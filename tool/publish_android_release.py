#!/usr/bin/env python3
"""Verify a release APK, then publish immutable bytes and an atomic manifest."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from android_release_archive import retain_manifest


def publish(apk: Path, root: Path, aapt: str, apksigner: str, notes: str = "", *, release_cert: str):
    if not re.fullmatch(r"[a-fA-F0-9]{64}", release_cert):
        raise ValueError("Expected the trusted release certificate SHA-256")
    signed = subprocess.check_output(
        [apksigner, "verify", "--print-certs", str(apk)], text=True
    )
    certificates = set(re.findall(
        r"Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})", signed
    ))
    if {certificate.lower() for certificate in certificates} != {release_cert.lower()}:
        raise ValueError("APK signer does not match the trusted release certificate")
    badging = subprocess.check_output([aapt, "dump", "badging", str(apk)], text=True)
    metadata = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
    if not metadata or metadata[1] != "com.qi.ai.music" or "application-debuggable" in badging:
        raise ValueError("Expected an AI Music release APK")
    with zipfile.ZipFile(apk) as archive:
        abis = {name.split("/")[1] for name in archive.namelist() if name.startswith("lib/") and name.endswith(".so")}
    if abis != {"arm64-v8a"}:
        raise ValueError("Expected an arm64 release APK")
    digest = hashlib.sha256()
    with apk.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    hash_hex = digest.hexdigest()
    root.mkdir(parents=True, exist_ok=True)
    manifest_path = root / "latest.json"
    code = int(metadata[2])
    if manifest_path.exists():
        previous = json.loads(manifest_path.read_text(encoding="utf-8"))
        retain_manifest(root, previous)
        if code < previous["versionCode"] or (code == previous["versionCode"] and hash_hex != previous["sha256"]):
            raise ValueError("Release versionCode must increase when APK bytes change")
        if code == previous["versionCode"]:
            return previous
    name = f"ai-music-{code}-{hash_hex[:12]}.apk"
    # Version metadata never points at a partially copied file.
    fd, temporary = tempfile.mkstemp(prefix=".apk-", dir=root)
    os.close(fd)
    try:
        shutil.copyfile(apk, temporary)
        os.replace(temporary, root / name)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    manifest = {
        "packageName": metadata[1], "versionName": metadata[3], "versionCode": code,
        "channel": "release", "abi": "arm64-v8a",
        "publishedAt": datetime.now(timezone.utc).isoformat(), "url": f"/releases/{name}",
        "sizeBytes": apk.stat().st_size, "sha256": hash_hex, "notes": notes,
    }
    retain_manifest(root, manifest)
    fd, temporary = tempfile.mkstemp(prefix=".manifest-", dir=root)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as destination:
            json.dump(manifest, destination, ensure_ascii=False)
            destination.flush()
            os.fsync(destination.fileno())
        os.replace(temporary, manifest_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--aapt", required=True)
    parser.add_argument("--apksigner", required=True)
    parser.add_argument("--release-cert", required=True, help="Trusted release certificate SHA-256")
    parser.add_argument("--notes", default="")
    args = parser.parse_args()
    result = publish(args.apk, args.root, args.aapt, args.apksigner, args.notes, release_cert=args.release_cert)
    print(f"Published {result['versionName']} ({result['versionCode']}) · {result['sha256']}")


if __name__ == "__main__":
    main()
