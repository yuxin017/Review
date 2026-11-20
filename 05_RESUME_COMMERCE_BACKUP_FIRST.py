#!/usr/bin/env python3
"""Continue the ParkSmart commerce patch with exact-content backups of collisions.

Handles tracked/staged/untracked additions without changing the Git index.
Only the three commerce package addition files are replaced temporarily.
On installer failure they are restored byte-for-byte.
"""
from __future__ import annotations

import difflib
import hashlib
from datetime import datetime
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path.cwd().resolve()
HERE = Path(__file__).resolve().parent
BRANCH = 'fix/staff-coverage-timetable'
FILES = {
    'functions/src/stripe_commerce_gateway.js': '0e99dd7edb7164f3a6cd829b3e07530e93661cf9d774e9310fc5d60c9bb53dc1',
    'lib/commerce/stripe_commerce_client.dart': '3723716d2a4cf9cd4bc365c492834062398c303c5ddef41a50ddc6a6ccd994e8',
    'lib/visitor/pages/souvenir_shop_page.dart': 'e43877c2f4852e0f2cc924357da55e998757deb67d09137afed721dcb8666568',
}

def invoke(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=ROOT, capture_output=True, text=True, check=False)

def locate_payload(name: str) -> Path:
    candidates = [ROOT / 'commerce_payload' / name, HERE / 'commerce_payload' / name]
    for p in candidates:
        if p.is_file():
            return p
    raise RuntimeError('Missing package payload: ' + name + '\nRe-extract ParkSmart_Commerce_Safe_Resume.zip into FYP_New first.')

def run() -> int:
    if not (ROOT / 'pubspec.yaml').is_file() or not (ROOT / 'lib/admin/staff/staff_schedule_arrangement.dart').is_file():
        raise RuntimeError('Run this script from FYP_New project root.')
    branch = invoke(['git', 'branch', '--show-current'])
    if branch.returncode or branch.stdout.strip() != BRANCH:
        raise RuntimeError(f'Expected branch {BRANCH}; got {branch.stdout.strip()!r}.')
    installer = ROOT / '03_APPLY_COMMERCE.py'
    if not installer.is_file() or 'expected_additions' not in installer.read_text(encoding='utf-8-sig'):
        raise RuntimeError('Install corrected 03_APPLY_COMMERCE.py from Commerce Installer Fix first.')
    wanted = {}
    prior = {}
    for name, expected in FILES.items():
        raw = locate_payload(name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise RuntimeError('Package checksum mismatch: ' + name)
        wanted[name] = raw
        f = ROOT / name
        original = f.read_bytes() if f.exists() else None
        prior[name] = original
    conflicts = [name for name in FILES if prior[name] != wanted[name]]
    if not conflicts:
        print('The three packaged additions already match; running 03...')
        result = subprocess.run([sys.executable, str(installer)], cwd=ROOT, check=False)
        return result.returncode

    stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup = ROOT.parent / ('BeforeCommerceSafeOverwrite_' + stamp)
    # Write backup and git diffs outside project before any active file changes.
    for name in conflicts:
        old = prior[name]
        if old is not None:
            out = backup / name
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(old)
            try:
                left = old.decode('utf-8-sig').replace('\r\n', '\n').splitlines(keepends=True)
                right = wanted[name].decode('utf-8-sig').replace('\r\n', '\n').splitlines(keepends=True)
                diff = ''.join(difflib.unified_diff(left, right, fromfile='current/'+name, tofile='package/'+name))
                if diff:
                    (backup / (name + '.patch')).write_text(diff, encoding='utf-8')
            except UnicodeDecodeError:
                pass
        print(f'{name}: ' + ('backup saved before using package file' if old is not None else 'new file'))
    if backup.exists():
        print('Current-file backups and any differences saved at:', backup)
    print('Git staged/index content is NOT touched; only working files are updated.')

    touched = []
    try:
        for name in conflicts:
            f = ROOT / name
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_bytes(wanted[name])
            touched.append(name)
        # The corrected 03 applies a prevalidated set of patches, with own backups.
        result = subprocess.run([sys.executable, str(installer)], cwd=ROOT, check=False)
        if result.returncode:
            raise RuntimeError(f'03_APPLY_COMMERCE.py exited with code {result.returncode}; original addition files will be restored.')
        print('\nSUCCESS: Commerce patch installed.')
        print('Review any local customizations in:', backup)
        print('No GitHub, Firebase, Stripe or Git staging changes were made by this helper.')
        return 0
    except Exception:
        for name in reversed(touched):
            f = ROOT / name
            old = prior[name]
            if old is None:
                f.unlink(missing_ok=True)
            else:
                f.write_bytes(old)
        raise

if __name__ == '__main__':
    try:
        raise SystemExit(run())
    except Exception as e:
        print('COMMERCE RESUME NOT COMPLETED:', str(e), file=sys.stderr)
        raise SystemExit(1)
