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
from lan_diagnostics import DiagnosticsReceiver, MAX_REPORT_BYTES
from lan_backups import (BackupStore, MAX_BLOB_BYTES, MAX_MANIFEST_BYTES, MissingFiles, lan_only,
                         valid_device_id, valid_sha256)


def download_page(root: Path, macos_root: Path = None):
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
    macos_link = ''
    if macos_root is not None:
        try:
            macos = json.loads((macos_root / 'latest.json').read_text(encoding='utf-8'))
            url = macos['url']
            name = url.removeprefix('/releases/macos/')
            if url.startswith('/releases/macos/') and name.endswith('.zip') and not any(c in name for c in '/\\\x00'):
                macos_link = ('<p><a download href="' + html.escape(url, quote=True) + '">下载 Mac 版 ' +
                              html.escape(str(macos['versionName'])) + '</a> · 解压后拖入“应用程序”</p>')
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            pass
    return ('<!doctype html><html lang="zh-CN"><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>AI Music 安装包</title><style>body{font:16px system-ui;background:#f5f7fa;color:#18242c;'
            'max-width:850px;margin:32px auto;padding:0 16px}h1{font-size:28px}table{width:100%;border-collapse:collapse;'
            'background:white;border-radius:12px}th,td{text-align:left;padding:16px 12px;border-bottom:1px solid #edf0f3}'
            'small{color:#657480}a{color:#176be2;line-height:2}.tag{font-size:12px;background:#e5f2ea;color:#176237;'
            'padding:3px 5px;border-radius:5px}p{color:#657480}</style><h1>AI Music 安装包</h1>'
            '<p>当前发布版与历史安装包。release 用于正式手机，debug 用于开发手机。</p>' + macos_link +
            '<table><thead><tr><th>版本</th><th>类型 / 架构</th><th>安装包</th></tr></thead><tbody>' +
            ''.join(rows) + '</tbody></table></html>').encode('utf-8')


def create_server(root: Path, host: str = "0.0.0.0", port: int = 8788, *, macos_root: Path = None):
    root = root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    macos_root = (macos_root if macos_root is not None else root.parent / 'macos').resolve()
    diagnostics = DiagnosticsReceiver(root.parent / 'diagnostics')
    backups = BackupStore(root.parent / 'backups')

    class Handler(BaseHTTPRequestHandler):
        def json_response(self, status, document):
            payload = json.dumps(document, ensure_ascii=False).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def read_json_body(self, limit):
            length = self.headers.get('Content-Length', '')
            if not length.isdigit() or not 0 < int(length) <= limit:
                raise OverflowError('Body size')
            self.connection.settimeout(30)
            payload = self.rfile.read(int(length))
            if len(payload) != int(length):
                raise ValueError('Truncated body')
            return payload

        def backup_error(self, error):
            if isinstance(error, PermissionError):
                self.send_error(403)
            elif isinstance(error, OverflowError):
                self.send_error(413)
            elif isinstance(error, FileNotFoundError):
                self.send_error(404)
            elif isinstance(error, MissingFiles):
                self.send_error(409, str(error))
            elif isinstance(error, (ValueError, TypeError, KeyError, UnicodeError, TimeoutError)):
                self.send_error(400, str(error)[:200])
            else:
                self.send_error(503)

        def do_PUT(self):
            path = unquote(urlsplit(self.path).path)
            try:
                lan_only(self.client_address[0])
                if path.startswith('/api/v1/backup/blobs/'):
                    sha256 = path[len('/api/v1/backup/blobs/'):]
                    length = self.headers.get('Content-Length', '')
                    if not valid_sha256(sha256) or not length.isdigit() or int(length) > MAX_BLOB_BYTES:
                        raise ValueError('Invalid blob upload')
                    self.connection.settimeout(60)
                    receipt = backups.put_blob(sha256, self.rfile, int(length), self.client_address[0])
                    self.json_response(201 if receipt['stored'] else 200, receipt)
                    return
                if path.startswith('/api/v1/backup/devices/'):
                    device_id = path[len('/api/v1/backup/devices/'):]
                    payload = self.read_json_body(MAX_MANIFEST_BYTES)
                    self.json_response(200, backups.put_manifest(device_id, payload, self.client_address[0]))
                    return
                self.send_error(404)
            except (OSError, ValueError, TypeError, KeyError, MissingFiles, OverflowError) as error:
                self.backup_error(error)

        def do_POST(self):
            if urlsplit(self.path).path == '/api/v1/backup/blobs/missing':
                try:
                    lan_only(self.client_address[0])
                    document = json.loads(self.read_json_body(4 * 1024 * 1024))
                    self.json_response(200, {'missing': backups.missing(document.get('sha256'))})
                except (OSError, ValueError, TypeError, KeyError, AttributeError, OverflowError) as error:
                    self.backup_error(error)
                return
            if urlsplit(self.path).path != '/api/v1/diagnostics':
                self.send_error(404)
                return
            length = self.headers.get('Content-Length', '')
            if not length.isdigit() or not 0 < int(length) <= MAX_REPORT_BYTES:
                self.send_error(413)
                return
            if self.headers.get_content_type() != 'application/json':
                self.send_error(415)
                return
            self.connection.settimeout(15)
            try:
                payload = self.rfile.read(int(length))
                if len(payload) != int(length):
                    raise ValueError('Truncated report')
                receipt = diagnostics.receive(payload, self.client_address[0])
                self.json_response(201, receipt)
            except FileExistsError:
                self.send_error(409)
            except PermissionError:
                self.send_error(403)
            except (ValueError, TypeError, UnicodeError, TimeoutError):
                self.send_error(400)
            except OSError:
                self.send_error(503)

        def do_GET(self):
            path = unquote(urlsplit(self.path).path)
            if path.startswith('/api/v1/backup/'):
                self.backup_get(path)
                return
            if path == '/api/v1/diagnostics':
                self.json_response(200, {'service': 'ai-music-diagnostics',
                                        'schemaVersion': 1, 'maxReportBytes': MAX_REPORT_BYTES})
                return
            if path in ('/', '/api/v1/releases/android'):
                if path == '/':
                    payload = download_page(root, macos_root)
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
            if path in ("/api/v1/update/android", "/api/v1/update/macos"):
                manifest = (macos_root if path.endswith('/macos') else root) / "latest.json"
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
            if path.startswith('/releases/macos/'):
                name = path[len('/releases/macos/'):]
                if not name or any(c in name for c in '/\\\x00') or not name.endswith('.zip'):
                    self.send_error(404)
                    return
                target = macos_root / name
                if target.is_symlink() or target.resolve().parent != macos_root or not target.is_file():
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header('Content-Type', 'application/zip')
                self.send_header('Content-Length', str(target.stat().st_size))
                self.end_headers()
                try:
                    with target.open('rb') as source:
                        for chunk in iter(lambda: source.read(1024 * 1024), b''):
                            self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    pass
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

        def backup_get(self, path):
            try:
                lan_only(self.client_address[0])
                if path == '/api/v1/backup/devices':
                    self.json_response(200, {'schemaVersion': 1, 'devices': backups.list_devices()})
                    return
                if path.startswith('/api/v1/backup/devices/'):
                    device_id = path[len('/api/v1/backup/devices/'):]
                    if not valid_device_id(device_id):
                        raise ValueError('Invalid device ID')
                    self.json_response(200, backups.manifest(device_id))
                    return
                if path.startswith('/api/v1/backup/blobs/'):
                    target = backups.blob_path(path[len('/api/v1/backup/blobs/'):])
                    if not target.is_file():
                        raise FileNotFoundError('blob')
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/octet-stream')
                    self.send_header('Content-Length', str(target.stat().st_size))
                    self.end_headers()
                    try:
                        with target.open('rb') as source:
                            for chunk in iter(lambda: source.read(1024 * 1024), b''):
                                self.wfile.write(chunk)
                    except (BrokenPipeError, ConnectionResetError):
                        pass
                    return
                self.send_error(404)
            except (OSError, ValueError, TypeError, KeyError) as error:
                self.backup_error(error)

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
