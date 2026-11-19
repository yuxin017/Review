'use strict';
// ParkSmart v16: server-verified visitor refund requests and admin decisions.
// Clients never write to souvenirOrders or issue Stripe refunds directly.
const crypto = require('node:crypto');
const {HttpsError} = require('firebase-functions/v2/https');
const fail = (code, text) => {throw new HttpsError(code, text);};
const validId = id => typeof id === 'string' && /^[a-f0-9]{64}$/.test(id);
const validRequest = id => typeof id === 'string' && /^[a-f0-9]{48}$/.test(id);
function createRefundRequestHandlers({db, FieldValue, operations}) {
  const orderRef = id => db.doc(`souvenirOrders/${id}`);
  const requestRef = id => db.doc(`souvenirRefundRequests/${id}`);
  function auth(req, admin = false) {
    const uid = req?.auth?.uid;
    if (!uid || req.auth?.token?.email_verified !== true) fail('unauthenticated','Sign in with a verified account.');
    if (admin && req.auth.token.admin !== true) fail('permission-denied','Administrator role required.');
    return uid;
  }
  async function requestRefund(req) {
    const uid = auth(req), id = req.data?.orderId;
    const reason = String(req.data?.reason ?? '').trim();
    if (!validId(id) || reason.length < 8 || reason.length > 500)
      fail('invalid-argument','Choose a paid purchase and give a reason (8–500 characters).');
    return db.runTransaction(async tx => {
      const [order, existing] = await tx.getAll(orderRef(id),requestRef(id));
      const o = order.data();
      if (!o || o.ownerUid !== uid) fail('permission-denied','This is not your order.');
      if (o.status !== 'paid' || o.currency !== 'MYR' || o.fulfillmentStatus !== 'awaiting_collection')
        fail('failed-precondition','Only paid, uncollected souvenirs can request an automatic refund.');
      if (existing.exists) {
        const status = existing.data().status;
        if (['requested','processing','approved','needs_review'].includes(status))
          return {status,orderId:id};
        fail('failed-precondition','This order already has a completed refund decision. Contact support.');
      }
      if (['pending','requested'].includes(o.refundStatus))
        fail('failed-precondition','This order has another refund operation.');
      tx.create(requestRef(id),{orderId:id,ownerUid:uid,status:'requested',reason,
        createdAt:FieldValue.serverTimestamp()});
      tx.update(orderRef(id),{refundStatus:'requested',refundReason:reason,
        refundRequestedAt:FieldValue.serverTimestamp()});
      return {status:'requested',orderId:id};
    });
  }
  async function decideRefund(req) {
    const adminUid = auth(req,true),id=req.data?.orderId, action=req.data?.decision;
    if (!validId(id) || !['approve','reject'].includes(action))
      fail('invalid-argument','Choose an order and an approval decision.');
    const decision = await db.runTransaction(async tx => {
      const [order, application] = await tx.getAll(orderRef(id),requestRef(id));
      const o=order.data(), r=application.data();
      if (!o || !r || r.orderId !== id || r.ownerUid !== o.ownerUid)
        fail('failed-precondition','No valid visitor refund request exists.');
      if (r.status === 'approved' && o.status === 'refunded') return 'refunded';
      if (r.status === 'rejected') return 'rejected';
      if (r.status !== 'requested' && r.status !== 'needs_review')
        fail('failed-precondition','Refund review already in progress.');
      if (r.status === 'needs_review' && action === 'reject')
        fail('failed-precondition','A Stripe refund may already be in progress. Reconcile it before rejecting.');
      if (r.status === 'requested' && o.refundStatus !== 'requested')
        fail('failed-precondition','Refund state changed; refresh before approval.');
      if (o.status !== 'paid' || o.fulfillmentStatus !== 'awaiting_collection')
        fail('failed-precondition','Order is no longer eligible for refund.');
      if (action === 'reject') {
        tx.update(requestRef(id),{status:'rejected',reviewedByUid:adminUid,
          reviewedAt:FieldValue.serverTimestamp()});
        tx.update(orderRef(id),{refundStatus:'rejected',refundReviewedByUid:adminUid,
          refundReviewedAt:FieldValue.serverTimestamp()});
        return 'rejected';
      }
      tx.update(requestRef(id),{status:'processing',reviewedByUid:adminUid,
        reviewedAt:FieldValue.serverTimestamp()});
      tx.update(orderRef(id),{refundStatus:'pending',refundReviewedByUid:adminUid,
        refundReviewedAt:FieldValue.serverTimestamp()});
      return 'process';
    });
    if (decision !== 'process') return {status:decision,orderId:id};
    try {
      const result = await operations.refund({auth:req.auth,data:{orderId:id,confirm:true}});
      await requestRef(id).update({status:result.status === 'refunded' ? 'approved' : 'processing',
        stripeRefundId:result.stripeRefundId ?? null,confirmedAt:FieldValue.serverTimestamp()});
      return {status:result.status,orderId:id};
    } catch (error) {
      // Do NOT re-enable collection: an indeterminate refund may have occurred.
      await requestRef(id).update({status:'needs_review',reviewError:String(error.message??error).slice(0,250)});
      throw error;
    }
  }
  // Stripe can finish a refund asynchronously after Admin approval. Keep the
  // separate review record consistent with the verified order state.
  async function syncRefundStatus(id) {
    if (!validId(id)) return false;
    const [order, application] = await db.getAll(orderRef(id),requestRef(id));
    if (!order.exists || !application.exists) return false;
    const o = order.data(), r = application.data();
    if (r.orderId !== id || r.ownerUid !== o.ownerUid || r.status === 'rejected') return false;
    let state;
    if (o.status === 'refunded' && o.refundStatus === 'succeeded') state = 'approved';
    else if (o.refundStatus === 'failed') state = 'needs_review';
    else if (o.refundStatus === 'pending') state = 'processing';
    else return false;
    if (r.status === state) return true;
    await requestRef(id).update({status:state,
      syncedAt:FieldValue.serverTimestamp()});
    return true;
  }
  async function recoverCheckout(req) {
    const uid=auth(req),type=req.data?.type, requestId=req.data?.requestId;
    if (!validRequest(requestId) || type!=='souvenir')
      fail('invalid-argument','Invalid checkout retry reference.');
    const id=crypto.createHash('sha256').update(`${uid}\0${type}\0${requestId}`).digest('hex');
    const doc=await db.doc(`parkCommercePayments/${id}`).get();
    if (!doc.exists) return {status:'not_found',orderId:null};
    const d=doc.data();
    if (d.ownerUid !== uid || d.type !== type) fail('permission-denied','Checkout not found.');
    return {status:d.status,orderId:id,canCheck:!!d.sessionId,
      url:d.url??null};
  }
  return {requestRefund,decideRefund,recoverCheckout,syncRefundStatus};
}
module.exports={createRefundRequestHandlers};
