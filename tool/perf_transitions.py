#!/usr/bin/env python3
"""Summarize the app's page-change checks (perf.transition / perf.transitions)
from an uploaded diagnostics report or an operations.jsonl.

  python3 tool/perf_transitions.py                 # newest uploaded report
  python3 tool/perf_transitions.py <reportId|file> # one report or log file

Hints and what fixed each before: docs/performance-diagnostics.md.
"""
import argparse
import json
from collections import defaultdict
from pathlib import Path

DEFAULT_ROOT = Path('/Users/huangqi/ClaudeProject/releases/ai_music/diagnostics')

HINTS = {
    'first_frame_build': '首帧构建重：新页面一次性构建/布局过多（列表行、同步计算）',
    'notify_mid_slide': '过场中有全应用通知：看 notifies 的 caller，推到 afterRouteEntrance 之后',
    'ui_mid_slide': '过场中 UI 重：重复重建、流重放、图片解码或布局抖动',
    'raster_first_open': '首开光栅重：多为 Skia 着色器首次编译（进程内首次绘制该效果）',
    'raster_heavy': '光栅持续重：半透明图层(saveLayer)、模糊、阴影或大图叠画',
    'notify_after_slide': '滑入刚结束就有全应用通知让整页重建：此时立刻滑动会顿，减少通知范围',
}


def load_operations(source, root=DEFAULT_ROOT):
    """Operations from a report id, report file, operations.jsonl or, with no
    source, the newest report under root."""
    if source is None:
        reports = sorted(root.glob('*.json'), key=lambda p: p.stat().st_mtime)
        if not reports:
            raise SystemExit(f'No reports under {root}')
        path = reports[-1]
    else:
        path = Path(source)
        if not path.exists():
            path = root / f'{source}.json'
    text = path.read_text(encoding='utf-8')
    if path.suffix == '.jsonl':
        return path, [json.loads(line) for line in text.splitlines() if line.strip()]
    document = json.loads(text)
    payload = document.get('payload', document)
    return path, payload.get('operations', [])


def latest_session(operations):
    """The newest app session that logged page changes."""
    for entry in reversed(operations):
        if str(entry.get('operation', '')).startswith('perf.transition'):
            return entry.get('session')
    return None


def summarize(operations, session=None):
    """Per page: changes seen, janky ones, dropped frames, worst frames and
    the hints the janky ones carried; plus the janky entries themselves."""
    pages = defaultdict(lambda: {'n': 0, 'janky': 0, 'dropped': 0, 'worstUiMs': 0.0,
                                 'worstRasterMs': 0.0, 'logged': 0,
                                 'hints': defaultdict(int)})
    janky = []
    for entry in operations:
        if session is not None and entry.get('session') != session:
            continue
        name = entry.get('operation')
        details = entry.get('details') or {}
        if name == 'perf.transitions':
            for key, stats in (details.get('pages') or {}).items():
                page = pages[key]
                page['n'] += stats.get('n', 0)
                page['janky'] += stats.get('janky', 0)
                page['dropped'] += stats.get('dropped', 0)
                page['worstUiMs'] = max(page['worstUiMs'], float(stats.get('worstUiMs', 0)))
                page['worstRasterMs'] = max(page['worstRasterMs'],
                                            float(stats.get('worstRasterMs', 0)))
        elif name == 'perf.transition':
            janky.append({'at': entry.get('at'), **details})
            page = pages[f"{details.get('kind')}:{details.get('to')}"]
            page['logged'] += 1
            for hint in details.get('hints') or []:
                page['hints'][hint] += 1
    return pages, janky


def severity(entry):
    return (entry.get('dropped', 0) * 2 + entry.get('overBudgetUi', 0) +
            entry.get('overBudgetRaster', 0) +
            max(float(entry.get('firstUiMs', 0)), float(entry.get('worstRasterMs', 0))) / 50)


def render(pages, janky, top=10):
    lines = ['页面变化                         次数  卡顿  掉帧  最差UI  最差光栅  线索',
             '（次数与最差值来自定期汇总，卡顿明细来自逐次记录）']
    for key, page in sorted(pages.items(),
                            key=lambda kv: (-max(kv[1]['janky'], kv[1]['logged']), kv[0])):
        hints = ', '.join(f'{h}×{n}' for h, n in sorted(page['hints'].items()))
        count = f"{page['n']:4}" if page['n'] else '   —'
        stutters = max(page['janky'], page['logged'])
        lines.append(f"{key[:32]:32} {count}  {stutters:4}  {page['dropped']:4}  "
                     f"{page['worstUiMs']:6.1f}  {page['worstRasterMs']:8.1f}  {hints}")
    if janky:
        lines += ['', f'最卡的 {min(top, len(janky))} 次：']
        for entry in sorted(janky, key=severity, reverse=True)[:top]:
            lines.append(
                f"- {entry.get('at', '')[:19]} {entry.get('kind')} {entry.get('from')} → "
                f"{entry.get('to')}{'（本进程首次）' if entry.get('firstOpen') else ''}："
                f"掉帧 {entry.get('dropped')}，UI 超预算 {entry.get('overBudgetUi')} 帧"
                f"（首帧 {entry.get('firstUiMs')} / 最差 {entry.get('worstUiMs')} ms），"
                f"光栅超预算 {entry.get('overBudgetRaster')} 帧（最差 {entry.get('worstRasterMs')} ms），"
                + (f"滑入后最差 UI {entry['afterSlideWorstUiMs']} ms，"
                   if entry.get('afterSlideWorstUiMs') else '')
                + f"预算 {entry.get('budgetMs')} ms")
            for hint in entry.get('hints') or []:
                lines.append(f'    · {hint}: {HINTS.get(hint, "")}')
            for notify in entry.get('notifies') or []:
                lines.append(f"    · 通知 {notify.get('source')} 第 {notify.get('frame')} 帧后，"
                             f"来自 {notify.get('caller') or '未知'}")
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('source', nargs='?', help='report id, report file or operations.jsonl')
    parser.add_argument('--root', type=Path, default=DEFAULT_ROOT)
    parser.add_argument('--top', type=int, default=10)
    parser.add_argument('--all-sessions', action='store_true',
                        help='every app session in the log, not just the newest')
    args = parser.parse_args()
    path, operations = load_operations(args.source, args.root)
    session = None if args.all_sessions else latest_session(operations)
    pages, janky = summarize(operations, session)
    print(f"{path}\n{'全部会话' if session is None else f'最近一次会话 {session}'}\n")
    print(render(pages, janky, args.top) if pages else '没有页面变化记录（需要 2026-11-10 之后的版本）。')


if __name__ == '__main__':
    main()
