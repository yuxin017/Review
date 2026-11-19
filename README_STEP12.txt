STEP 12 — Course-to-Attraction Binding + Staff Portal Fix (Firebase Spark)

WHAT IT CHANGES
- Every new Attraction Operator course must select an exact park Attraction in the course catalogue.
- Records for a staff member automatically inherit that Attraction; the record form never asks staff to choose it again.
- Courses created before this change display Link Attraction. Link the course ONCE (manually choose the actual Firestore Attraction). A bound course cannot be silently remapped.
- Training updates use a batch, and the rules check that the qualification's attractionId matches its course.
- Replaces the old Step 7 staff:true claim gate with the Spark Staff Profile gate.
- Refreshes the employee sign-in state once to register an already-verified email. It does NOT auto-activate accounts.
- No Cloud Functions, no Blaze, no database migration or automatic employee activation.

IMPORTANT: EMAIL VERIFICATION / ACTIVE
1. Password setup does not verify email automatically.
2. Staff signs in at /#/staff using exactly the Email created by Admin.
3. Staff selects Send Verification Email (if needed), opens verification link, returns and chooses Refresh Access; after this patch a new sign-in also syncs proof automatically.
4. The Admin sees Email Verified, then selects Active. Supervisor approval remains required.
5. Existing staff roles, approved training and shifts are not automatically granted or changed.

INSTALL FROM FYP_New ROOT (PowerShell)
1. Expand-Archive -Path "$HOME\Downloads\Staff_Step12_Course_Binding_and_Staff_Login.zip" -DestinationPath "."
2. .\APPLY_STAFF_STEP12.ps1
3. flutter analyze lib/admin/staff
4. flutter test test/admin/staff_training_batch_policy_test.dart test/admin/staff_access_test.dart test/admin/staff_records_test.dart test/admin/staff_portal_policy_test.dart
5. firebase emulators:exec --config firebase.staff-emulators.json --only auth,firestore --project demo-themepark-fyp "node --test test/emulator/staff_course_binding.test.cjs test/emulator/staff_rules.test.cjs test/emulator/staff_spark_rules.test.cjs test/emulator/staff_step10_rules.test.cjs test/emulator/staff_training_batch.test.cjs"
6. git --no-pager diff --check -- firestore.rules
7. Review modified rules and compare with currently deployed rules. Deploy only after passing tests and comparing deployed rules:
   firebase deploy --only firestore:rules --project themeparksmartmanagement
8. .\tool\run-app.cmd -Restart
9. Force-reload Chrome (Ctrl+Shift+R). If /staff still shows the old "This Firebase login does not have a staff identity" text, check the running server and current source file.

RUN STEP 12 EMULATORS BEFORE ANY DEPLOY. Do not upload credentials, reset Git or delete staff data.
BACKUPS ARE AUTOMATICALLY SAVED: *.before-staff-step12-[timestamp].bak

LIMITATIONS
- The release code has been statically inspected but not compiled with Flutter here. Use local flutter analyze/test as the acceptance check.
- Course binding controls training data, but actual ride-operation authorization still requires shift + training + attraction permissions enforced by the backend. Do not grant staff admin:true claims.
- The existing root-admin gate in Staff Management still relies on the legacy admin:true claim and must be restricted further before production.
- If the installer detects local code edits not matching the packaged baselines, it stops without changes. Upload the different Dart files for safe merging.
