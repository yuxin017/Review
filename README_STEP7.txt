THEME PARK SMART MANAGEMENT SYSTEM — STEP 7
STAFF EMAIL LOGIN, VERIFICATION & READ-ONLY STAFF PORTAL

PRECONDITIONS
- Step 6 installed.
- Step 4 Firestore rules pass local Emulator tests (6/6).
- Step 6 Backend tests pass (5/5).
- Step 2–3 Staff Flutter tests pass (13/13).

WHAT THIS ADDS
- /staff route for employees, separate from /admin and visitor login.
- Separate named Firebase app (ThemeParkStaff) so staff signing in does NOT
  replace the browser's ThemeParkAdmin Super Admin session.
- Login with REAL email + password.
- Staff 'Forgot password' via Firebase Auth email.
- First-login verification email request and 'Refresh Access'.
- Staff identity claim check (`staff:true`), email verification check,
  matching profile email/UID, and current staffProfiles.status check.
- Inactive/pending activation, suspended and unknown accounts get denied.
- Active, verified staff can view only their own Staff ID, eligible roles,
  and training records; NO operations or AdminShell privileges.
- A pure StaffPortalPolicy test suite.

SECURITY
- This route is READ ONLY for staff. It intentionally does NOT unlock
  ticket admission, Attraction Operator actions, Photo uploads, etc.
- UI access checks are not a security boundary. Before enabling ANY staff
  operation, enforce identity, effective shift, exact role, attraction
  qualifications and status INSIDE Cloud Functions/Firestore Rules.
- Never give restricted staff the `admin:true` claim.
- Staff profiles and qualifications must remain self-read-only via the
  deployed Step 4 Firestore Rules; admins alone may edit them.
- A password setup/reset link does not verify the email address.
- Supervisor must explicitly activate staffProfiles.status after confirmation.
- Staff email in Firestore must match Firebase Auth's email. Existing Edit Staff
  UI shows email as READ ONLY; changing auth email requires a separate secure
  coordinated workflow.

INSTALL (DO NOT DEPLOY AUTOMATICALLY)
1. Extract this ZIP from Downloads into your FYP_New project folder.
2. Run .\APPLY_STAFF_PORTAL_STEP7.ps1
   The script ONLY changes the import/route in lib/main.dart and saves a backup.
   It does not touch any existing CrowdSense, Admin UI, Firebase Rules or functions.
3. Run: flutter analyze lib/admin/staff lib/main.dart
4. Run: flutter test test/admin/staff_portal_policy_test.dart
5. Run: flutter test test/admin/staff_access_test.dart test/admin/staff_records_test.dart
6. Start your usual Flutter Web app; navigate to http://127.0.0.1:5173/#/staff
   (assuming the dev server is serving port 5173).

ACTUAL EMAIL/LOGIN DEMO REQUIREMENTS
- Deploy Step 6 createStaffAccount Cloud Function and current Firestore Rules
  ONLY after checking the correct live project and reviewing security; nothing
  in Step 7 deploys them.
- Enable Firebase Authentication Email/Password and correct email templates.
- Use a REAL mailbox owned by the employee. Firebase creates a login account,
  NOT the inbox itself.
- Create employee from Super Admin's Staff Management, verify invite arrival.
- Follow password setup link to choose password; go to /staff and sign in.
- Click Send Verification Email; open link and Refresh Access.
- Super Admin edits staff record to status Active, and staff sees the
  read-only portal with their Staff ID, roles and training records.
- Even after activation, shift-dependent operational actions remain locked
  pending future backend work.

LIMITATION
This package has NOT been compiled on your Windows Flutter environment.
The automated pure Dart test and Flutter analyze there are authoritative.
Do not deploy live solely based on local unit tests.
