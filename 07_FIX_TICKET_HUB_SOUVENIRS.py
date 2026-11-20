"""Replace the actual Ticket Hub souvenir hardcodes with the installed Firestore widget.

Run once from the ParkSmart FYP_New root. No Git/Firebase operations.
Backups are written alongside, never inside, the project directory.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path
import re
import shutil
import sys

ROOT = Path.cwd()
TARGET = Path('lib/visitor/pages/ticket_catalog_screens.dart')
WIDGET = Path('lib/visitor/widgets/live_souvenirs_section.dart')
IMPORT = "import '../widgets/live_souvenirs_section.dart';"


def stop(message: str) -> None:
    sys.exit('STOP: ' + message)


def main() -> None:
    if not (ROOT / 'pubspec.yaml').is_file():
        stop('Open PowerShell inside FYP_New, not the Downloads folder.')
    page, widget = ROOT / TARGET, ROOT / WIDGET
    if not page.is_file():
        stop('Missing ' + str(TARGET))
    if not widget.is_file() or 'class LiveSouvenirsSection ' not in widget.read_text(encoding='utf-8-sig'):
        stop('LiveSouvenirsSection is missing. Keep the previous installed widget before applying this fix.')

    text = page.read_text(encoding='utf-8-sig')
    start_token = "        _section('Shop Souvenirs',"
    if "        const LiveSouvenirsSection()," in text and start_token not in text:
        print('ALREADY APPLIED: Ticket Hub uses the live Firestore Souvenir section.')
        return
    if text.count(start_token) != 1:
        stop('Expected static Shop Souvenirs anchor exactly once; local page differs. No changes made.')
    if text.count("import 'tickets_page.dart';") != 1:
        stop('Ticket Hub imports differ from expected layout; no changes made.')
    first = text.index(start_token)
    after = text.find('        const SizedBox(height: 12),', first)
    if after < 0:
        stop('Could not locate the card-list boundary; no changes made.')
    old = text[first:after]
    expected = ('Mickey Ears Headband', 'Castle Snow Globe', 'Duffy Plush Toy',
                'scrollDirection: Axis.horizontal', '_souvenir(context,')
    if not all(item in old for item in expected) or len(old) > 1800:
        stop('The hardcoded cards have been customized. No changes made; preserve your work.')

    patched = text[:first] + '        const LiveSouvenirsSection(),\n' + text[after:]
    if IMPORT not in patched:
        patched = patched.replace("import 'tickets_page.dart';", "import 'tickets_page.dart';\n" + IMPORT, 1)

    # Only delete the two obsolete helpers if their exact class region is as expected.
    # In an extensively customized file we keep them rather than deleting user code.
    helper_start = patched.find('  Widget _souvenir(\n')
    class_boundary = patched.find('\n}\n\nclass PassCatalog extends', helper_start) if helper_start >= 0 else -1
    if helper_start >= 0 and class_boundary > helper_start:
        helpers = patched[helper_start:class_boundary]
        if (helpers.count('  Widget _souvenir(') == 1
                and helpers.count('  void _souvenirInfo(') == 1
                and re.findall(r'(?m)^  (?:Widget|void|Future<[^>]+>|int|String|bool) _\w+\(', helpers)
                == ['  Widget _souvenir(', '  void _souvenirInfo(']):
            patched = patched[:helper_start] + patched[class_boundary:]
            print('Obsolete hardcoded souvenir helpers removed.')
        else:
            print('NOTICE: Customized souvenir helpers kept untouched (now unused).')

    backup = ROOT.parent / ('BeforeTicketHubSouvenirs_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    (backup / TARGET).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(page, backup / TARGET)
    page.write_text(patched, encoding='utf-8')
    print('SUCCESS: Ticket Hub hardcoded souvenirs replaced with LiveSouvenirsSection.')
    print('UPDATED:', page)
    print('BACKUP:', backup)
    print('Admin changes sync from Firestore parkMenuItems when active == true.')
    print('No GitHub or Firebase changes were performed.')


if __name__ == '__main__':
    main()
