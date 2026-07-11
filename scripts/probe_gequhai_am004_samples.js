#!/usr/bin/env node
'use strict';

const fs = require('fs/promises');
const path = require('path');
const http = require('http');
const https = require('https');
const { URL, URLSearchParams } = require('url');

const root = path.resolve(__dirname, '..');
const evidenceDir = path.join(root, 'evidence', 'script');
const reportDir = path.join(root, 'reports');

const samples = [
  { query: '外婆', expectedTitle: '外婆', expectedArtist: '周杰伦' },
  { query: '一丝不挂', expectedTitle: '一丝不挂', expectedArtist: '陈奕迅' },
  { query: '稻香', expectedTitle: '稻香', expectedArtist: '周杰伦' },
  { query: '哎呀', expectedTitle: '哎呀', expectedArtist: '王蓉' },
  {
    query: '东方财富',
    expectedTitle: '东方财富',
    expectedArtist: '',
    expectFailure: true,
  },
];

const userAgent =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

class CookieJar {
  constructor() {
    this.cookies = new Map();
  }

  add(setCookieHeaders) {
    for (const header of setCookieHeaders || []) {
      const first = String(header).split(';')[0];
      const index = first.indexOf('=');
      if (index <= 0) continue;
      this.cookies.set(first.slice(0, index).trim(), first.slice(index + 1).trim());
    }
  }

  header() {
    if (this.cookies.size === 0) return '';
    return [...this.cookies.entries()].map(([k, v]) => `${k}=${v}`).join('; ');
  }
}

function headersToLines(headers) {
  return Object.entries(headers)
    .map(([key, value]) => `${key}: ${Array.isArray(value) ? value.join(', ') : value}`)
    .join('\n');
}

async function request(url, options = {}, redirectDepth = 0) {
  await delay(options.delayMs ?? 1300);
  const uri = new URL(url);
  const transport = uri.protocol === 'http:' ? http : https;
  const method = options.method || 'GET';
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
      {
        method,
        headers,
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', async () => {
          const buffer = Buffer.concat(chunks);
          const location = res.headers.location;
          if (
            [301, 302, 303, 307, 308].includes(res.statusCode) &&
            location &&
            redirectDepth < 4
          ) {
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

function cleanText(value) {
  return decodeHtml(String(value || ''))
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
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
  return cleanText(match?.[1] || '').replace(/\s*(\[\d{2}:\d{2}(?:\.\d+)?\])/g, '\n$1').trim();
}

function extractDuration(html) {
  return /\b\d{2}:\d{2}\b/.exec(cleanText(html))?.[0] || '';
}

function extractExternalPan(html) {
  const direct = /https?:\/\/pan\.quark\.cn\/[^\s"'<>]+/i.exec(html)?.[0] || '';
  if (direct) return direct;
  let extra = extractJsString(html, 'mp3_extra_url');
  for (let i = 0; i < 3 && extra; i += 1) {
    const next = decodeURIComponentSafe(extra);
    if (next === extra) break;
    extra = next;
  }
  const modifiedBase64 = extra.replace(/#/g, 'H').replace(/%/g, 'S');
  try {
    const decoded = Buffer.from(modifiedBase64, 'base64').toString('utf8');
    const match = /https?:\/\/pan\.quark\.cn\/[^\s"'<>]+/i.exec(decoded)?.[0] || '';
    if (match) return match;
  } catch (_) {
    // Fall through to the raw decoded scan.
  }
  return /https?:\/\/pan\.quark\.cn\/[^\s"'<>]+/i.exec(extra)?.[0] || '';
}

function decodeURIComponentSafe(value) {
  try {
    return decodeURIComponent(value);
  } catch (_) {
    return value;
  }
}

function parseSearchResults(html) {
  const results = [];
  const seen = new Set();
  const linkPattern = /<a\b[^>]*href=["'](\/play\/(\d+))["'][^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = linkPattern.exec(html)) !== null) {
    const link = match[1];
    const id = match[2];
    if (seen.has(id)) continue;
    seen.add(id);
    const title = cleanText(match[3]);
    const start = Math.max(0, match.index - 500);
    const end = Math.min(html.length, linkPattern.lastIndex + 500);
    const context = cleanText(html.slice(start, end));
    const artist = guessArtist(context, title);
    results.push({
      rank: results.length + 1,
      id,
      title,
      artist,
      link: `https://www.gequhai.com${link}`,
      context: context.slice(0, 240),
    });
  }
  return results.slice(0, 8);
}

function guessArtist(context, title) {
  const text = cleanText(context);
  const titleIndex = text.indexOf(title);
  const after = titleIndex >= 0 ? text.slice(titleIndex + title.length, titleIndex + title.length + 120) : text;
  const parts = after
    .split(/[|\-_/，,：:]/)
    .map((part) => cleanText(part))
    .filter(Boolean);
  for (const part of parts) {
    if (part.length > 0 && part.length <= 12 && !part.includes('播放') && !part.includes('下载')) {
      return part;
    }
  }
  return '';
}

function matchScore(candidate, sample) {
  const titleMatch = normalize(candidate.title) === normalize(sample.expectedTitle);
  const artistMatch =
    !sample.expectedArtist ||
    normalize(candidate.artist).includes(normalize(sample.expectedArtist)) ||
    normalize(candidate.context).includes(normalize(sample.expectedArtist));
  if (titleMatch && artistMatch) return 1;
  if (titleMatch) return 0.6;
  return 0;
}

function classifyDefender(response) {
  const text = response.text.toLowerCase();
  return (
    response.status === 403 ||
    text.includes('安全验证') ||
    text.includes('just a moment') ||
    text.includes('forbidden')
  );
}

function parseContentLength(headers) {
  const raw = headers['content-length'];
  const value = Array.isArray(raw) ? raw[0] : raw;
  const parsed = Number.parseInt(value || '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function parseRangeTotal(contentRange) {
  const value = Array.isArray(contentRange) ? contentRange[0] : contentRange;
  const match = /bytes\s+\d+-\d+\/(\d+)/i.exec(value || '');
  if (!match) return null;
  const parsed = Number.parseInt(match[1], 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

async function writeEvidence(name, response, bodyExtension = 'html') {
  const safe = name.replace(/[^a-z0-9_-]+/gi, '-').toLowerCase();
  await fs.writeFile(
    path.join(evidenceDir, `${safe}.headers`),
    `status: ${response.status}\nurl: ${response.url}\nfinal-url: ${response.finalUrl}\n${headersToLines(response.headers)}\n`,
  );
  if (response.body && response.body.length > 0 && bodyExtension) {
    await fs.writeFile(path.join(evidenceDir, `${safe}.${bodyExtension}`), response.body);
  }
}

async function probeSample(sample, index) {
  const jar = new CookieJar();
  const idBase = `s${index + 1}-${Buffer.from(sample.query).toString('hex').slice(0, 16)}`;
  const searchUrl = `https://www.gequhai.com/s/${encodeURIComponent(sample.query)}`;
  const result = {
    query: sample.query,
    expectedTitle: sample.expectedTitle,
    expectedArtist: sample.expectedArtist,
    expectFailure: Boolean(sample.expectFailure),
    search: {},
    selectedCandidate: null,
    detail: null,
    api: null,
    audioValidation: null,
    lyrics: null,
    cover: null,
    externalPan: null,
    classification: 'unknown',
    failureCode: '',
    clientReady: false,
  };

  const search = await request(searchUrl, {
    headers: {
      accept:
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    },
  });
  jar.add(search.headers['set-cookie']);
  await writeEvidence(`${idBase}-search`, search, 'html');
  const candidates = parseSearchResults(search.text);
  result.search = {
    url: searchUrl,
    status: search.status,
    candidateCount: candidates.length,
    candidates: candidates.map((candidate) => ({
      rank: candidate.rank,
      id: candidate.id,
      title: candidate.title,
      artist: candidate.artist,
      link: candidate.link,
      matchScore: matchScore(candidate, sample),
    })),
  };
  if (classifyDefender(search)) {
    result.classification = 'security_or_defender';
    result.failureCode = 'security_or_defender';
    return result;
  }

  const selected =
    candidates
      .map((candidate) => ({ candidate, score: matchScore(candidate, sample) }))
      .filter((entry) => entry.score >= 0.6)
      .sort((a, b) => b.score - a.score)[0]?.candidate || null;
  result.selectedCandidate = selected
    ? {
        rank: selected.rank,
        id: selected.id,
        title: selected.title,
        artist: selected.artist,
        link: selected.link,
        matchScore: matchScore(selected, sample),
      }
    : null;
  if (!selected || sample.expectFailure) {
    result.classification = selected && sample.expectFailure ? 'low_confidence_match' : 'no_search_match';
    result.failureCode = result.classification;
    return result;
  }

  let page = await request(selected.link, {
    headers: {
      accept:
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      ...(jar.header() ? { cookie: jar.header() } : {}),
    },
  });
  jar.add(page.headers['set-cookie']);
  if (classifyDefender(page)) {
    const retry = await request(selected.link, {
      headers: {
        accept:
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        ...(jar.header() ? { cookie: jar.header() } : {}),
      },
    });
    jar.add(retry.headers['set-cookie']);
    page = retry;
  }
  await writeEvidence(`${idBase}-play-${selected.id}`, page, 'html');
  if (classifyDefender(page)) {
    result.classification = 'security_or_defender';
    result.failureCode = 'security_or_defender';
    return result;
  }

  const playId = extractJsString(page.text, 'play_id');
  const title = cleanText(extractJsString(page.text, 'mp3_title'));
  const artist = cleanText(extractJsString(page.text, 'mp3_author'));
  const coverUrl = extractJsString(page.text, 'mp3_cover');
  const lrc = extractLrc(page.text);
  const externalPan = extractExternalPan(page.text);
  result.detail = {
    url: selected.link,
    status: page.status,
    mp3Id: extractJsString(page.text, 'mp3_id') || selected.id,
    playId,
    title,
    artist,
    duration: extractDuration(page.text),
    cookieJarNames: [...jar.cookies.keys()],
  };
  result.lyrics = {
    source: 'page:#content-lrc2',
    lineCount: lrc ? lrc.split(/\n+/).filter(Boolean).length : 0,
    sample: lrc.split(/\n+/).filter(Boolean).slice(0, 8),
  };
  result.cover = {
    source: 'page:window.mp3_cover',
    url: coverUrl,
  };
  result.externalPan = externalPan
    ? { url: externalPan, classification: 'external_pan_link' }
    : null;
  if (!playId) {
    result.classification = 'play_url_unavailable';
    result.failureCode = 'play_url_unavailable';
    return result;
  }
  if (
    normalize(title) !== normalize(sample.expectedTitle) ||
    (sample.expectedArtist && normalize(artist) !== normalize(sample.expectedArtist))
  ) {
    result.classification = 'low_confidence_match';
    result.failureCode = 'low_confidence_match';
    return result;
  }

  const body = new URLSearchParams({ id: playId, type: '0' }).toString();
  const api = await request('https://www.gequhai.com/api/music', {
    method: 'POST',
    headers: {
      origin: 'https://www.gequhai.com',
      referer: selected.link,
      'x-requested-with': 'Http',
      'x-custom-header': 'Key',
      'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
      accept: 'application/json, text/javascript, */*; q=0.01',
      ...(jar.header() ? { cookie: jar.header() } : {}),
    },
    body,
  });
  jar.add(api.headers['set-cookie']);
  await writeEvidence(`${idBase}-api-${selected.id}`, api, 'json');
  let apiJson = {};
  try {
    apiJson = JSON.parse(api.text);
  } catch (_) {
    apiJson = {};
  }
  const audioUrl = apiJson?.data?.url || apiJson?.url || '';
  result.api = {
    url: 'https://www.gequhai.com/api/music',
    status: api.status,
    responseCode: apiJson?.code ?? null,
    responseMessage: apiJson?.msg ?? '',
    requestHeaders: {
      origin: 'https://www.gequhai.com',
      referer: selected.link,
      'x-requested-with': 'Http',
      'x-custom-header': 'Key',
      cookieJar: jar.header() ? 'present' : 'empty',
    },
    audioUrl,
  };
  if (api.status < 200 || api.status >= 300 || apiJson?.code !== 200 || !audioUrl) {
    result.classification = 'play_url_unavailable';
    result.failureCode = 'play_url_unavailable';
    return result;
  }

  const head = await request(audioUrl, {
    method: 'HEAD',
    headers: {
      accept: '*/*',
    },
  });
  await writeEvidence(`${idBase}-audio-head-${selected.id}`, head, null);
  const range = await request(audioUrl, {
    headers: {
      accept: '*/*',
      range: 'bytes=0-8191',
    },
  });
  await writeEvidence(`${idBase}-audio-range-0-8191-${selected.id}`, range, 'bin');
  const headType = String(head.headers['content-type'] || '').toLowerCase();
  const rangeType = String(range.headers['content-type'] || '').toLowerCase();
  const headLength = parseContentLength(head.headers);
  const rangeTotal = parseRangeTotal(range.headers['content-range']);
  result.audioValidation = {
    head: {
      status: head.status,
      contentType: headType,
      contentLength: headLength,
      acceptRanges: head.headers['accept-ranges'] || '',
    },
    range: {
      status: range.status,
      contentType: rangeType,
      contentRange: range.headers['content-range'] || '',
      rangeTotal,
      bytesRead: range.body.length,
    },
  };

  if (head.status !== 200 || !headType.startsWith('audio/')) {
    result.classification = 'non_audio_content';
    result.failureCode = 'non_audio_content';
    return result;
  }
  if (range.status !== 206 || !rangeType.startsWith('audio/') || !rangeTotal) {
    result.classification = 'range_not_supported';
    result.failureCode = 'range_not_supported';
    return result;
  }
  if (!headLength && !rangeTotal) {
    result.classification = 'audio_validation_failed';
    result.failureCode = 'audio_validation_failed';
    return result;
  }

  result.classification = 'direct_full_audio';
  result.failureCode = '';
  result.clientReady = true;
  return result;
}

function markdownTable(rows) {
  const header =
    '| query | selected | search | detail | audio | lyrics | cover | classification |\n' +
    '| --- | --- | --- | --- | --- | --- | --- | --- |';
  return [
    header,
    ...rows.map((row) => {
      const selected = row.selectedCandidate
        ? `${row.selectedCandidate.title}/${row.detail?.artist || row.selectedCandidate.artist || ''} ${row.selectedCandidate.link}`
        : 'none';
      const search = row.search
        ? `status=${row.search.status} candidates=${row.search.candidateCount}`
        : 'not_reached';
      const detail = row.detail
        ? `id=${row.detail.mp3Id} play_id=${row.detail.playId || 'missing'} title=${row.detail.title}/${row.detail.artist}`
        : 'not_reached';
      const audio = row.audioValidation
        ? `HEAD ${row.audioValidation.head.status} ${row.audioValidation.head.contentType} len=${row.audioValidation.head.contentLength || row.audioValidation.range.rangeTotal}; Range ${row.audioValidation.range.status} ${row.audioValidation.range.contentRange}`
        : 'not_reached';
      const lyrics = row.lyrics ? `${row.lyrics.lineCount} lines` : 'not_reached';
      const cover = row.cover?.url ? 'ok' : 'missing';
      return `| ${row.query} | ${selected} | ${search} | ${detail} | ${audio} | ${lyrics} | ${cover} | ${row.classification || row.failureCode} |`;
    }),
  ].join('\n');
}

async function main() {
  await fs.mkdir(evidenceDir, { recursive: true });
  await fs.mkdir(reportDir, { recursive: true });
  const startedAt = new Date().toISOString();
  const results = [];
  for (const [index, sample] of samples.entries()) {
    console.log(`[gequhai] probing ${sample.query}`);
    try {
      results.push(await probeSample(sample, index));
    } catch (error) {
      results.push({
        query: sample.query,
        expectedTitle: sample.expectedTitle,
        expectedArtist: sample.expectedArtist,
        classification: 'probe_error',
        failureCode: 'probe_error',
        error: String(error && error.stack ? error.stack : error),
      });
    }
  }
  const finishedAt = new Date().toISOString();
  const payload = {
    request: 'AM-20260711-004',
    workflow: 'superpowers-v1',
    lane: 'source-researcher',
    generatedAt: finishedAt,
    startedAt,
    policy: 'low_frequency_serial_search_detail_api_head_range',
    samples: results,
    clientEligible: results
      .filter((row) => row.clientReady && row.classification === 'direct_full_audio')
      .map((row) => ({
        query: row.query,
        title: row.detail.title,
        artist: row.detail.artist,
        playPage: row.detail.url,
        playId: row.detail.playId,
        audioUrl: row.api.audioUrl,
        contentLength:
          row.audioValidation.head.contentLength || row.audioValidation.range.rangeTotal,
        lyricsLines: row.lyrics.lineCount,
        coverUrl: row.cover.url,
      })),
    failClosed: results
      .filter((row) => !row.clientReady)
      .map((row) => ({
        query: row.query,
        classification: row.classification,
        failureCode: row.failureCode,
      })),
  };
  const jsonPath = path.join(evidenceDir, 'gequhai-am004-multisample-result.json');
  await fs.writeFile(jsonPath, `${JSON.stringify(payload, null, 2)}\n`);
  const report = [
    '# AM-20260711-004 Gequhai 多样例完整音频复核',
    '',
    `Generated: ${finishedAt}`,
    'Lane: source-researcher',
    'Workflow: superpowers-v1',
    '',
    '## Summary',
    '',
    `- Policy: ${payload.policy}`,
    `- Client eligible: ${payload.clientEligible.map((row) => `${row.title}/${row.artist}`).join(', ') || 'none'}`,
    `- Fail closed: ${payload.failClosed.map((row) => `${row.query}:${row.failureCode}`).join(', ') || 'none'}`,
    '',
    '## Status Table',
    '',
    markdownTable(results),
    '',
    '## Evidence',
    '',
    `- JSON: ${jsonPath}`,
    `- Raw headers/html/bin: ${evidenceDir}`,
    '',
    '## Minimal Client Protocol',
    '',
    '1. GET `/s/{keyword}` with a cookie jar; select only high-confidence title/artist matches.',
    '2. GET `/play/{id}` with the same cookie jar; retry once only when a defender page sets cookies.',
    '3. Parse `window.play_id`, `window.mp3_title`, `window.mp3_author`, `window.mp3_cover`, `window.mp3_extra_url`, and `#content-lrc2`.',
    '4. POST `/api/music` with `id=<play_id>&type=0`, `Origin`, page `Referer`, `X-Requested-With: Http`, `X-Custom-Header: Key`, and the page cookie jar.',
    '5. Validate final CDN with no gequhai referer: HEAD `200 audio/*` plus Range `206` and positive length/total.',
    '6. Only `direct_full_audio` may enter client search results, transient streaming, or formal cache.',
    '',
    '## Failure Classification',
    '',
    '- `no_search_match` / `low_confidence_match`: do not display as a playable result.',
    '- `external_pan_link`: Quark evidence only, never a completion path.',
    '- `security_or_defender`: stop after one low-frequency retry.',
    '- `play_url_unavailable`: API or page did not provide a usable player URL.',
    '- `non_audio_content`: HEAD/Range did not return audio.',
    '- `range_not_supported`: Range was not 206 or total was missing.',
    '',
  ].join('\n');
  const reportPath = path.join(reportDir, 'am004-gequhai-multisample-status.md');
  await fs.writeFile(reportPath, report);
  console.log(`[gequhai] wrote ${jsonPath}`);
  console.log(`[gequhai] wrote ${reportPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
