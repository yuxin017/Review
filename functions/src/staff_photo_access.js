'use strict';
const {HttpsError} = require('firebase-functions/v2/https');

/** A small trusted-server guard; never use client roles to authorize. */
async function requirePhotoStaff({db,request,role,clock=()=>new Date()}) {
  const uid = request.auth?.uid;
  if (!uid || request.auth?.token?.email_verified !== true) {
    throw new HttpsError('unauthenticated', 'Please sign in with a verified account.');
  }
  if (request.auth.token.admin === true) return uid;
  const profile = await db.doc('staffProfiles/' + uid).get();
  const value = profile.data();
  if (!value || value.status !== 'active' ||
      !Array.isArray(value.eligibleRoles) || !value.eligibleRoles.includes(role) ||
      String(value.email || '').toLowerCase() !== String(request.auth.token.email || '').toLowerCase()) {
    throw new HttpsError('permission-denied', 'Your account is not approved for this work.');
  }
  const approved = await db.collection('staffQualifications')
    .where('staffUid', '==', uid)
    .where('roleCode', '==', role)
    .where('status', '==', 'approved')
    .limit(50).get();
  const now = clock();
  const valid = approved.docs.some(doc => {
    const q = doc.data();
    const completed = q.completedAt?.toDate?.();
    const expires = q.expiresAt?.toDate?.();
    return completed instanceof Date && Number.isFinite(completed.getTime()) &&
      completed <= now && (q.expiresAt == null ||
      (expires instanceof Date && expires > now));
  });
  if (!valid) throw new HttpsError('permission-denied',
    'Your training must be approved and valid before using this tool.');
  return uid;
}
module.exports = {requirePhotoStaff};
