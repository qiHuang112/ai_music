"""Private LAN diagnostic report storage; no read/download endpoint."""
import hashlib
import ipaddress
import json
import os
import re
import tempfile
import threading
from datetime import datetime, timezone
from pathlib import Path

MAX_REPORT_BYTES = 32 * 1024 * 1024


class DiagnosticsReceiver:
    def __init__(self, root: Path):
        self.root = root
        self.lock = threading.Lock()

    def receive(self, payload: bytes, client_address: str):
        if not ipaddress.ip_address(client_address).is_private:
            raise PermissionError('LAN clients only')
        if len(payload) > MAX_REPORT_BYTES:
            raise ValueError('Report too large')
        document = json.loads(payload)
        if not isinstance(document, dict) or document.get('schemaVersion') != 1:
            raise ValueError('Invalid schema')
        report_id = document.get('reportId')
        if not isinstance(report_id, str) or not re.fullmatch(r'[a-f0-9]{32}', report_id):
            raise ValueError('Invalid report ID')
        if (not isinstance(document.get('operations'), list) or
                not isinstance(document.get('listeningStats'), dict) or
                not isinstance(document.get('app'), dict) or
                document['app'].get('packageName') not in {'com.qi.ai.music', 'com.qi.ai.music.preview'}):
            raise ValueError('Invalid report contents')
        digest = hashlib.sha256(payload).hexdigest()
        now = datetime.now(timezone.utc).isoformat()
        with self.lock:
            self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
            target = self.root / f'{report_id}.json'
            if target.exists():
                old = json.loads(target.read_text())
                if old['sha256'] != digest:
                    raise FileExistsError('Report ID already used')
                return {'saved': True, 'reportId': report_id, 'sha256': digest,
                        'receivedAt': old['receivedAt']}
            document = {'receivedAt': now, 'clientAddress': client_address,
                        'sha256': digest, 'payload': document}
            fd, temporary = tempfile.mkstemp(prefix='.upload-', dir=self.root)
            try:
                with os.fdopen(fd, 'w', encoding='utf-8') as output:
                    json.dump(document, output, ensure_ascii=False)
                    output.write('\n')
                    output.flush()
                    os.fsync(output.fileno())
                os.replace(temporary, target)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
        return {'saved': True, 'reportId': report_id, 'sha256': digest, 'receivedAt': now}
