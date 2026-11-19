STEP 11 — STAFF TRAINING UX + SHORT ERROR MESSAGES (SPARK COMPATIBLE)
===================================================================

What this update does
---------------------
- Record Training now has checkboxes, allowing 1–3 completed courses at once.
- One completion date is shared by the selected courses.
- Every course has its OWN optional expiry/review date. Ride courses need a
  specified review date under this FYP's demo safety policy.
- "Set the same ride review date" assigns one date to all selected ride courses.
  Individual review dates remain editable afterwards.
- Ride-specific training choices are limited to attraction names mentioned in
  the course title, using the live attractions collection. If a course's name
  does not match a real attraction name, the UI blocks the assignment.
- All selected training records use one Firestore write batch: all succeed or
  none succeed. Existing training history is preserved.
- Short, plain-language error messages for Staff Management, create/edit,
  Training Course Catalogue, and Staff Portal.
- Existing email duplicate check still runs near the email input.
- Training expiry dates are valid THROUGH the selected calendar day.

Why expiry stays
----------------
Malaysia DOSH amusement-ride safety guidance calls for device-specific
operator training and keeping employee training records. Industry guidance
such as IAAPA also stresses ongoing refresher training and competency checks.
None of the guidance checked establishes a single universal 12-month expiry
for every ride/course. This FYP uses a configurable per-record review date:
required for ride courses, optional for non-ride system training. You can set
any valid review date under a park policy; 365 days in the date picker is only
an initial suggestion, NOT a legal requirement.

SAFETY LIMITATION
-----------------
The current Step 10 Firestore rules verify course ID, role and title, and that
an attraction ID was supplied, but they do NOT yet cryptographically bind
that course ID to an immutable attraction ID. This UI prevents obvious course-
ride mismatches, but it is NOT sufficient by itself for a production ride
operations authorization system. Before live ride operations, the course
catalogue must store an immutable attraction ID and the Firestore rules / backend
must reject mismatched IDs. No operational access is granted by this update.

Install (from FYP_New in Windows PowerShell)
---------------------------------------------
1. Expand-Archive -Path "$HOME\Downloads\Staff_Step11_Training_And_UX.zip" -DestinationPath "."
2. .\APPLY_STAFF_STEP11.ps1
3. flutter analyze lib/admin/staff
4. flutter test test/admin/staff_training_batch_policy_test.dart test/admin/staff_form_validation_test.dart test/admin/staff_email_check_test.dart test/admin/staff_access_test.dart test/admin/staff_records_test.dart
5. firebase emulators:exec --config firebase.staff-emulators.json --only auth,firestore --project demo-themepark-fyp "node --test test/emulator/staff_training_batch.test.cjs"
6. .\tool\run-app.cmd -Restart
7. Ctrl+Shift+R in Chrome. Admin > Staff Management > Record Training.

Nothing is deployed to Firebase; no database or rules changes.

Files updated (after exact-version checks and automatic backups):
 lib/admin/staff/staff_management_page.dart
 lib/admin/staff/staff_records_repository.dart
 lib/admin/staff/staff_form_validation.dart
 lib/admin/staff/staff_training_catalog.dart
 lib/admin/staff/staff_email_check.dart
 lib/admin/staff/staff_portal.dart

Files added:
 lib/admin/staff/staff_training_batch_policy.dart
 test/admin/staff_training_batch_policy_test.dart
 test/emulator/staff_training_batch.test.cjs

If the script halts because a file has newer edits, DO NOT force overwrite.
Upload that file for a safe merge. Other FYP modules are not touched.

References:
https://dosh.gov.my/wp-content/uploads/2025/12/Garis-Panduan-bagi-Pengurusan-Keselamatan-Peralatan-Taman-Hiburan-2008-1.pdf
https://iaapa.org/safety/ride-safety-report
https://iaapainsurance.com/insight-resources/seasonal-hiring-risk-management-attractions
