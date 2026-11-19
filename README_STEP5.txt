Staff Workforce Step 5 — Staff Management UI
============================================

PREREQUISITE: Step 2 and Step 3 files already installed. Step 4 emulator tests
should pass. Do NOT deploy untested Firebase rules.

WHAT THIS ZIP DOES
- Adds one new Flutter staff management UI under lib/admin/staff/
- Includes a guarded PowerShell patcher which backs up and makes minimal
  changes to admin_repository.dart and admin_shell.dart.
- It does not modify existing staff access or records models.
- It does not modify firestore.rules, firebase.json or CrowdSense.
- It does not set Firebase Authentication custom claims or create an Auth login.

INSTALL
1) Extract ZIP to FYP_New (the root with pubspec.yaml).
2) Run: .\APPLY_STAFF_MANAGEMENT_STEP5.ps1
3) Run: flutter analyze lib/admin/staff/staff_management_page.dart lib/admin/admin_repository.dart lib/admin/admin_shell.dart
4) Run: flutter test test/admin/staff_access_test.dart test/admin/staff_records_test.dart
5) Restart your Flutter web server; open /#/admin -> Staff Management.

SECURITY / OPERATION
- Only users already authorized as admin:true can enter the existing portal.
- Staff profile records do NOT create authentication accounts. To link an
  existing account, use its Firebase Auth UID from your project's Auth users.
- The `admin:true` claim is still the legacy full-access root admin. Do NOT
  grant it to Photographer or Attraction Operator.
- This UI will show permission-denied until Step 4 rules are verified and
  deployed safely. Do not weaken rules to force access.
- This step manages approved role eligibility/training records only.
  Shift-specific authorization is not yet enforced.
- Suspending a staff record does NOT disable their Firebase Auth login.
- Credentials, passwords and Firebase claims must never be entered in
  Firestore profile fields.

KNOWN LIMITATIONS
- This is a source-level integration package, not a verified full-app build.
- The current version links existing Firebase Auth UIDs only. A secure
  privileged backend for Auth onboarding/invitations is a later step.
- No changes to Payment or existing Ticket/Photo staff permission enforcement.

If the patcher rejects a marker, send its exact output instead of manually
editing unrelated sections.
