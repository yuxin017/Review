Staff Step 10 SAFE MERGE — for user-uploaded staff_management_page.dart

We compared your actual uploaded file to the Step 9 reference.
The ONLY difference is additional braces around `if (mounted)` inside
_resendSetupEmail (two added lines).  No custom behavioral logic is lost.

From FYP_New project root:
1. Expand-Archive -Path "$HOME\Downloads\Staff_Step10_SAFE_MERGED_FOR_YOUR_FILE.zip" -DestinationPath "."
2. .\APPLY_STAFF_STEP10_MERGED.ps1
3. flutter analyze lib/admin/staff
4. flutter test test/admin/staff_email_check_test.dart test/admin/staff_form_validation_test.dart test/admin/staff_spark_policy_test.dart test/admin/staff_access_test.dart test/admin/staff_records_test.dart test/admin/staff_portal_policy_test.dart
5. firebase emulators:exec --config firebase.staff-emulators.json --only auth,firestore --project demo-themepark-fyp "node --test test/emulator/staff_rules.test.cjs test/emulator/staff_spark_rules.test.cjs test/emulator/staff_step10_rules.test.cjs"
6. git --no-pager diff --check -- firestore.rules

The installer preflights exact file hashes of the local Staff Management,
Staff Portal, and Staff Records Repository; refuses to overwrite an unknown
version; checks staff-only Firestore rules patch locations; creates time-
stamped backups; and never deploys or changes live Firebase data.
If it stops, upload the file named in the error instead of forcing changes.

IMPORTANT: new Staff Profiles remain INACTIVE. For existing staff previously
made ACTIVE before email verification, change to INACTIVE until the employee
verifies their email and clicks Refresh Access at /staff. Test the new
Firestore Rules locally and reconcile with LIVE rules before deploying.

Actual new Step 10 page requires companion files in merged_step10_files;
copying the Dart page alone is insufficient.

Locally checked: diff of uploaded file against Step 9 reference; exact
new package files and PowerShell guard. Flutter and emulator execution has
NOT been verified in this environment.
