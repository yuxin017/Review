STEP 3 — STAFF FIREBASE RECORD MODELS + TRAINING BUSINESS RULES

The zip ADDS only these files:
  lib/admin/staff/staff_records.dart
  lib/admin/staff/staff_records_repository.dart
  test/admin/staff_records_test.dart

PREREQUISITE: Step 2 installed and all six staff_access_test.dart tests passed.

INSTALL:
  1. In FYP_New PowerShell terminal, run:
     Test-Path ".\lib\admin\staff\staff_records.dart"
     Test-Path ".\test\admin\staff_records_test.dart"
     Both should be False before extracting.
  2. Extract ZIP at the FYP_New project ROOT (not inside lib).
  3. Run:
     flutter test test/admin/staff_access_test.dart test/admin/staff_records_test.dart
     git status --short

ARCHITECTURE:
  staffProfiles/{uid} -- staff displayName, email, account status, eligibleRoles
  staffQualifications/{qualificationId} -- approved training and expiry per role/ride
  staffShifts/... -- NEXT STEP, not implemented in this ZIP

SECURITY AND CURRENT LIMITATIONS:
  - No existing Firebase Rules, screens, Cloud Functions, or database data changed.
  - The repository provides Firebase read/write APIs for a future Super Admin UI,
    but the current Firestore rules do NOT authorize these collections yet.
    Do NOT test the repository writes before secure rules are implemented.
  - TrainingPolicy is a client-side policy helper; it is NOT trusted authorization.
    Production permission checks must happen on Firestore Rules / backend.
  - A StaffProfile cannot assign super_admin. Super Admin requires privileged
    Firebase Auth claims maintained by a trusted administrator.
  - Existing admin:true accounts have broad legacy permissions. NEVER assign
    admin:true to restricted staff (operator, photographer, admission).
  - These tests verify pure logic only. End-to-end access verification follows.
  - No changes to your previous CrowdSense files or pubspec.lock.
