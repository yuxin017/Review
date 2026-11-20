from __future__ import annotations
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path.cwd().resolve()
BRANCH = 'fix/staff-coverage-timetable'
BACKUP_NAME = 'Review_CameraCrowdBackup_20261119_175113'
FILES = [
    'lib/admin/cameras/attraction_camera_store.dart',
    'lib/admin/cameras/camera_station_page.dart',
    'lib/admin/cameras/live_cameras_panel.dart',
    'lib/admin/operations/crowd_monitoring_page.dart',
    'lib/park/park_map_canvas.dart',
    'lib/park/venue_map.dart',
    'firestore.rules',
]
ADDED = 'lib/admin/cameras/camera_crowd_overview.dart'

def main():
    if not (ROOT/'lib/admin/staff/staff_schedule_arrangement.dart').exists():
        raise RuntimeError('Please run from FYP_New root, the folder containing pubspec.yaml.')
    branch = subprocess.run(['git', 'branch', '--show-current'], cwd=ROOT,
        capture_output=True, text=True, check=True).stdout.strip()
    if branch != BRANCH:
        raise RuntimeError(f'Wrong branch: {branch}. Expected {BRANCH}.')
    source = ROOT.parent/BACKUP_NAME
    missing = [str(source/name) for name in FILES if not (source/name).is_file()]
    if missing:
        raise RuntimeError('Original camera backup missing. No files changed:\n'+'\n'.join(missing))
    for name in FILES:
        if not (ROOT/name).exists():
            raise RuntimeError('Project file missing: '+name)
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    safety = ROOT.parent/f'BeforeRollbackCameraSync_{stamp}'
    if safety.exists():
        raise RuntimeError('Safety backup folder already exists, please run again.')
    safety.mkdir()
    try:
        for name in FILES+[ADDED]:
            file = ROOT/name
            if file.is_file():
                target = safety/name
                target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(file,target)
        for name in FILES:
            shutil.copy2(source/name,ROOT/name)
        if (ROOT/ADDED).exists():
            (ROOT/ADDED).unlink()
    except BaseException:
        for name in FILES+[ADDED]:
            saved=safety/name
            if saved.is_file():
                target=ROOT/name
                target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(saved,target)
        raise
    print('SUCCESS: Restored seven pre-camera-sync files, deleted added widget.')
    print('Safety snapshot of CURRENT edits saved at:',safety)
    print('GitHub and Firebase were NOT modified. Do NOT redeploy Firestore rules yet.')
    print('If camera rules had ALREADY been deployed, review deployed rules separately.')

if __name__=='__main__':
    main()
