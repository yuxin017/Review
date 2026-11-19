STEP 2 — STAFF PERMISSION FOUNDATION (NON-DESTRUCTIVE)

This package ADDS only:
  lib/admin/staff/staff_access.dart
  test/admin/staff_access_test.dart

No existing Flutter screens, Firebase rules or databases are changed.

1. Extract ZIP into your existing FYP_New folder (do not replace project files).
2. From the FYP_New PowerShell terminal, run:
   git status --short
   flutter test test/admin/staff_access_test.dart

If `flutter` is not on PATH, use the Flutter SDK path that the project launcher
sets up, or send the error to ChatGPT for the exact command.

IMPORTANT:
The classes in this package are a permission vocabulary/UI preview only.
They are NOT security enforcement. Do NOT grant the admin:true custom claim
to photographer/operator/admission accounts. The next step must implement
trusted backend/Firestore authorization before enabling restricted staff.

The leave, qualifications and shift records will be stored in Firebase in a
later step. Do not add staff test data to production manually at this stage.
