#!/usr/bin/env python3
"""Serve atomically published Android releases on a home LAN."""
import argparse
import html
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit
from android_release_archive import retained_versions


def download_page(root: Path):
    latest_hash = None
    try:
        latest_hash = json.loads((root / 'latest.json').read_text(encoding='utf-8'))['sha256']
    except (OSError, ValueError, KeyError):
        pass
    rows = []
    versions = retained_versions(root)
    for row in sorted(versions, key=lambda item: item['sha256'] != latest_hash):
        url = row.get('url', '')
        # Only local APK paths from this server are rendered as download links.
        if not url.startswith('/releases/') or '/' in url[len('/releases/'):] or not url.endswith('.apk'):
            continue
        label = ' <span class="tag">最新版</span>' if row['sha256'] == latest_hash else ''
        rows.append('<tr><td><strong>' + html.escape(str(row.get('versionName', ''))) + '</strong>' + label +
                    '<br><small>' + str(row.get('versionCode', '')) + '</small></td><td>' +
                    html.escape(str(row.get('channel', ''))) + '<br><small>' +
                    html.escape(str(row.get('abi', ''))) + '</small></td><td>' +
                    f"{row.get('sizeBytes', 0) / 1024 / 1024:.1f} MB" +
                    '<br><a download href="' + html.escape(url, quote=True) + '">下载 APK</a></td></tr>')
    return ('<!doctype html><html lang="zh-CN"><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>AI Music 安装包</title><style>body{font:16px system-ui;background:#f5f7fa;color:#18242c;'
            'max-width:850px;margin:32px auto;padding:0 16px}h1{font-size:28px}table{width:100%;border-collapse:collapse;'
            'background:white;border-radius:12px}th,td{text-align:left;padding:16px 12px;border-bottom:1px solid #edf0f3}'
            'small{color:#657480}a{color:#176be2;line-height:2}.tag{font-size:12px;background:#e5f2ea;color:#176237;'
            'padding:3px 5px;border-radius:5px}p{color:#657480}</style><h1>AI Music 安装包</h1>'
            '<p>当前发布版与历史安装包。release 用于正式手机，debug 用于开发手机。</p>'
            '<table><thead><tr><th>版本</th><th>类型 / 架构</th><th>安装包</th></tr></thead><tbody>' +
            ''.join(rows) + '</tbody></table></html>').encode('utf-8')


def create_server(root: Path, host: str = "0.0.0.0", port: int = 8788):
    root = root.resolve()
    root.mkdir(parents=True, exist_ok=True)

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = unquote(urlsplit(self.path).path)
            if path in ('/', '/api/v1/releases/android'):
                if path == '/':
                    payload = download_page(root)
                    content_type = 'text/html; charset=utf-8'
                else:
                    payload = json.dumps(retained_versions(root), ensure_ascii=False).encode('utf-8')
                    content_type = 'application/json; charset=utf-8'
                self.send_response(200)
                self.send_header('Content-Type', content_type)
                self.send_header('Cache-Control', 'no-store')
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            if path == "/api/v1/update/android":
                manifest = root / "latest.json"
                if not manifest.is_file():
                    self.send_response(204)
                    self.send_header("Cache-Control", "no-store")
                    self.end_headers()
                    return
                try:
                    payload = manifest.read_bytes()
                    json.loads(payload)
                except (OSError, ValueError):
                    self.send_error(503, "Release metadata unavailable")
                    return
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            if path.startswith("/releases/"):
                name = path[len("/releases/"):]
                if not name or "/" in name or "\\" in name or "\x00" in name or not name.endswith(".apk"):
                    self.send_error(404)
                    return
                target = root / name
                if target.is_symlink() or target.resolve().parent != root or not target.is_file():
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Type", "application/vnd.android.package-archive")
                self.send_header("Content-Length", str(target.stat().st_size))
                self.end_headers()
                try:
                    with target.open("rb") as source:
                        for chunk in iter(lambda: source.read(1024 * 1024), b""):
                            self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    pass  # User canceled the download.
                return
            self.send_error(404)

    return ThreadingHTTPServer((host, port), Handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", default=8788, type=int)
    parser.add_argument('--mirror-github', action='store_true')
    parser.add_argument('--aapt')
    parser.add_argument('--apksigner')
    args = parser.parse_args()
    if args.mirror_github and (not args.aapt or not args.apksigner):
        parser.error('--mirror-github requires --aapt and --apksigner')
    server = create_server(args.root, args.host, args.port)
    stopped = threading.Event()
    if args.mirror_github:
        from mirror_github_android_release import mirror

        def mirror_releases():
            while not stopped.is_set():
                try:
                    release = mirror(args.root, args.aapt, args.apksigner)
                    print(f"LAN mirror ready: {release['versionCode']}", flush=True)
                except Exception as error:
                    print(f'LAN mirror retry: {error}', flush=True)
                stopped.wait(60)

        threading.Thread(target=mirror_releases, daemon=True).start()
    print(f"Android release updates: http://{args.host}:{server.server_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stopped.set()
        server.server_close()


if __name__ == "__main__":
    main()
