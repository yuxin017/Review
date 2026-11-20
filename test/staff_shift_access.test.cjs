'use strict';

const assert = require('node:assert/strict');
const {test} = require('node:test');
const {currentStaffShift, requireStaffShift, requireStaffRole} = require('../functions/src/staff_shift_access');

const start = date => new Date(date + 'T01:00:00Z');
const end = date => new Date(date + 'T09:00:00Z');
const shift = (roleCode, day, attractionIds = []) => ({
  roleCode, startsAt: start(day), endsAt: end(day), published: true, attractionIds,
});

function fixture() {
  const profile = {
    status: 'active',
    email: 'staff@example.test',
    eligibleRoles: ['admission_staff', 'attraction_operator'],
  };
  const shifts = [
    shift('admission_staff', '2026-11-19'),
    shift('attraction_operator', '2026-11-20', ['coaster', 'ferris-wheel']),
  ];
  const qualifications = [
    {roleCode: 'admission_staff', status: 'approved', completedAt: start('2026-11-01')},
    {roleCode: 'attraction_operator', status: 'approved', completedAt: start('2026-11-01'), attractionId: 'coaster'},
  ];
  const leave = [];
  const docs = {
    staffPublishedShifts: shifts, staffQualifications: qualifications, staffLeaveRequests: leave,
  };
  const snapshot = data => ({data: () => data});
  const db = {
    doc: path => ({get: async () => snapshot(path === 'staffProfiles/worker' ? profile : undefined)}),
    collection: name => ({where: (_, __, uid) => ({
      get: async () => {
        assert.equal(uid, 'worker');
        return {docs: docs[name].map(snapshot)};
      },
    })}),
  };
  const request = {auth: {uid: 'worker', token: {email: profile.email, email_verified: true, admin: true}}};
  return {db, request, shifts, leave, qualifications, profile};
}

test('the same account can only perform the active role, even with a legacy admin claim on staff endpoints', async () => {
  const f = fixture();
  const first = {...f, now: start('2026-11-19')};
  const second = {...f, now: start('2026-11-20')};
  assert.equal(await requireStaffShift(first, 'admission_staff'), 'worker');
  await assert.rejects(requireStaffShift(first, 'attraction_operator', 'coaster'), {code: 'permission-denied'});
  await assert.rejects(requireStaffShift(second, 'admission_staff'), {code: 'permission-denied'});
  assert.equal(await requireStaffShift(second, 'attraction_operator', 'coaster'), 'worker');
  await assert.rejects(requireStaffShift(second, 'attraction_operator', 'ferris-wheel'), {code: 'permission-denied'});
});

test('ends, conflicts, approved leave, and revoked qualifications fail closed', async () => {
  const f = fixture();
  assert.equal(await currentStaffShift({...f, now: end('2026-11-19')}), null);
  const onDuty = {...f, now: start('2026-11-19')};
  f.shifts.push({...f.shifts[0], roleCode: 'attraction_operator'});
  assert.equal(await currentStaffShift(onDuty), null);
  f.shifts.pop();
  f.leave.push({status: 'approved', startOn: '2026-11-19', endOn: '2026-11-19'});
  assert.equal(await currentStaffShift(onDuty), null);
  f.leave.pop();
  f.qualifications[0].status = 'revoked';
  assert.equal(await currentStaffShift(onDuty), null);
});

test('regular duty has Malaysia working hours without a published shift', async () => {
  const f = fixture();
  f.profile.eligibleRoles = ['operations_manager'];
  f.shifts.length = 0;
  const onDuty = {...f, now: start('2026-11-19')};
  assert.equal((await currentStaffShift(onDuty)).role, 'operations_manager');
  assert.equal(await currentStaffShift({...f, now: end('2026-11-19')}), null);
  f.leave.push({status: 'approved', startOn: '2026-11-19', endOn: '2026-11-19'});
  assert.equal(await currentStaffShift(onDuty), null);
});

test('portal roles work without a shift and stay scoped to current qualifications', async () => {
  const f = fixture();
  f.shifts.length = 0;
  const request = {auth: {...f.request.auth, token: {...f.request.auth.token, admin: false}}};
  const options = {...f, request, now: end('2026-11-20')};
  assert.equal(await requireStaffRole(options, 'admission_staff'), 'worker');
  assert.equal(await requireStaffRole(options, 'attraction_operator', 'coaster'), 'worker');
  await assert.rejects(requireStaffRole(options, 'attraction_operator', 'ferris-wheel'), {code: 'permission-denied'});
  await assert.rejects(requireStaffRole(options, 'marketing_staff'), {code: 'permission-denied'});
  f.profile.status = 'inactive';
  await assert.rejects(requireStaffRole(options, 'admission_staff'), {code: 'permission-denied'});
});
