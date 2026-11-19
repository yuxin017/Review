'use strict';

const crypto = require('node:crypto');

const ALLOWED_ROLES = new Set([
  'operations_manager',
  'attraction_operator',
  'admission_staff',
  'photographer',
  'photo_counter_staff',
  'marketing_staff',
  'customer_support',
]);

/**
 * Staff accounts are created only by a trusted callable. A role recorded in
 * staffProfiles describes job eligibility; it never grants operational access.
 * Account activation, safety training and active shift checks are separate.
 *
 * The random bootstrap password is NEVER shown, returned or stored in Firestore.
 * An admin may request a Firebase password reset email for the real mailbox.
 */
function createStaffAccountHandler({auth, db, FieldValue, HttpsError}) {
  if (!auth || !db || !FieldValue || !HttpsError) throw Error('Missing dependencies');
  const fail = (code, message) => { throw new HttpsError(code, message); };

  return async function createStaffAccount(request) {
    const caller = request?.auth;
    if (!caller?.uid || caller.token?.email_verified !== true) {
      fail('unauthenticated', 'Sign in with a verified administrator account.');
    }

    // Don't rely on client-supplied roles or cached client-side UI state.
    // Read the administrator account as it exists *now*.
    const actor = await auth.getUser(caller.uid);
    if (actor.disabled || actor.emailVerified !== true || actor.customClaims?.admin !== true) {
      fail('permission-denied', 'Only an active Super Admin may create staff accounts.');
    }

    const input = request.data || {};
    const name = typeof input.fullName === 'string' ? input.fullName.trim() : '';
    const email = typeof input.email === 'string' ? input.email.trim().toLowerCase() : '';
    const roles = input.eligibleRoles;
    if (name.length < 2 || name.length > 120 || /[\r\n\x00-\x1f]/.test(name)) {
      fail('invalid-argument', 'Enter a staff name between 2 and 120 characters.');
    }
    if (email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      fail('invalid-argument', 'Enter a valid, working email address for this employee.');
    }
    if (!Array.isArray(roles) || roles.length === 0 || roles.length > 7 ||
        new Set(roles).size !== roles.length || roles.some(role => !ALLOWED_ROLES.has(role))) {
      fail('invalid-argument', 'Select one or more eligible staff roles. Super Admin cannot be assigned here.');
    }
    // Avoid accidental visitor/staff account collisions. Do not repurpose an
    // existing Firebase account via this create-only endpoint.
    let created;
    try {
      created = await auth.createUser({
        email,
        displayName: name,
        emailVerified: false,
        disabled: false,
        password: crypto.randomBytes(32).toString('base64url') + 'aA1!',
      });
    } catch (error) {
      if (error?.code === 'auth/email-already-exists') {
        fail('already-exists', 'That email already has a Firebase account. Do not create a duplicate.');
      }
      if (error?.code === 'auth/invalid-email') {
        fail('invalid-argument', 'The email address is invalid.');
      }
      throw error;
    }

    try {
      // A *restricted* identity claim. Never set `admin:true` for frontline staff.
      await auth.setCustomUserClaims(created.uid, {staff: true});
      const staffId = await db.runTransaction(async (transaction) => {
        const seqRef = db.collection('staffCounters').doc('ids');
        const profileRef = db.collection('staffProfiles').doc(created.uid);
        const seqSnap = await transaction.get(seqRef);
        const next = seqSnap.exists ? seqSnap.data().nextNumber : 1;
        if (!Number.isSafeInteger(next) || next < 1 || next > 99999999) {
          fail('failed-precondition', 'Staff ID sequence requires administrator review.');
        }
        const id = 'STF-' + String(next).padStart(5, '0');
        transaction.set(seqRef, {
          nextNumber: next + 1,
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.create(profileRef, {
          fullName: name,
          email,
          status: 'inactive', // No operational access until approved.
          eligibleRoles: [...roles].sort(),
          staffId: id,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return id;
      });
      return {
        uid: created.uid,
        staffId,
        email,
        invitationRequired: true,
        accountStatus: 'inactive',
      };
    } catch (error) {
      // Creation is not atomic across Firebase Auth and Firestore. Attempt
      // compensation and log failures for operational recovery.
      try { await auth.deleteUser(created.uid); }
      catch (rollbackError) {
        console.error('Staff onboarding rollback failed', created.uid, rollbackError);
      }
      if (error instanceof HttpsError) throw error;
      console.error('Staff account provisioning failed', error);
      fail('internal', 'The account could not be provisioned. Please retry or contact support.');
    }
  };
}

module.exports = {createStaffAccountHandler, ALLOWED_ROLES};
