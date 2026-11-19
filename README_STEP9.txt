STAFF WORKFORCE — STEP 9: UI/FORM FIXES

What this changes:
- Uses the same AdminHeading and AdminCard as Visitor Accounts.
- Replaces the oversized pink Create Staff dialog with a compact white dialog.
- Adds inline Full Name and Email validation; rejects "123" and "11".
- Replaces long role checklists with grouped multi-select chips.
- Adds a real Status dropdown button on every staff directory row.
- Status changes ask for confirmation, preserve Staff ID/roles/training and
  write through the existing StaffRecordsRepository under Firestore Rules.
- Separates Edit Details / Roles from Change Status.
- Keeps Spark Firebase Auth onboarding and Resend Setup Email unchanged.

INSTALL (PowerShell inside FYP_New):
  Expand-Archive -Path "$HOME\Downloads\Staff_Workforce_Step9_UI_Redesign.zip" -DestinationPath "."
  .\APPLY_STAFF_UI_STEP9.ps1
  flutter analyze lib/admin/staff
  flutter test test/admin/staff_form_validation_test.dart test/admin/staff_spark_policy_test.dart test/admin/staff_access_test.dart test/admin/staff_records_test.dart
  .\tool\run-app.cmd -Restart

Look at http://127.0.0.1:5173/#/admin > Staff Management

IMPORTANT:
- Staff onboarding and profile repository both enforce the new name/email validation.
- Files are backed up before editing. The script refuses a mismatched Step 8
  project and does not replace other modules or deployed Firestore rules.
- This is user-interface/input validation, not proof an email mailbox exists.
- Status Active only allows read-only Staff Portal (after email verification).
  It does NOT grant camera, ticket admission, photo-upload, or ride operations.
- The Spark-plan provisioning implementation is for FYP demonstration and is
  not production-grade staff identity management.
