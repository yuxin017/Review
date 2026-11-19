'use strict';
const {HttpsError} = require('firebase-functions/v2/https');
const {requireStaffShift} = require('./staff_shift_access');

/** A small trusted-server guard; never use client roles to authorize. */
async function requirePhotoStaff({db,reader,request,role,forceShift=false,clock=()=>new Date()}) {
  const uid = request.auth?.uid;
  if (!uid || request.auth?.token?.email_verified !== true) {
    throw new HttpsError('unauthenticated', 'Please sign in with a verified account.');
  }
  if (!forceShift && request.auth.token.admin === true) return uid;
  return requireStaffShift({db,reader,request,now:clock()},role);
}
module.exports = {requirePhotoStaff};
