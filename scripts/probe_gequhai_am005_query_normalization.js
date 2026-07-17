#!/usr/bin/env node
'use strict';

const fs = require('fs/promises');
const path = require('path');
const http = require('http');
const https = require('https');
const { URL, URLSearchParams } = require('url');

const root = path.resolve(__dirname, '..');
const evidenceDir = path.join(root, 'evidence', 'script', 'am005-query-normalization');
const reportDir = path.join(root, 'reports');

const userAgent =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

const cases = [
  {
    id: 'zhoujielun-artist-only',
    rawQuery: '周杰伦',
    expectedTitle: '',
    expectedArtist: '周杰伦',
    artistOnly: true,
    variants: [
      { label: 'raw', query: '周杰伦', reason: 'QA/Product artist-only input' },
    ],
  },
  {
    id: 'zhoujielun-de-waipo',
    rawQuery: '周杰伦的外婆',
    expectedTitle: '外婆',
    expectedArtist: '周杰伦',
    variants: [
      { label: 'raw', query: '周杰伦的外婆', reason: 'QA exact input' },
      { label: 'title-only', query: '外婆', reason: 'possessive 的 normalization title term' },
      { label: 'artist-title-space', query: '周杰伦 外婆', reason: 'artist title spaced fallback' },
    ],
  },
  {
    id: 'huangrong-de-aiya',
    rawQuery: '黄蓉的哎呀',
    expectedTitle: '哎呀',
    expectedArtist: '王蓉',
    artistHint: '黄蓉',
    variants: [
      { label: 'raw', query: '黄蓉的哎呀', reason: 'QA exact input' },
      { label: 'title-only', query: '哎呀', reason: 'possessive 的 normalization title term' },
      { label: 'artist-title-space', query: '黄蓉 哎呀', reason: 'typed artist hint with title' },
    ],
  },
  {
    id: 'shengxiadeguoshi',
    rawQuery: '剩下的果实',
    expectedTitle: '剩下的果实',
    expectedArtist: '',
    variants: [
      { label: 'raw', query: '剩下的果实', reason: 'QA exact input' },
    ],
  },
];

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

class CookieJar {
  constructor() {
    this.cookies = new Map();
  }

  add(headers) {
    for (const header of headers || []) {
      const first = String(header).split(';')[0];
      const index = first.indexOf('=');
      if (index <= 0) continue;
      this.cookies.set(first.slice(0, index).trim(), first.slice(index + 1).trim());
    }
  }

  header() {
    return [...this.cookies.entries()].map(([k, v]) => `${k}=${v}`).join('; ');
  }
}

async function request(url, options = {}, redirectDepth = 0) {
  await delay(options.delayMs ?? 1400);
  const uri = new URL(url);
  const transport = uri.protocol === 'http:' ? http : https;
  const headers = {
    'user-agent': userAgent,
    accept: '*/*',
    ...(options.headers || {}),
  };
  const body = options.body || null;
  if (body && !headers['content-length']) {
    headers['content-length'] = Buffer.byteLength(body);
  }
  return new Promise((resolve, reject) => {
    const req = transport.request(
      uri,
      { method: options.method || 'GET', headers },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', async () => {
          const buffer = Buffer.concat(chunks);
          const location = res.headers.location;
          if ([301, 302, 303, 307, 308].includes(res.statusCode) && location && redirectDepth < 4) {
            const redirected = new URL(location, uri).toString();
            resolve(await request(redirected, options, redirectDepth + 1));
            return;
          }
          resolve({
            url,
            finalUrl: uri.toString(),
            status: res.statusCode,
            headers: res.headers,
            body: buffer,
            text: buffer.toString('utf8'),
          });
        });
      },
    );
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

function decodeHtml(value) {
  return String(value || '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ');
}

function cleanText(value) {
  return decodeHtml(String(value || ''))
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalize(value) {
  return cleanText(value)
    .toLowerCase()
    .replace(/[《》「」『』【】\[\]\(\)（）·\-\s_]/g, '');
}

function extractJsString(html, name) {
  const pattern = new RegExp(`(?:window\\.)?${name}\\s*=\\s*['"]([^'"]*)['"]`, 'i');
  return decodeHtml(pattern.exec(html)?.[1] || '').trim();
}

function extractLrc(html) {
  const match = /<[^>]+id=["']content-lrc2["'][^>]*>([\s\S]*?)<\/[^>]+>/i.exec(html);
  return cleanText(match?.[1] || '')
    .replace(/\s*(\[\d{2}:\d{2}(?:\.\d+)?\])/g, '\n$1')
    .trim();
}

function extractExternalPan(html) {
  const direct = /https?:\/\/pan\.quark\.cn\/[^\s"'<>]+/i.exec(html)?.[0] || '';
  if (direct) return direct;
  const extra = extractJsString(html, 'mp3_extra_url');
  if (!extra) return '';
  const variants = new Set([extra]);
  let decoded = extra;
  for (let i = 0; i < 3; i += 1) {
    try {
      const next = decodeURIComponent(decoded);
      variants.add(next);
      if (next === decoded) break;
      decoded = next;
    } catch (_) {
      break;
    }
  }
  try {
    variants.add(Buffer.from(extra.replace(/#/g, 'H').replace(/%/g, 'S'), 'base64').toString('utf8'));
  } catch (_) {
    // Evidence only; ignore malformed optional pan data.
  }
  for (const variant of variants) {
    const found = /https?:\/\/pan\.quark\.cn\/[^\s"'<>]+/i.exec(variant)?.[0] || '';
    if (found) return found;
  }
  return '';
}

function parseSearchResults(html) {
  const rows = [];
  const rowPattern = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
  let rowMatch;
  while ((rowMatch = rowPattern.exec(html)) !== null) {
    const rowHtml = rowMatch[1] || '';
    const parsed = parseSearchRow(rowHtml);
    if (parsed) rows.push(parsed);
  }
  if (rows.length > 0) return rows.slice(0, 12);

  const links = [];
  const linkPattern = /<a\b[^>]*href=["'](\/play\/(\d+))["'][^>]*>([\s\S]*?)<\/a>/gi;
  let linkMatch;
  while ((linkMatch = linkPattern.exec(html)) !== null) {
    const title = cleanText(linkMatch[3] || '');
    if (!title) continue;
    links.push({
      id: linkMatch[2] || '',
      title,
      artist: '',
      detailUrl: `https://www.gequhai.com${linkMatch[1]}`,
      rowText: cleanText(linkMatch[0] || ''),
    });
  }
  return links.slice(0, 12);
}

function parseSearchRow(rowHtml) {
  const linkMatch = /<a\b[^>]*href=["'](\/play\/(\d+))["'][^>]*>([\s\S]*?)<\/a>/i.exec(rowHtml);
  if (!linkMatch) return null;
  const title = cleanText(linkMatch[3] || '');
  const rowText = cleanText(rowHtml).replace(/\s+/g, ' ');
  const artist = extractSearchArtist(rowText, title);
  if (!title) return null;
  return {
    id: linkMatch[2] || '',
    title,
    artist,
    detailUrl: `https://www.gequhai.com${linkMatch[1]}`,
    rowText,
  };
}

function extractSearchArtist(rowText, title) {
  const withoutTitle = rowText.replace(title, '').trim();
  const parts = withoutTitle
    .split(/[\s|/／\-—–]+/)
    .map((part) => part.trim())
    .filter(Boolean);
  return parts.reverse().find((part) => !/^\d+$/.test(part)) || '';
}

function scoreCandidate(candidate, spec) {
  if (spec.artistOnly) {
    const artistExact =
      normalize(candidate.artist) === normalize(spec.expectedArtist) ||
      normalize(candidate.rowText).includes(normalize(spec.expectedArtist));
    return artistExact
      ? { confidence: 0.86, reason: 'artist_exact_list_candidate' }
      : { confidence: 0, reason: 'no_artist_match' };
  }
  const titleExact = normalize(candidate.title) === normalize(spec.expectedTitle);
  const artistExact =
    !spec.expectedArtist ||
    normalize(candidate.artist) === normalize(spec.expectedArtist) ||
    normalize(candidate.rowText).includes(normalize(spec.expectedArtist));
  const artistNear =
    spec.artistHint &&
    candidate.artist &&
    isSingleCharacterCorrection(normalize(spec.artistHint), normalize(candidate.artist));
  if (titleExact && artistExact) return { confidence: 1, reason: 'title_artist_exact' };
  if (titleExact && artistNear) return { confidence: 0.78, reason: 'title_exact_artist_near_match' };
  if (titleExact) return { confidence: 0.65, reason: 'title_exact_artist_missing_or_mismatch' };
  return { confidence: 0, reason: 'no_title_match' };
}

function isSingleCharacterCorrection(expected, actual) {
  if (!expected || expected.length !== actual.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i += 1) {
    if (expected[i] !== actual[i]) diff += 1;
  }
  return diff === 1;
}

function classifySearchMiss(searchStatus, results) {
  if (searchStatus === 403) return 'security_or_defender';
  if (searchStatus < 200 || searchStatus >= 300) return `provider_http_${searchStatus}`;
  if (results.length === 0) return 'no_search_match';
  return 'low_confidence_match';
}

function parseContentLength(headers) {
  const raw = headers['content-length'];
  const value = Array.isArray(raw) ? raw[0] : raw;
  const parsed = Number.parseInt(value || '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function parseRangeTotal(headers) {
  const raw = headers['content-range'];
  const value = Array.isArray(raw) ? raw[0] : raw;
  const match = /bytes\s+\d+-\d+\/(\d+)/i.exec(value || '');
  if (!match) return null;
  const parsed = Number.parseInt(match[1], 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function headersToLines(headers) {
  return Object.entries(headers)
    .map(([key, value]) => `${key}: ${Array.isArray(value) ? value.join(', ') : value}`)
    .join('\n');
}

async function writeResponse(name, response, extension) {
  const bodyPath = path.join(evidenceDir, `${name}.${extension}`);
  const headersPath = path.join(evidenceDir, `${name}.headers`);
  await fs.writeFile(bodyPath, response.body);
  await fs.writeFile(
    headersPath,
    [
      `${response.status} ${response.finalUrl}`,
      headersToLines(response.headers),
      '',
    ].join('\n'),
  );
  return { bodyPath, headersPath };
}

async function probeVariant(spec, variant, variantIndex) {
  const prefix = `${spec.id}-${variantIndex + 1}-${variant.label}`;
  const jar = new CookieJar();
  const searchUrl = `https://www.gequhai.com/s/${encodeURIComponent(variant.query)}`;
  const search = await request(searchUrl, {
    headers: {
      accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    },
  });
  jar.add(search.headers['set-cookie']);
  const searchEvidence = await writeResponse(`${prefix}-search`, search, 'html');
  const results = parseSearchResults(search.text).map((candidate, index) => {
    const score = scoreCandidate(candidate, spec);
    return { rank: index + 1, ...candidate, ...score };
  });
  const best = results.find((candidate) => candidate.confidence >= 0.78) ||
    results.find((candidate) => candidate.confidence >= 0.65);

  const variantResult = {
    label: variant.label,
    query: variant.query,
    reason: variant.reason,
    searchUrl,
    searchStatus: search.status,
    searchEvidence,
    candidates: results,
    selected: null,
    sourceAttempts: [
      {
        stage: 'search',
        status: search.status >= 200 && search.status < 300 ? 'ok' : 'failed',
        failureCode: search.status >= 200 && search.status < 300 ? '' : `provider_http_${search.status}`,
        evidencePath: searchEvidence.bodyPath,
      },
    ],
  };

  if (!best) {
    variantResult.finalStatus = classifySearchMiss(search.status, results);
    variantResult.finalReason = '没有满足 title/artist 置信阈值的候选。';
    return variantResult;
  }

  const detail = await request(best.detailUrl, {
    headers: {
      accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      referer: searchUrl,
      ...(jar.header() ? { cookie: jar.header() } : {}),
    },
  });
  jar.add(detail.headers['set-cookie']);
  const detailEvidence = await writeResponse(`${prefix}-play-${best.id}`, detail, 'html');
  const playId = extractJsString(detail.text, 'play_id') || extractJsString(detail.text, 'mp3_id') || best.id;
  const pageTitle = cleanText(extractJsString(detail.text, 'mp3_title')) || best.title;
  const pageArtist = cleanText(extractJsString(detail.text, 'mp3_author')) || best.artist;
  const coverUrl = new URL(extractJsString(detail.text, 'mp3_cover') || '', best.detailUrl).toString();
  const lyrics = extractLrc(detail.text);
  const externalPan = extractExternalPan(detail.text);
  variantResult.sourceAttempts.push({
    stage: 'detail',
    status: detail.status >= 200 && detail.status < 300 ? 'ok' : 'failed',
    failureCode: detail.status >= 200 && detail.status < 300 ? '' : `provider_http_${detail.status}`,
    evidencePath: detailEvidence.bodyPath,
  });
  variantResult.selected = {
    ...best,
    playId,
    pageTitle,
    pageArtist,
    coverUrl,
    lyricsLines: lyrics ? lyrics.split(/\n/).filter(Boolean).length : 0,
    lyricsSample: lyrics.split(/\n/).slice(0, 3),
    externalPanEvidence: externalPan ? 'present_non_completion_path' : 'missing',
  };

  const apiBody = new URLSearchParams({ id: playId, type: '0' }).toString();
  const api = await request('https://www.gequhai.com/api/music', {
    method: 'POST',
    body: apiBody,
    headers: {
      accept: 'application/json, text/javascript, */*; q=0.01',
      'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
      origin: 'https://www.gequhai.com',
      referer: best.detailUrl,
      'x-requested-with': 'Http',
      'x-custom-header': 'Key',
      ...(jar.header() ? { cookie: jar.header() } : {}),
    },
  });
  const apiEvidence = await writeResponse(`${prefix}-api-${playId}`, api, 'json');
  variantResult.sourceAttempts.push({
    stage: 'api',
    status: api.status >= 200 && api.status < 300 ? 'ok' : 'failed',
    failureCode: api.status >= 200 && api.status < 300 ? '' : `provider_http_${api.status}`,
    evidencePath: apiEvidence.bodyPath,
    requestHeaders: {
      origin: 'https://www.gequhai.com',
      referer: best.detailUrl,
      'x-requested-with': 'Http',
      'x-custom-header': 'Key',
      cookie: jar.header() ? 'present' : 'missing',
    },
  });

  let audioUrl = '';
  try {
    const decoded = JSON.parse(api.text);
    audioUrl = String(decoded?.data?.url || decoded?.url || '').trim();
  } catch (_) {
    variantResult.finalStatus = 'anticc_non_json';
    variantResult.finalReason = '播放器 API 返回非 JSON。';
    return variantResult;
  }
  if (!audioUrl) {
    variantResult.finalStatus = 'play_url_unavailable';
    variantResult.finalReason = '播放器 API 未返回音频 URL。';
    return variantResult;
  }

  const head = await request(audioUrl, {
    method: 'HEAD',
    headers: { accept: '*/*' },
  });
  const headEvidence = await writeResponse(`${prefix}-audio-head-${playId}`, head, 'bin');
  const range = await request(audioUrl, {
    headers: {
      accept: '*/*',
      range: 'bytes=0-8191',
    },
  });
  const rangeEvidence = await writeResponse(`${prefix}-audio-range-0-8191-${playId}`, range, 'bin');
  const headType = String(head.headers['content-type'] || '').toLowerCase();
  const rangeType = String(range.headers['content-type'] || '').toLowerCase();
  const headLength = parseContentLength(head.headers);
  const rangeTotal = parseRangeTotal(range.headers);
  const directOk =
    head.status === 200 &&
    headType.startsWith('audio/') &&
    range.status === 206 &&
    rangeType.startsWith('audio/') &&
    rangeTotal !== null;

  variantResult.sourceAttempts.push({
    stage: 'media_validation',
    status: directOk ? 'ok' : 'failed',
    failureCode: directOk ? '' : 'audio_validation_failed',
    evidencePath: rangeEvidence.headersPath,
    noReferer: true,
    head: {
      status: head.status,
      contentType: headType,
      contentLength: headLength,
      evidencePath: headEvidence.headersPath,
    },
    range: {
      status: range.status,
      contentType: rangeType,
      contentRange: range.headers['content-range'] || '',
      totalLength: rangeTotal,
      evidencePath: rangeEvidence.headersPath,
    },
  });
  variantResult.audioUrl = audioUrl;
  variantResult.finalStatus = directOk ? 'direct_full_audio' : 'audio_validation_failed';
  variantResult.finalReason = directOk
    ? 'HEAD 200 audio + Range 206 audio 通过，可脚本化完整音频。'
    : '媒体 HEAD/Range 未通过完整音频门禁。';
  return variantResult;
}

async function main() {
  await fs.mkdir(evidenceDir, { recursive: true });
  await fs.mkdir(reportDir, { recursive: true });
  const startedAt = new Date().toISOString();
  const output = {
    request: 'AM-20260711-005',
    lane: 'source-researcher',
    startedAt,
    policy: 'low_frequency_serial_requests_no_pan_download_no_concurrency',
    cases: [],
  };

  for (const spec of cases) {
    const caseResult = {
      id: spec.id,
      rawQuery: spec.rawQuery,
      expectedTitle: spec.expectedTitle,
      expectedArtist: spec.expectedArtist,
      artistHint: spec.artistHint || '',
      normalization: spec.variants.map((variant) => ({
        label: variant.label,
        query: variant.query,
        reason: variant.reason,
      })),
      variants: [],
      conclusion: '',
    };
    for (let index = 0; index < spec.variants.length; index += 1) {
      caseResult.variants.push(await probeVariant(spec, spec.variants[index], index));
    }
    const direct = caseResult.variants.find((variant) => variant.finalStatus === 'direct_full_audio');
    if (direct) {
      const selected = direct.selected || {};
      const artistHintDiffers =
        spec.artistHint && normalize(spec.artistHint) !== normalize(selected.pageArtist);
      const exactArtist =
        !spec.expectedArtist ||
        normalize(selected.pageArtist) === normalize(spec.expectedArtist);
      const nearArtist =
        spec.artistHint &&
        selected.pageArtist &&
        isSingleCharacterCorrection(normalize(spec.artistHint), normalize(selected.pageArtist));
      caseResult.conclusion = spec.artistOnly && exactArtist
        ? 'client_ready_artist_only_high_confidence'
        : artistHintDiffers && nearArtist
        ? 'client_ready_title_exact_artist_near_match_requires_explanation'
        : exactArtist && !artistHintDiffers
        ? 'client_ready_high_confidence'
        : 'client_ready_title_only_low_confidence';
    } else {
      caseResult.conclusion = 'no_client_ready_candidate';
    }
    output.cases.push(caseResult);
  }

  output.finishedAt = new Date().toISOString();
  const jsonPath = path.join(evidenceDir, 'gequhai-am005-query-normalization-result.json');
  await fs.writeFile(jsonPath, JSON.stringify(output, null, 2));
  const reportPath = path.join(reportDir, 'am005-gequhai-query-normalization-status.md');
  await fs.writeFile(reportPath, buildReport(output, jsonPath));
  console.log(JSON.stringify({ jsonPath, reportPath }, null, 2));
}

function buildReport(output, jsonPath) {
  const lines = [
    '# AM-005 歌曲海 query normalization 复核',
    '',
    `- JSON: \`${jsonPath}\``,
    `- Policy: \`${output.policy}\``,
    `- Started: \`${output.startedAt}\``,
    `- Finished: \`${output.finishedAt}\``,
    '',
    '## 结论表',
    '',
    '| raw query | 结论 | 可进入客户端完整结果 | 关键 normalized 链路 | 说明 |',
    '| --- | --- | --- | --- | --- |',
  ];
  for (const item of output.cases) {
    const direct = item.variants.find((variant) => variant.finalStatus === 'direct_full_audio');
    const raw = item.variants.find((variant) => variant.label === 'raw');
    const canClient = item.conclusion === 'client_ready_high_confidence' ? '是' :
      item.conclusion === 'client_ready_artist_only_high_confidence' ? '是，作为歌手列表候选' :
      item.conclusion.includes('near_match') ? '可展示但需解释/保留真实 artist' : '否';
    const key = direct
      ? `${direct.label}: ${direct.selected?.pageTitle || ''}/${direct.selected?.pageArtist || ''}/detail ${direct.selected?.id || ''}/api_play_id ${direct.selected?.playId || ''}`
      : `raw=${raw?.finalStatus || 'unknown'}`;
    const note = direct
      ? `${direct.finalReason}${raw && raw.finalStatus !== 'direct_full_audio' ? `；raw query 为 ${raw.finalStatus}` : ''}`
      : item.variants.map((variant) => `${variant.label}:${variant.finalStatus}`).join('; ');
    lines.push(`| ${item.rawQuery} | ${item.conclusion} | ${canClient} | ${key} | ${note} |`);
  }
  lines.push('', '## 每条 query 的候选与失败链');
  for (const item of output.cases) {
    lines.push('', `### ${item.rawQuery}`, '');
    for (const variant of item.variants) {
      lines.push(`- ${variant.label} \`${variant.query}\`: ${variant.finalStatus}；${variant.finalReason || ''}`);
      if (variant.selected) {
        lines.push(
          `  - selected: title=\`${variant.selected.pageTitle}\`, artist=\`${variant.selected.pageArtist}\`, detail=\`${variant.selected.detailUrl}\`, detail_id=\`${variant.selected.id}\`, api_play_id=\`${variant.selected.playId}\`, confidence=\`${variant.selected.confidence}\`, reason=\`${variant.selected.reason}\``,
        );
        lines.push(
          `  - media: HEAD=\`${variant.sourceAttempts.at(-1)?.head?.status || ''}\`, Range=\`${variant.sourceAttempts.at(-1)?.range?.status || ''}\`, total=\`${variant.sourceAttempts.at(-1)?.range?.totalLength || ''}\`, lyricsLines=\`${variant.selected.lyricsLines}\`, cover=\`${variant.selected.coverUrl ? 'present' : 'missing'}\``,
        );
      }
      if (variant.candidates.length > 0) {
        const brief = variant.candidates
          .slice(0, 3)
          .map((candidate) => `${candidate.rank}.${candidate.title}/${candidate.artist || '?'} play/${candidate.id} c=${candidate.confidence} ${candidate.reason}`)
          .join('; ');
        lines.push(`  - candidates: ${brief}`);
      }
    }
  }
  lines.push('', '## 客户端最小协议建议', '');
  lines.push('- 对 `artist的title` 先解析为 `artistHint` + `titleQuery`，歌曲海 search 只发 `titleQuery`；raw query miss 不能直接判源站无歌。');
  lines.push('- 对纯歌手 query 允许按 artist-only 列表召回；每个可操作候选仍必须通过详情 artist 校验和 media gate，不能把合集/错歌手低置信行当完成路径。');
  lines.push('- 候选详情页必须重新校验 `mp3_title/mp3_author/play_id`；`artistHint` 与真实 artist 精确一致才是高置信自动完整结果。');
  lines.push('- `黄蓉的哎呀` 只能作为 `title_exact_artist_near_match`：展示真实 `哎呀/王蓉` 并保留纠错说明，不得把 artist 写成 `黄蓉`。');
  lines.push('- 完整结果仍需 page -> `/api/music` -> CDN no-referer HEAD 200 audio -> Range 206 audio/totalLength 正数；夸克只作 evidence，不进入完成路径。');
  lines.push('');
  return `${lines.join('\n')}\n`;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
