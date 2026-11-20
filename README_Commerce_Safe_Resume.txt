ParkSmart Commerce Safe Resume (for fix/staff-coverage-timetable)

Your previous 03_APPLY_COMMERCE.py stopped because a pre-existing souvenir_shop_page.dart
was not byte-for-byte identical to the distributed file.

1) Extract THIS ZIP into your FYP_New project folder. Keep the commerce_payload directory.
2) In PowerShell, while inside the FYP_New folder, run:

   python .\04_RESUME_COMMERCE_SAFE.py

This tool preserves differing pre-existing files under a timestamped BeforeCommerceResume_...
folder OUTSIDE the Git repository, stages known package files, then runs corrected
03_APPLY_COMMERCE.py. If it fails, pre-existing staged files are restored.
It refuses to overwrite files tracked by Git. It does not touch Camera Sync/Navigation files.
It does not modify GitHub or deploy anything to Firebase or Stripe.

After SUCCESS (do not run 01 or 02 again):
   flutter analyze --no-fatal-infos lib/park/visitor_navigation_page.dart lib/admin/products/park_menu_management_page.dart lib/visitor/pages/souvenir_shop_page.dart lib/commerce lib/photos/photo_checkout_pages.dart
   node --check .\functions\src\stripe_commerce_gateway.js
   node --check .\functions\local_stripe_server.cjs
   node --check .\functions\src\photos.js
   git diff --check

Before any Firebase Rules deployment, inspect the current live rules and reconcile with
local firestore.rules, especially if deployed rules might have changed since source checkout.
