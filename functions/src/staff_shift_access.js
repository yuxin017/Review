'use strict';

const {HttpsError} = require('firebase-functions/v2/https');
const deny = message => { throw new HttpsError('permission-denied', message); };
const time = value => value?.toDate?.() ?? value;
const dateValid = value => time(value) instanceof Date && Number.isFinite(time(value).getTime());
const parkDay = now => new Date(now.getTime() + 8 * 3600000).toISOString().slice(0, 10);

async function currentStaffShift({db, reader, request, now}) {
  const read = ref => reader ? reader.get(ref) : ref.get();
  const uid = request.auth?.uid;
  const token = request.auth?.token;
  if (!uid || token?.email_verified !== true) {
    throw new HttpsError('unauthenticated', 'Sign in with your verified staff account.');
  }

  const profile = (await read(db.doc('staffProfiles/' + uid))).data();
  const security = (await read(db.doc('accountSecurity/' + uid))).data();
  if (profile?.status !== 'active' || typeof token.email !== 'string' ||
      typeof profile.email !== 'string' ||
      profile.email.toLowerCase() !== token.email.toLowerCase() ||
      security?.closing || security?.revokedBefore >= (token.auth_time ?? 0)) {
    deny('Your staff account is not available.');
  }

  const shifts = await read(db.collection('staffPublishedShifts').where('staffUid', '==', uid));
  const active = shifts.docs.map(doc => doc.data()).filter(shift =>
    shift.published === true && dateValid(shift.startsAt) && dateValid(shift.endsAt) &&
    time(shift.startsAt) <= now && now < time(shift.endsAt));
  if (active.length !== 1) return null;
  const shift = active[0];
  if (!Array.isArray(profile.eligibleRoles) || !profile.eligibleRoles.includes(shift.roleCode)) return null;

  const day = parkDay(now);
  const leaves = await read(db.collection('staffLeaveRequests').where('staffUid', '==', uid));
  if (leaves.docs.some(doc => {
    const leave = doc.data();
    return leave.status === 'approved' && leave.startOn <= day && day <= leave.endOn;
  })) return null;

  const attractionIds = Array.isArray(shift.attractionIds) ? shift.attractionIds : [];
  const requiresTraining = ['admission_staff', 'attraction_operator', 'photographer', 'photo_counter_staff'];
  if (!requiresTraining.includes(shift.roleCode)) {
    return {role: shift.roleCode, attractionIds: [], endsAt: time(shift.endsAt).toISOString()};
  }
  const training = await read(db.collection('staffQualifications').where('staffUid', '==', uid));
  const valid = training.docs.map(doc => doc.data()).filter(record =>
    record.roleCode === shift.roleCode && record.status === 'approved' &&
    dateValid(record.completedAt) && time(record.completedAt) <= now &&
    (record.expiresAt == null || (dateValid(record.expiresAt) && time(record.expiresAt) > now)));
  if (!valid.length) return null;
  const assigned = shift.roleCode === 'attraction_operator'
    ? attractionIds.filter(id => valid.some(record => record.attractionId === id))
    : [];
  if (shift.roleCode === 'attraction_operator' && !assigned.length) return null;
  return {role: shift.roleCode, attractionIds: assigned, endsAt: time(shift.endsAt).toISOString()};
}

async function requireStaffShift(options, role, attractionId) {
  const shift = await currentStaffShift(options);
  if (shift?.role !== role ||
      (role === 'attraction_operator' && !shift.attractionIds.includes(attractionId))) {
    deny('This task is only available during the matching assigned shift.');
  }
  return options.request.auth.uid;
}

module.exports = {currentStaffShift, requireStaffShift, parkDay};
