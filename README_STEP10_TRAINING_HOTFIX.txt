Step 10 Training Qualification Emulator Hotfix
===============================================

WHY 2 OF 12 TESTS FAILED
- The old Step 4 test creates free-text Training Qualifications with no courseId.
- Step 10 now uses a central Training Course Catalogue.
- Step 10's migration incorrectly required courseId on existing historical records too,
  stopping old training records from being revoked.

FIX
1) New training approvals MUST include courseId matching an active registered course.
2) Older records with no courseId remain readable and can be revoked by Admin.
3) Qualification updates can only change approved -> revoked (other fields immutable).
4) The Step 4 emulator test uses a registered course, tests that missing / invalid
   course IDs are rejected, and tests safe revocation of an old document.

HOW TO INSTALL
Run in FYP_New PowerShell:

Expand-Archive -Path "$HOME\Downloads\Staff_Step10_Training_Hotfix.zip" -DestinationPath "."
.\APPLY_STEP10_TRAINING_HOTFIX.ps1
node --check test/emulator/staff_rules.test.cjs
firebase emulators:exec --config firebase.staff-emulators.json --only auth,firestore --project demo-themepark-fyp "node --test test/emulator/staff_rules.test.cjs test/emulator/staff_spark_rules.test.cjs test/emulator/staff_step10_rules.test.cjs"

git --no-pager diff --check -- firestore.rules

DO NOT deploy rules if tests fail. Script does NOT deploy or delete data.
The patch only writes firestore.rules and test/emulator/staff_rules.test.cjs,
backing up both. If local files differ from expected versions, it stops.
