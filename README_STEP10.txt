THEME PARK SMART MANAGEMENT SYSTEM — STEP 10
STAFF UI CONSISTENCY, VERIFICATION ENFORCEMENT & TRAINING CATALOGUE
Firebase Spark (FREE); no Cloud Functions; no additional dependencies.

THIS PACKAGE IMPLEMENTS
1. Staff Management uses the same AdminHeading and AdminCard design system
   as Visitor Accounts. The staff directory is a full-width row-by-row table,
   not a split left/right layout. Employee details appear below the table.
2. Warm off-white dialogs with shadow and one shared header, close control,
   body layout and footer actions across Create/Edit/Status/Training/Catalogue.
3. Full name and email use Form validation with errors directly below the
   fields. Employee email duplicates are checked after typing (debounced) and
   on blur against the REAL Staff Directory in Firestore. Submission checks
   again. A duplicate in OTHER Firebase Auth categories (e.g. Visitor) cannot
   be enumerated safely from Spark client; the final Firebase Auth create call
   reports that as an error BELOW the email field. Do not disable email
   enumeration protection to fake immediate universal existence checks.
4. Email Verification has TWO SECURITY CHECKS:
   - Employee verifies email from their real inbox, then signs in at /staff
     and presses Refresh Access. The staff portal writes a proof under their
     own Firebase UID with an ID token containing email_verified=true.
   - Firestore rules reject proof from unverified users AND reject a NEW
     transition to Active until that proof exists and matches the staff email.
   - Newly created staffProfiles MUST start Inactive.
5. Training courses are NOT typed ad hoc for each employee. Super Admin
   adds standardized courses ONCE in 'Training Catalogue' (Firestore
   staffTrainingCourses). Record Training then uses a course dropdown,
   choosing a ride dynamically from the actual 'attractions' collection
   for Attraction Operator. No fake sample rides or training records.
6. Existing accounts and training history remain. No migration or deletion.

IMPORTANT LIMITATIONS
- The role/shift operational access backend is STILL not complete. ACTIVE
  currently enables only a read-only Staff Portal, not admission/photo/ride.
- `admin:true` remains the legacy administrator condition; revisit true
  Super Admin scoping before having many different types of administrator.
- Firebase Spark cannot securely query all Auth user emails from a browser.
  Only staffProfiles can be prechecked before Create; the final Firebase Auth
  signup detects another Auth account if the provider returns such an error.
- An employee activated with the OLD UI stays Active until a supervisor
  changes it. Security rules are NOT retroactive database migrations.
  After deploying Step 10, mark such accounts Inactive first. Have staff
  verify email at /staff and press Refresh Access; then Activate again.
- If email verification cannot be recorded, do NOT manually insert a proof
  from Firebase Console or bypass Firestore rules to enable access.

INSTALL — PROJECT ROOT FYP_New (Windows PowerShell)
1. Download Staff_Workforce_Step10_UX_and_Verification.zip to Downloads.
2. Expand-Archive -Path "$HOME\Downloads\Staff_Workforce_Step10_UX_and_Verification.zip" -DestinationPath "."
3. .\APPLY_STAFF_STEP10.ps1
   The script verifies known Step 8/9 source hashes, preflights rules edits,
   backs up the changed files and stops without overwriting unknown changes.
   It does NOT deploy Firestore rules or modify any Firebase data.
4. flutter analyze lib/admin/staff
5. flutter test test/admin/staff_email_check_test.dart test/admin/staff_form_validation_test.dart test/admin/staff_spark_policy_test.dart test/admin/staff_access_test.dart test/admin/staff_records_test.dart test/admin/staff_portal_policy_test.dart
6. firebase emulators:exec --config firebase.staff-emulators.json --only auth,firestore --project demo-themepark-fyp "node --test test/emulator/staff_rules.test.cjs test/emulator/staff_spark_rules.test.cjs test/emulator/staff_step10_rules.test.cjs"
7. git --no-pager diff --check -- firestore.rules
8. git --no-pager diff --stat -- firestore.rules
   CHECK the expected staff-only additions, and compare with current LIVE
   Firebase Rules in the Console before deploying (deploy replaces all rules).
9. ONLY WHEN ALL TESTS PASS AND THE LIVE RULES ARE RECONCILED:
   firebase deploy --only firestore:rules --project themeparksmartmanagement
10. .\tool\run-app.cmd -Restart
11. Chrome Ctrl+Shift+R; open http://127.0.0.1:5173/#/admin
12. Existing ACTIVE unverified account: mark INACTIVE; staff sets password,
    logs in at http://127.0.0.1:5173/#/staff, sends verification link,
    confirms email, presses Refresh Access, then Admin sees Verified and
    may Activate.
13. In Staff Management choose Training Catalogue > Add Course, choose
    role/title ONCE. Afterwards Record Training on a selected employee.

THIS PACKAGE HAS BEEN STATICALLY INSPECTED AND ZIP VALIDATED. Flutter SDK
AND FIREBASE EMULATOR WERE NOT AVAILABLE IN THIS SERVER ENVIRONMENT;
YOUR local flutter analyze/test and emulator result are the acceptance gates.
Do not deploy Firestore rules before all local tests pass.
