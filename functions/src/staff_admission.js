'use strict';

const {HttpsError} = require('firebase-functions/v2/https');
const {requireStaffShift, parkDay} = require('./staff_shift_access');

const ticketIdValid = id => /^[a-f0-9]{48}_([1-9]|10)$/.test(id);
const fail = (code, message) => { throw new HttpsError(code, message); };

function ticketView(id, data) {
  const view = {id};
  for (const key of ['orderId', 'packageName', 'guestName', 'displayCode',
                     'visitDate', 'validUntil', 'ticketType', 'status']) {
    if (data[key] !== undefined) view[key] = data[key];
  }
  return view;
}

function createStaffAdmission({db, FieldValue, clock = () => new Date()}) {
  async function find(request) {
    await requireStaffShift({db, request, now: clock()}, 'admission_staff');
    let id = String(request.data?.code ?? '').trim().replace(/^TP1:/, '');
    if (/^TP-[A-Z0-9-]{1,100}$/i.test(id)) {
      const ref = await db.doc('ticketReferences/' + id.toUpperCase()).get();
      id = ref.data()?.ticketId ?? '';
    }
    if (!ticketIdValid(id)) fail('not-found', 'Ticket not found. Check the ticket code.');
    const ticket = (await db.doc('tickets/' + id).get()).data();
    if (!ticket) fail('not-found', 'Ticket not found.');
    return ticketView(id, ticket);
  }

  async function admit(request) {
    const {ticketId, requestId} = request.data ?? {};
    if (!ticketIdValid(ticketId) || !/^[a-f0-9]{48}$/.test(requestId)) {
      fail('invalid-argument', 'Scan a valid ticket again.');
    }
    const ref = db.doc('tickets/' + ticketId);
    const receipt = db.doc('admissions/' + requestId);
    return db.runTransaction(async tx => {
      const now = clock();
      const uid = await requireStaffShift({db, reader: tx, request, now}, 'admission_staff');
      const ticket = (await tx.get(ref)).data();
      if (!ticket) fail('not-found', 'Ticket not found.');
      const day = parkDay(now);
      const dayAt = new Date(day + 'T00:00:00Z');
      const validUntil = ticket.validUntil || ticket.visitDate;
      const days = ticket.admissionDays ?? [];
      const result = (state, message) => ({state, message, ticket: ticketView(ticketId, ticket)});
      if (ticket.validationId === requestId && ticket.usedBy === uid) {
        return result('accepted', 'Admission already confirmed for this request.');
      }
      if (ticket.status === 'used' || days.some(value => value.toDate?.().getTime() === dayAt.getTime())) {
        return result('already-used', 'This ticket has already been admitted.');
      }
      if (ticket.status !== 'valid') return result('unavailable', 'This ticket is not active.');
      if (ticket.visitDate > day) return result('future', 'This ticket is valid from ' + ticket.visitDate + '.');
      if (validUntil < day) return result('expired', 'This ticket expired on ' + validUntil + '.');
      ticket.status = validUntil === day ? 'used' : 'valid';
      tx.update(ref, {
        status: ticket.status, usedAt: FieldValue.serverTimestamp(), usedBy: uid,
        validationId: requestId, lastAdmissionDay: dayAt, admissionDays: [...days, dayAt],
      });
      tx.create(receipt, {
        ticketId, orderId: ticket.orderId, ownerUid: ticket.ownerUid, actorUid: uid,
        visitDay: dayAt, createdAt: FieldValue.serverTimestamp(), outcome: 'admitted',
      });
      return result('accepted', 'Admission confirmed. Welcome to the park!');
    });
  }

  return {find, admit};
}

module.exports = {createStaffAdmission};
