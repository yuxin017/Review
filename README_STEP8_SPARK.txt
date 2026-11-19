THEME PARK SMART MANAGEMENT SYSTEM - STEP 8 (SPARK PLAN, NO BLAZE)

WHY
Cloud Functions require Blaze and were not deployed. This replacement uses
Firebase client Email/Password registration and protected Firestore writes.

WHAT IT DOES
1. Existing verified root administrator signs in at /admin (admin:true).
2. Create Staff uses a DIFFERENT named Firebase app, ThemeParkStaffProvisioning,
   with no saved browser session to create a new Email/Password Auth user.
3. No initial password is shown or emailed; a random 40-character password is
   discarded when registration completes.
4. The existing named ThemeParkAdmin app, with admin credentials, creates the
   staffProfiles/{newAuthUid} document. Deployed Firestore Rules must authorize it.
5. New record contains display Staff ID, name, real inbox email, eligible roles,
   INACTIVE status, server timestamp. Roles never contain super_admin.
6. The existing UI separately requests Firebase's built-in password-reset email.
   If mail sending fails AFTER account creation, do NOT retry Create Staff; use
   Resend Setup Email in the Staff Management page.
7. New employee sets a password, goes to /staff, signs in, verifies email and
   asks supervisor to activate. No staff:true custom Auth claim is required.
8. Even after activation the Staff Portal is READ-ONLY. No ticket scan, photo
   upload, attraction operation or staff-shift authority is granted.

CRITICAL SECURITY LIMITATIONS
- Spark client SDK cannot securely set custom Auth claims. Only Staff Profiles
  written under verified administrator Firestore Rules grant staff UI access.
- Your existing rules treat admin:true as a root admin. If later more admin
  accounts exist, revise root-admin scoping before exposing management UI.
- Auth signup itself is not a privileged operation; public visitors can also
  register Firebase Auth accounts. Registration alone never grants staff access.
- This is a small FYP demo. Provisioning is not atomic across Firebase Auth
  and Firestore. The client attempts rollback on failure; if rollback fails,
  manually reconcile the orphan account. Staff IDs are eight-digit random
  display identifiers checked for collisions (not fully concurrency-safe).
- A suspended/inactive Staff Profile denies Staff Portal UI, but cannot disable
  the underlying Firebase Auth account without trusted admin backend. Existing
  staff-specific data remains protected by Firestore Rules; operational actions
  must be separately protected before launch. Do not grant staff admin:true.
- Do not use this client-only solution as a production-safe HR identity system.
- Firebase emails go to an existing real mailbox. Firebase does not create
  Gmail/Outlook inboxes. Spark quotas apply; delivery is not guaranteed.

INSTALL
1. Download Staff_Workforce_Step8_Spark_Free.zip to Windows Downloads.
2. From your FYP_New PowerShell terminal:
   Expand-Archive -Path "$HOME\Downloads\Staff_Workforce_Step8_Spark_Free.zip" -DestinationPath "."
3. Run: .\APPLY_SPARK_STAFF_STEP8.ps1
4. Run: flutter analyze lib/admin/staff
5. Run: flutter test test/admin/staff_portal_policy_test.dart test/admin/staff_spark_policy_test.dart test/admin/staff_access_test.dart test/admin/staff_records_test.dart
6. Run Spark-specific local Firebase rules test:
   firebase emulators:exec --config firebase.staff-emulators.json --only auth,firestore --project demo-themepark-fyp "node --test test/emulator/staff_spark_rules.test.cjs"
   (must show pass 3, fail 0)
7. Restart web app: .\tool\run-app.cmd -Restart
8. Open http://127.0.0.1:5173/#/admin, Staff Management.

BEFORE TESTING LIVE
- Firebase Console > Authentication > Sign-in method > Email/Password ENABLED.
- Step 6 Firestore Rules ALREADY DEPLOYED (only admin can write staffProfiles).
- Do not deploy Step 6 Cloud Function. The function source may remain in code
  but is unused by this new UI.
- Use a fresh REAL email address the test staff member can read. If a prior
  attempt created the Auth user, first inspect Auth Users and staffProfiles.
- Do not use an account already used by visitors/admin; Firebase will reject
  its email as already in use. Linking existing accounts requires an additional
  separate security-reviewed flow.

NOTES
The package updates 4 Step 6/7 files, plus the existing Staff Management
screen's informational message/error hints, and adds pure-policy and
Firestore Emulator tests.
It refuses to overwrite unknown modifications and keeps timestamped backups.
It NEVER touches existing CrowdSense, Ticket, main.dart, or firestore.rules.
The Step 8 ZIP has not been compiled on your Windows Flutter environment;
flutter analyze / flutter test results there are the acceptance checks.
