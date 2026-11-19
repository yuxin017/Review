FYP DEMO DATA SEED KIT - June to November 2026
============================================

Purpose: Fill the existing Firebase Firestore reporting collections with consistent,
clearly labelled *synthetic* visitor and transaction records for an FYP demonstration.
This is NOT verified real sales or Stripe money. Do not present it as actual revenue.

Files:
  functions/seed_fyp_demo.cjs  Node script. No Flutter code is modified.
  DEMO_PREVIEW.json        Local sample counts and month-by-month figures.
  DEMO_MONTHLY_SUMMARY.csv Local simulated order values and volumes.

Creates deterministic, repeatable test data:
  visitors, visitorAdmin, orders, tickets, loyaltyEvents, admissions,
  rideAdmissions, reservations, photoOrders, rewardVouchers.

IMPORTANT:
  * The script writes to the Firestore PROJECT YOU SELECT. It is NOT connected to
    ChatGPT and I cannot perform the import on your behalf. Run it on your PC.
  * Existing Admin Reports and Visitor Accounts read the SAME collections. Once
    imported, they will mix demo metrics with real metrics; YOU MUST LABEL THE
    RESULTS AS SYNTHETIC / TEST DATA IN YOUR FYP PRESENTATION.
  * No actual payments have been made. Synthetic orders are status 'completed'
    only so the existing Reports code can count them; paymentMethod='demo',
    paymentStatus='simulated', isDemo=true, demoBatchId attached.
  * No Firebase Auth users are created. These demo visitor profiles are for
    Admin visitor management and analytics, not real app login accounts.
  * Generated tickets are 'used' or 'demo', no ticketReferences or usable QR
    code is created. Vouchers cannot be redeemed (used or expired).
  * Use a separate demonstration Firebase project if possible. If you use
    your existing themeparksmartmanagement project, delete this synthetic data
    afterwards using the command below. Only run during your controlled demo.
  * Keep your Firebase service-account private key OUTSIDE your project and ZIP.
    Never paste it into ChatGPT or commit it to Git. After your demo, revoke an
    unneeded downloaded private key in Google Cloud IAM.

HOW TO INSTALL (WINDOWS POWERSHELL, from FYP_New project folder):

1) Extract this ZIP into your project root (this ADDS only the seed script
   under functions; it does not replace your existing source):

   Expand-Archive "$HOME\Downloads\FYP_Demo_Seed_Kit.zip" -DestinationPath (Get-Location).Path -Force

2) Preview the dataset. NO DATABASE WRITES:

   node .\functions\seed_fyp_demo.cjs --preview

3) Ensure firebase-admin module exists for Node in your functions directory.
   Only if you see "Cannot find module 'firebase-admin'", run:

   Push-Location .\functions
   npm install --no-audit --no-fund
   Pop-Location

4) Find your existing Firebase Service Account JSON file. Do NOT share it.
   Give its full path to the following input (it must be outside your project):

   $key = (Read-Host 'Firebase service-account JSON FULL PATH').Trim('"')

5) APPLY: read the preview first. THIS WRITES SYNTHETIC DATA INTO FIRESTORE:

   node .\functions\seed_fyp_demo.cjs --apply --project themeparksmartmanagement --key "$key"

6) Verify:
   Admin > Visitor Accounts: synthetic visitors should appear.
   Admin > Reports & Analytics: choose a date range WITHIN 93 DAYS,
   for example 2026-10-01 to 2026-11-18.
   REPORT NOTE: The Reports page requires its existing local /v1/park/report
   backend endpoint to work; this script does not install or activate a backend.

7) REMOVE ONLY THIS DEMO DATA AFTER THE DEMO:

   node .\functions\seed_fyp_demo.cjs --delete-demo --project themeparksmartmanagement --key "$key"

Running --apply again is idempotent: IDs are deterministic and re-used. The
script checks target records first and refuses to overwrite any non-demo
records, including records missing its special identifying tags.

If permission or quota errors occur, STOP and share only the error text,
never the service-account JSON contents, sk_test key, or whsec secret.

DATA LIMITATIONS:
- Total synthetic sample: 120 visitors; 321 ticket orders; 827 non-valid
  historical demo tickets; 589 park admissions; 433 ride check-ins;
  140 reservations; 45 photo orders; 65 expired/used vouchers.
- Some metrics only show if the backend endpoint is active.
- These are fabricated trends and revenue values. They are examples for
  demonstration, NOT evidence that a business has achieved those results.
