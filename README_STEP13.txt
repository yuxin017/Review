STEP 13 — ATTRACTION-CENTRIC REQUIRED TRAINING (Spark compatible)

Why this change?
- When an administrator creates a new ride in Park Facilities, the system
  creates ONE required Attraction Operator course linked to that ride.
- Default name: <Attraction Name> Operation & Safety Training.
- Optionally override the course name once at creation.
- The ride + course are committed in ONE Firestore transaction.
- Staff Management > Course Catalogue remains for non-ride courses only.
- Staff Management > Record Training selects an existing course; it never
  asks for the ride again.
- When editing an old ride, existing linked courses are shown; if none exist,
  administrators may use 'Create required course' once.
- Historical ride courses without a linked attraction are NOT silently
  reassigned. Link those correctly through the legacy Course Catalogue flow.

STEP 12 PREREQUISITE:
The Step 12 course binding/Staff Portal update must already be installed.
The installer checks for the marker in Firestore Rules and the expected Staff UI.

INSTALL (PowerShell from FYP_New root):
1. Download the ZIP to Downloads.
2. Expand-Archive -Path "$HOME\Downloads\Staff_Step13_Attraction_Required_Training.zip" -DestinationPath "."
3. .\APPLY_ATTRACTION_TRAINING_STEP13.ps1

TEST (do not deploy yet):
4. flutter analyze lib/admin/attractions lib/admin/staff
5. flutter test test/admin/attraction_training_policy_test.dart
6. firebase emulators:exec --config firebase.staff-emulators.json --only auth,firestore --project demo-themepark-fyp "node --test test/emulator/staff_attraction_auto_course.test.cjs test/emulator/staff_course_binding.test.cjs"
7. git --no-pager diff --check -- firestore.rules
8. git --no-pager diff --stat -- firestore.rules

Only when all tests pass AND online Firestore Rules are reconciled with the
local version, deploy with:
  firebase deploy --only firestore:rules --project themeparksmartmanagement

Then restart the web app:
  .\tool\run-app.cmd -Restart

IMPORTANT:
- Local code changes are not active until the app has been restarted.
- The atomic creation workflow requires Step 13 Firestore Rules to be deployed.
- Existing attractions, staff, qualifications and tickets are NOT deleted.
- The installer backups modified files before writing and restores on errors.
- If an expected anchor has changed, it exits before modifying files.
- This change does not implement the Shift Scheduler or production-grade
  server-side ride-operation authorization. Shift authorization must validate
  that EVERY required training qualification is valid for the assigned ride.
- Real equipment training and refresh cycles must follow park policies and
  applicable safety requirements. This is FYP sample logic.
