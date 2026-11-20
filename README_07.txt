ParkSmart Ticket Hub Souvenirs dynamic sync fix

Current project: FYP_New
Fixes actual UI source: lib/visitor/pages/ticket_catalog_screens.dart
Uses already-installed widget: lib/visitor/widgets/live_souvenirs_section.dart

Steps:
1) Unzip this archive. Place 07_FIX_TICKET_HUB_SOUVENIRS.py into FYP_New root.
2) From FYP_New PowerShell run: python .\07_FIX_TICKET_HUB_SOUVENIRS.py
3) Run: flutter analyze --no-fatal-infos lib/visitor/pages/ticket_catalog_screens.dart lib/visitor/widgets/live_souvenirs_section.dart
4) Restart web app: .\tool\run-app.cmd -Restart
5) Visit Visitor > Tickets > Ticket Hub. Shop Souvenirs will use Admin's Firestore products.

Only the target Dart file is changed. Before overwriting, it is backed up to a sibling folder named BeforeTicketHubSouvenirs_DATE.
No GitHub commits, pushes, Firebase deployment, or Firestore writes.
If the browser shows no products, verify Firestore read permission and active shop items.
