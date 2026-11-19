'use strict';
// ParkSmart TEST-only operations. Requires Firebase Admin SDK and authenticated localhost API.
// Every stock adjustment is tied to a Stripe-confirmed terminal status and a Firestore transaction.
const {HttpsError} = require('firebase-functions/v2/https');
const fail = (code, message) => { throw new HttpsError(code, message); };
const safeId = id => typeof id === 'string' && /^[a-f0-9]{64}$/.test(id);
const asDate = value => value?.toDate?.() ?? (value instanceof Date ? value : null);

async function stripeApi(key, method, route, body, idempotencyKey) {
  if (!key?.startsWith('sk_test_')) fail('failed-precondition', 'Stripe Test Mode key required.');
  const headers = {Authorization: `Bearer ${key}`};
  if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;
  const args = {method, headers, signal: AbortSignal.timeout(20000)};
  if (body) {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    args.body = new URLSearchParams(body).toString();
  }
  let response;
  try { response = await fetch(`https://api.stripe.com/v1${route}`, args); }
  catch (_) { fail('unavailable', 'Could not reach Stripe; retry safely.'); }
  let json;
  try { json = await response.json(); }
  catch (_) { fail('unavailable', 'Stripe response was unreadable.'); }
  if (!response.ok) {
    fail(response.status === 409 ? 'already-exists' : 'unavailable',
      String(json?.error?.message ?? 'Stripe rejected the operation.').slice(0,220));
  }
  return json;
}

function createCommerceOperations({db, FieldValue, commerce, getStripeKey,
  api = stripeApi, clock = () => new Date(), log = console}) {
  const pRef = id => db.doc(`parkCommercePayments/${id}`);
  const oRef = id => db.doc(`souvenirOrders/${id}`);
  const authUid = request => {
    const uid = request?.auth?.uid;
    if (!uid || request?.auth?.token?.email_verified !== true)
      fail('unauthenticated', 'Sign in with a verified account.');
    return uid;
  };
  const adminUid = request => {
    const uid = authUid(request);
    if (request.auth.token.admin !== true)
      fail('permission-denied', 'Administrator permission required.');
    return uid;
  };
  const getSession = async (data, id) => {
    if (typeof data.sessionId !== 'string' || !/^cs_test_[A-Za-z0-9_]+$/.test(data.sessionId))
      fail('failed-precondition', 'Checkout session has not been recorded yet; check again shortly.');
    const session = await api(getStripeKey(), 'GET', `/checkout/sessions/${encodeURIComponent(data.sessionId)}`);
    if (session.id !== data.sessionId || session.livemode !== false ||
        session.client_reference_id !== id || session.currency !== 'myr' ||
        session.amount_total !== data.amountMinor ||
        session.metadata?.orderId !== id || session.metadata?.uid !== data.ownerUid ||
        session.metadata?.checkoutType !== data.type)
      fail('failed-precondition', 'Stripe session did not match the saved order.');
    return session;
  };
  const readPayment = async id => {
    if (!safeId(id)) fail('invalid-argument', 'Invalid payment reference.');
    const snapshot = await pRef(id).get();
    if (!snapshot.exists) fail('not-found', 'Payment not found.');
    return snapshot.data();
  };

  // Do NOT treat the Stripe cancel redirect as proof of cancellation. The API
  // must confirm that checkout is expired and unpaid before releasing stock.
  async function cancel(request) {
    const uid = authUid(request), id = request.data?.orderId;
    const saved = await readPayment(id);
    if (saved.ownerUid !== uid) fail('permission-denied', 'Not your payment.');
    if (saved.status !== 'pending') return {status: saved.status, orderId: id};
    const current = await getSession(saved, id);
    if (current.payment_status === 'paid') {
      await commerce.fulfill(current);
      return {status: 'paid', orderId: id};
    }
    if (current.status === 'expired') {
      await commerce.expired(current);
    } else if (current.status === 'open' && current.payment_status === 'unpaid') {
      let expired;
      try {
        expired = await api(getStripeKey(), 'POST',
          `/checkout/sessions/${encodeURIComponent(current.id)}/expire`);
      } catch (err) {
        // Stripe may have completed concurrently. Do not release any stock.
        const latest = await getSession(saved, id);
        if (latest.payment_status === 'paid') {
          await commerce.fulfill(latest);
          return {status: 'paid', orderId: id};
        }
        if (latest.status !== 'expired') throw err;
        expired = latest;
      }
      if (expired.status !== 'expired' || expired.payment_status === 'paid')
        fail('failed-precondition', 'Checkout did not expire; stock was not released.');
      await commerce.expired(expired);
    } else {
      return {status: 'pending', orderId: id,
        message: 'Payment is processing. Stock cannot be released yet.'};
    }
    return {status: (await readPayment(id)).status, orderId: id};
  }

  // Called only after a Stripe refund succeeded (or when an existing Stripe
  // refund is independently observed). The Firestore transaction guarantees
  // a *single* stock restoration even under duplicate webhooks/retries.
  async function settleRefund(id, refund, actorUid = 'stripe') {
    if (!safeId(id) || refund?.status !== 'succeeded') return false;
    const saved = await readPayment(id);
    if (saved.type !== 'souvenir' || saved.status !== 'paid') return false;
    const session = await getSession(saved, id);
    if (typeof session.payment_intent !== 'string' ||
        refund.payment_intent !== session.payment_intent ||
        refund.amount !== saved.amountMinor || refund.currency !== 'myr')
      fail('failed-precondition', 'Refund does not match the original Stripe payment.');
    const eventRef = db.doc(`souvenirRefundEvents/${id}`);
    return db.runTransaction(async tx => {
      const [pay, order, audit] = await tx.getAll(pRef(id), oRef(id), eventRef);
      const p = pay.data(), o = order.data();
      if (!p || !o || p.status === 'refunded' || o.status === 'refunded' || audit.exists)
        return false;
      if (p.status !== 'paid' || o.status !== 'paid' ||
          o.currency !== 'MYR' || o.totalMinor !== p.amountMinor ||
          o.fulfillmentStatus === 'collected')
        fail('failed-precondition', 'Order changed or was collected; refund needs manual review.');
      const items = Array.isArray(o.items) ? o.items : [];
      if (items.length === 0) fail('failed-precondition', 'Order has no inventory snapshots.');
      const refs = items.map(x => db.doc(`parkMenuItems/${x.productId}`));
      const inventory = await tx.getAll(...refs);
      for (let n = 0; n < items.length; n++) {
        const quantity = items[n].quantity;
        const stock = inventory[n].data()?.stockQuantity;
        if (!Number.isInteger(quantity) || quantity < 1 ||
            !Number.isInteger(stock) || stock < 0 || stock + quantity > 1000000)
          fail('failed-precondition', 'Inventory cannot be safely restored; review required.');
      }
      for (let n = 0; n < refs.length; n++)
        tx.update(refs[n], {stockQuantity: inventory[n].data().stockQuantity + items[n].quantity});
      tx.update(oRef(id), {status: 'refunded', refundStatus: 'succeeded',
        refundMinor: refund.amount, stripeRefundId: refund.id,
        refundedAt: FieldValue.serverTimestamp(), refundedByUid: actorUid});
      tx.update(pRef(id), {status: 'refunded', refundStatus: 'succeeded',
        stripeRefundId: refund.id, refundedAt: FieldValue.serverTimestamp()});
      tx.create(eventRef, {orderId: id, ownerUid: o.ownerUid,
        refundMinor: refund.amount, currency: 'MYR', stripeRefundId: refund.id,
        collected: false, actorUid, createdAt: FieldValue.serverTimestamp()});
      return true;
    });
  }

  async function observeRefund(id, refund, actorUid = 'stripe') {
    const current = await readPayment(id);
    if (current.status === 'refunded') return 'refunded';
    if (current.type !== 'souvenir' || current.status !== 'paid') return 'review';
    if (refund?.status === 'succeeded') {
      await settleRefund(id, refund, actorUid);
      return 'refunded';
    }
    if (refund?.status === 'pending' || refund?.status === 'requires_action') {
      await oRef(id).update({refundStatus: 'pending', stripeRefundId: refund.id});
      await pRef(id).update({refundStatus: 'pending', stripeRefundId: refund.id});
      return 'pending';
    }
    if (['failed', 'canceled'].includes(refund?.status)) {
      await oRef(id).update({refundStatus: 'failed', stripeRefundId: refund.id});
      await pRef(id).update({refundStatus: 'failed', stripeRefundId: refund.id});
      return 'failed';
    }
    return 'review';
  }

  async function listOriginalRefunds(paymentIntent) {
    if (typeof paymentIntent !== 'string' || !/^pi_[A-Za-z0-9]+$/.test(paymentIntent))
      fail('failed-precondition', 'Stripe payment intent is missing.');
    const all = await api(getStripeKey(), 'GET',
      `/refunds?payment_intent=${encodeURIComponent(paymentIntent)}&limit=100`);
    return Array.isArray(all.data) ? all.data : [];
  }

  async function refund(request) {
    const admin = adminUid(request), id = request.data?.orderId;
    if (request.data?.confirm !== true) fail('invalid-argument', 'Explicit refund confirmation required.');
    const saved = await readPayment(id);
    if (saved.type !== 'souvenir') fail('failed-precondition', 'Only souvenir refunds are supported.');
    if (saved.status === 'refunded') return {orderId: id, status: 'refunded'};
    if (saved.status !== 'paid') fail('failed-precondition', 'Order is not paid.');
    const order = await oRef(id).get();
    const d = order.data();
    if (!d || d.status !== 'paid' || d.fulfillmentStatus !== 'awaiting_collection')
      fail('failed-precondition', 'Collected orders require manual return review.');
    const session = await getSession(saved, id);
    if (session.payment_status !== 'paid' || !session.payment_intent)
      fail('failed-precondition', 'Stripe has not confirmed this payment.');
    // Mark the order as refund-in-progress before contacting Stripe. A
    // second administrator cannot collect it from the updated Admin UI.
    await db.runTransaction(async tx => {
      const [pay, current] = await tx.getAll(pRef(id), oRef(id));
      if (pay.data()?.status !== 'paid' || current.data()?.status !== 'paid' ||
          current.data()?.fulfillmentStatus !== 'awaiting_collection') {
        fail('failed-precondition', 'Order changed before refund.');
      }
      tx.update(pRef(id), {refundStatus: 'pending'});
      tx.update(oRef(id), {refundStatus: 'pending'});
    });
    const previous = await listOriginalRefunds(session.payment_intent);
    const applicable = previous.filter(r => r.currency === 'myr' &&
      r.payment_intent === session.payment_intent);
    const completed = applicable.find(r => r.status === 'succeeded' && r.amount === saved.amountMinor);
    if (completed) {
      await observeRefund(id, completed, admin);
      return {orderId: id, status: 'refunded'};
    }
    const active = applicable.find(r => ['pending','requires_action'].includes(r.status));
    if (active) {
      await observeRefund(id, active, admin);
      return {orderId: id, status: 'pending'};
    }
    // Never issue another full refund when manual partial / failed refund exists.
    if (applicable.length) fail('failed-precondition',
      'Existing Stripe refund requires manual review; no second refund created.');
    const created = await api(getStripeKey(), 'POST', '/refunds', {
      payment_intent: session.payment_intent,
      amount: String(saved.amountMinor),
      reason: 'requested_by_customer',
      'metadata[orderId]': id,
      'metadata[operation]': 'parksmart_souvenir_refund',
    }, `parksmart-refund-v15-${id}`);
    const status = await observeRefund(id, created, admin);
    return {orderId: id, status, stripeRefundId: created.id};
  }

  async function onRefundEvent(event) {
    const refund = event?.data?.object;
    const id = refund?.metadata?.orderId;
    if (!safeId(id) || !/^re_[A-Za-z0-9]+$/.test(refund?.id ?? '')) return false;
    const saved = await readPayment(id);
    if (saved.type !== 'souvenir') return false;
    const session = await getSession(saved, id);
    if (refund.payment_intent !== session.payment_intent ||
        refund.amount !== saved.amountMinor || refund.currency !== 'myr') {
      log.warn('[refund-webhook] Unrelated refund was ignored:', refund.id);
      return false;
    }
    await observeRefund(id, refund);
    return true;
  }

  async function reconcileOne(id, data, expireOld = true) {
    if (data.status !== 'pending' || !data.sessionId) return 'missing-session';
    const session = await getSession(data, id);
    if (session.payment_status === 'paid') { await commerce.fulfill(session); return 'paid'; }
    if (session.status === 'expired') { await commerce.expired(session); return 'expired'; }
    const until = asDate(data.expiresAt);
    if (expireOld && until && until.getTime() <= clock().getTime() &&
        session.status === 'open' && session.payment_status === 'unpaid') {
      try {
        const expired = await api(getStripeKey(), 'POST',
          `/checkout/sessions/${encodeURIComponent(session.id)}/expire`);
        if (expired.status === 'expired' && expired.payment_status !== 'paid') {
          await commerce.expired(expired);
          return 'expired';
        }
      } catch (error) {
        // May have just been paid; next pass or webhook will confirm.
        log.warn('[reconcile] Checkout could not be expired safely:', id, String(error.message ?? error));
      }
    }
    return 'pending';
  }

  async function reconcileRefund(id, data) {
    if (data.status === 'refunded' || data.type !== 'souvenir') return 'done';
    const session = await getSession(data, id);
    const existing = await listOriginalRefunds(session.payment_intent);
    const match = existing.find(r => r.amount === data.amountMinor &&
      r.currency === 'myr' && r.payment_intent === session.payment_intent &&
      ['succeeded','pending','requires_action','failed'].includes(r.status));
    if (!match) return 'missing';
    return observeRefund(id, match);
  }

  async function reconcilePending({limit = 35} = {}) {
    const take = Math.max(1, Math.min(100, limit));
    const [pending, refunds] = await Promise.all([
      db.collection('parkCommercePayments').where('status', '==', 'pending').limit(take).get(),
      db.collection('parkCommercePayments').where('refundStatus', '==', 'pending').limit(take).get(),
    ]);
    let checked = 0, expired = 0, paid = 0, refundsSettled = 0, errors = 0, missing = 0;
    for (const doc of pending.docs) {
      try {
        const outcome = await reconcileOne(doc.id, doc.data());
        checked++;
        if (outcome === 'expired') expired++;
        if (outcome === 'paid') paid++;
        if (outcome === 'missing-session') missing++;
      } catch (e) { errors++; log.error('[reconcile] Payment:', doc.id, String(e.message ?? e)); }
    }
    for (const doc of refunds.docs) {
      try {
        if (await reconcileRefund(doc.id, doc.data()) === 'refunded') refundsSettled++;
      } catch (e) { errors++; log.error('[reconcile] Refund:', doc.id, String(e.message ?? e)); }
    }
    return {checked, expired, paid, refundsSettled, missing, errors};
  }
  return {cancel, refund, reconcilePending, onRefundEvent, settleRefund};
}
module.exports = {createCommerceOperations, stripeApi};
