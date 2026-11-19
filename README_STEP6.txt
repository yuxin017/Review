STAFF WORKFORCE — STEP 6: SECURE ACCOUNT ONBOARDING
===================================================

CHECKED PRECONDITIONS
- Previous Step 3, Step 4 (emulator test), Step 5 installed.
- Staff Admin is signed in through the EXISTING /admin portal.
- This patch targets the *main* AdminShell, not the small alternative admin portal.
- Changes are local only. No automatic Firebase deployment.

WHAT IT ADDS
- Create Staff Account dialog: name, REAL email inbox, eligible roles.
- Backend callable createStaffAccount: verifies existing admin:true root account,
  provisions NEW Firebase Auth login with cryptographically random unknown password,
  sets restricted staff:true claim, creates INACTIVE staff profile and sequential
  Staff ID like STF-00001 using a Firestore transaction.
- Front end requests Firebase built-in password reset email as INITIAL PASSWORD SETUP.
- Employee owns mailbox, chooses password. No passwords are ever emailed or shown.
- Resend Setup Email button; account-created and invitation-sent are handled as
  two separate outcomes. Duplicate account creation is not attempted on email failure.
- Immutable staffId field in profile schema. Old profiles without staffId still work.
- Fix three Flutter DropdownButtonFormField deprecated `value` usages.
- Node tests with fakes for authorization, role escalation, creation and rollback.

IMPORTANT SECURITY/WORKFLOW LIMITATIONS
- Firebase Auth account is automatically created. This DOES NOT create Gmail or
  any other mailbox. Staff must have a real mailbox to receive the email.
- Password reset email is requested via Firebase client SDK. Actual delivery
  depends on project's Email/Password provider and template configuration,
  provider quotas, and email delivery. Always confirm with a real mailbox.
- A password-reset link does NOT verify an email. Future Staff Login must send
  an email verification link and check emailVerified before allowing work.
- Step 6 DOES NOT ENABLE restricted staff to sign in to the existing /admin:
  the legacy AdminPortal still requires admin:true. DO NOT give restricted
  accounts admin:true to bypass this; it grants too many rights.
- Step 6 DOES NOT enforce staff status, training or shift checks inside
  existing Ticket, Photo or Attraction backends. This is a later step.
- Existing staff accounts cannot be converted through Create Staff; it is
  create-only to avoid accidentally linking an unrelated visitor.
- Once an employee is activated later, a separate secured Staff login gate
  and effective-permission checks must be implemented.
- `staffCounters/ids` is written by the Admin SDK. It is not client-readable.
- A fatal cross-service error can leave a partially provisioned record if
  rollback fails. Server logs indicate the UID for manual recovery.

INSTALL (AFTER VERIFYING ORIGINAL LOCAL FILES)
1. Extract this ZIP into FYP_New root (same directory as pubspec.yaml).
2. Run: .\APPLY_STAFF_ONBOARDING_STEP6.ps1
   This backs up and patches ONLY these existing files:
     lib/admin/staff/staff_records.dart
     lib/admin/staff/staff_management_page.dart
     firestore.rules
     functions/themepark.js
   It ADDS new backend/client files and test files, no CrowdSense changes.
   If you modified the Step3/Step5 Dart files, script refuses to overwrite.
3. Run: node --test functions/test/staff_onboarding.test.cjs
4. Run: flutter analyze lib/admin/staff lib/admin/admin_repository.dart lib/admin/admin_shell.dart
5. Run: flutter test test/admin/staff_access_test.dart test/admin/staff_records_test.dart
6. Re-run Step4 Firestore emulator tests using saved firebase.staff-emulators.json:
   firebase emulators:exec --config firebase.staff-emulators.json --only auth,firestore --project demo-themepark-fyp "node --test test/emulator/staff_rules.test.cjs"
7. Only after tests PASS and after reviewing changes: deploy BOTH relevant
   Firestore rules and the single Cloud Function with explicit user intent.
   Typical commands (check Firebase project ID first):
   firebase use
   firebase deploy --only firestore:rules --project themeparksmartmanagement
   firebase deploy --only functions:createStaffAccount --project themeparksmartmanagement

BEFORE LIVE DEMO
- Confirm Firebase project has Email/Password enabled in Authentication.
- Confirm email templates and authorized domains in Firebase Console.
- Confirm Cloud Functions deployments are permitted by project billing/quotas.
- Use an email inbox you own for demo staff, receive setup email, set password.
- Do NOT try to log restricted staff into the existing /admin until the future
  restricted-role login gate is implemented.
