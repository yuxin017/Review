SMART WORKFORCE - STEP 4: REAL FIRESTORE STAFF RECORD RULES

Result: local rules and authorization tests for the existing Step 3 repository.
No Dashboard integration yet. No live Firebase data is changed until you intentionally deploy.

IMPORTANT
- You have uncommitted CrowdSense work. Do not run git reset --hard, git clean -fd, or blind git pull.
- This package adds rules to your CURRENT firestore.rules, retaining previous rules.
- Existing admin:true accounts remain the only authorized writers of staff records.
- NEVER assign admin:true to photographers, admission staff, or ride operators.
- Staff identity alone does NOT yet grant working permissions. Shift qualification + server enforcement are next steps.
- Use actual Firebase Auth UID for staffProfiles document ID. A profile does not create an Auth account.

1. Extract the ZIP contents into the FYP_New PROJECT ROOT.

2. In PowerShell (already inside FYP_New):
   .\APPLY_STAFF_FIRESTORE_RULES.ps1
   git diff -- firestore.rules

3. LOCAL TESTS (test first, not production):
   firebase emulators:exec --only auth,firestore --project demo-themepark-fyp "node --test test/emulator/staff_rules.test.cjs"

   If Firebase CLI asks for Java or fails to start emulators, share the EXACT output.
   The test explicitly refuses to run against a real Firebase project.

4. Show these results to ChatGPT. DO NOT run firebase deploy yet.

SAFETY/SCOPE
- PowerShell script backs up existing firestore.rules with a timestamped .bak file.
- No existing Dart, AdminShell, Cloud Functions, or CrowdSense files overwritten.
- Security tests verify restricted accounts cannot give themselves roles or qualifications.
- No user-facing staff management page in Step 4 (we will build it after rules pass).
- Email and UID must refer to the same real staff member: current rules can validate the shape, not Auth ownership for an arbitrary UID. Back-office identity must be verified before record creation.
- Staff profile/qualification changes still need audit logging in the later trusted backend before production usage.

SHOULD NOT BE DEPLOYED TO LIVE FIREBASE UNTIL THE EMULATOR TESTS PASS.
