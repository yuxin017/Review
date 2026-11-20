#!/usr/bin/env python3
"""Resume ParkSmart commerce installation without losing existing local source files.

Applies ONLY to the fix/staff-coverage-timetable project. Does not modify GitHub,
Firebase, or Stripe. Backups are placed outside the Git worktree.
"""
from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path.cwd().resolve()
HERE = Path(__file__).resolve().parent
BRANCH = 'fix/staff-coverage-timetable'
FILES = {
    'functions/src/stripe_commerce_gateway.js': '0e99dd7edb7164f3a6cd829b3e07530e93661cf9d774e9310fc5d60c9bb53dc1',
    'lib/commerce/stripe_commerce_client.dart': '3723716d2a4cf9cd4bc365c492834062398c303c5ddef41a50ddc6a6ccd994e8',
    'lib/visitor/pages/souvenir_shop_page.dart': 'e43877c2f4852e0f2cc924357da55e998757deb67d09137afed721dcb8666568',
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def normalized(data: bytes) -> str:
    return data.decode('utf-8-sig').replace('\r\n', '\n').rstrip('\n')


def main() -> int:
    if not (ROOT / 'lib/admin/staff/staff_schedule_arrangement.dart').is_file():
        raise RuntimeError('Run from the FYP_New project root (contains pubspec.yaml).')
    branch = subprocess.run(['git', 'branch', '--show-current'], cwd=ROOT,
                            text=True, capture_output=True, check=True).stdout.strip()
    if branch != BRANCH:
        raise RuntimeError(f'Wrong branch: {branch}. Expected {BRANCH}.')
    installer = ROOT / '03_APPLY_COMMERCE.py'
    if not installer.is_file() or 'expected_additions' not in installer.read_text(encoding='utf-8-sig'):
        raise RuntimeError('The corrected 03_APPLY_COMMERCE.py is required. Unzip ParkSmart_Commerce_Installer_Fix.zip first.')

    payloads: dict[str, bytes] = {}
    changes: list[tuple[str, bytes | None, bytes, str]] = []
    for name, expected_sha in FILES.items():
        source = HERE / 'commerce_payload' / name
        if not source.is_file():
            raise RuntimeError(f'Missing distributed source: {source}. Extract the whole ZIP into FYP_New.')
        payload = source.read_bytes()
        if sha(payload) != expected_sha:
            raise RuntimeError(f'Payload checksum mismatch: {name}. Do not install a modified package.')
        payloads[name] = payload
        target = ROOT / name
        original = target.read_bytes() if target.exists() else None
        if original is None:
            changes.append((name, None, payload, 'not present; new file'))
        elif sha(original) != expected_sha:
            tracked = subprocess.run(['git', 'ls-files', '--error-unmatch', '--', name],
                                     cwd=ROOT, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL).returncode == 0
            if tracked:
                raise RuntimeError(f'{name} is tracked/staged in Git; refusing to replace it. Reconcile manually.')
            try:
                kind = 'line endings / UTF-8 formatting' if normalized(original) == normalized(payload) else 'local source changes'
            except UnicodeDecodeError:
                kind = 'different encoding / local source changes'
            changes.append((name, original, payload, kind))

    if not changes:
        print('All 3 additions match the installer package. Running original 03 installer...')
    else:
        print('Files to stage safely (any existing version will be backed up):')
        for name, original, _, reason in changes:
            print(f'  {name}: {reason}'+(' (existing file preserved in backup)' if original is not None else ''))

    backup = ROOT.parent / ('BeforeCommerceResume_' + datetime.now().strftime('%Y%m%d_%H%M%S'))
    # Always write backup copies of changed existing files BEFORE altering project.
    for name, original, _, _ in changes:
        if original is not None:
            dest = backup / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(original)
    if any(original is not None for _, original, _, _ in changes):
        print('Backup of previous versions:', backup)

    prepared: list[tuple[str, bytes | None]] = []
    try:
        for name, original, payload, _ in changes:
            target = ROOT / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(payload)
            prepared.append((name, original))
        result = subprocess.run([sys.executable, str(installer)], cwd=ROOT, check=False)
        if result.returncode:
            raise RuntimeError(f'03_APPLY_COMMERCE.py exited with code {result.returncode}; the staged 3 files will be restored.')
        print('SUCCESS: Commerce installer completed. Previous versions (if any) remain in:', backup)
        print('NO GitHub push and NO Firebase/Stripe deployment were performed.')
        return 0
    except Exception:
        for name, original in reversed(prepared):
            target = ROOT / name
            if original is None:
                target.unlink(missing_ok=True)
            else:
                target.write_bytes(original)
        raise


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print('RESUME NOT COMPLETED:', error, file=sys.stderr)
        sys.exit(1)
