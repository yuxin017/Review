'use strict';
// Run only on the authenticated localhost Stripe TEST server. Never in Flutter.
const crypto = require('node:crypto');
const {HttpsError} = require('firebase-functions/v2/https');
const {checkoutOrigin} = require('./stripe_ticket_gateway');
const bad = (code, message) => { throw new HttpsError(code, message); };
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const reference = value => typeof value === 'string' && /^[a-f0-9]{48}$/.test(value);
const productId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value);
const now = () => new Date();

async function stripeAPI(key, method, route, body, idempotencyKey) {
  if (!key?.startsWith('sk_test_')) bad('failed-precondition','Only Stripe test keys are supported by this local checkout service.');
  const headers = {Authorization: `Bearer ${key}`};
  if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;
  const params = {method, headers, signal: AbortSignal.timeout(20000)};
  if (body) {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    params.body = new URLSearchParams(body).toString();
  }
  const response = await fetch(`https://api.stripe.com/v1${route}`, params);
  let result;
  try { result = await response.json(); }
  catch (_) { bad('unavailable','Stripe returned an unreadable response.'); }
  if (!response.ok) bad('unavailable', String(result.error?.message ?? 'Payment service unavailable').slice(0,200));
  return result;
}

function createCommerceStripeGateway({db, FieldValue, photos, projectId, getStripeKey,
  api = stripeAPI, clock = now}) {
  const paymentRef = id => db.doc('parkCommercePayments/' + id);
  const orderRef = id => db.doc('souvenirOrders/' + id);
  function auth(request) {
    const uid = request.auth?.uid;
    if (!uid || request.auth?.token?.email_verified !== true) {
      bad('unauthenticated','Sign in using your verified visitor email.');
    }
    return uid;
  }
  function parseItems(raw) {
    if (!Array.isArray(raw) || raw.length < 1 || raw.length > 20) {
      bad('invalid-argument','Select between 1 and 20 products.');
    }
    let totalQuantity = 0;
    const unique = new Set();
    const items = raw.map(row => {
      const id = row?.id, qty = row?.quantity;
      if (!productId(id) || !Number.isInteger(qty) || qty < 1 || qty > 20 || unique.has(id)) {
        bad('invalid-argument','Invalid product or quantity.');
      }
      unique.add(id); totalQuantity += qty;
      return {id, quantity: qty};
    });
    if (totalQuantity > 30) bad('invalid-argument','Maximum 30 items per order.');
    return items.sort((a,b) => a.id.localeCompare(b.id));
  }
  async function validateBuyer(tx,uid,token) {
    const [profile, access, security] = await tx.getAll(
      db.doc('visitors/'+uid), db.doc('visitorAccess/'+uid), db.doc('accountSecurity/'+uid));
    if (!profile.exists) bad('failed-precondition','Complete your visitor profile first.');
    if (access.exists && access.data().status !== 'active') bad('permission-denied','Your visitor account is restricted.');
    if (security.data()?.closing || security.data()?.revokedBefore >= (token.auth_time ?? 0)) {
      bad('unauthenticated','Please sign in again.');
    }
  }
  async function calculateSouvenirs(tx, lines) {
    const refs = lines.map(row=>db.doc('parkMenuItems/'+row.id));
    const docs = await tx.getAll(...refs);
    const snapshots=[]; let totalMinor = 0;
    for(let i=0;i<lines.length;i++) {
      const product=docs[i].data(), line=lines[i];
      if (!product || product.active !== true || product.currency !== 'MYR' ||
        !Number.isInteger(product.priceMinor) || product.priceMinor < 1 ||
        !Number.isInteger(product.stockQuantity) || product.stockQuantity < line.quantity) {
        bad('failed-precondition','An item is unavailable or stock changed. Refresh the catalogue.');
      }
      if (!productId(product.storeId)) bad('failed-precondition','A souvenir store needs administrator review.');
      const store = await tx.get(db.doc('attractions/'+product.storeId));
      const kind = String(store.data()?.kind ?? store.data()?.category ?? '').toLowerCase();
      if (!store.exists || store.data().deletedAt || !/shop|retail|shopping|souvenir|gift/.test(kind)) {
        bad('failed-precondition','This product no longer belongs to an active shop.');
      }
      const lineMinor = product.priceMinor * line.quantity;
      totalMinor += lineMinor;
      if (totalMinor > 100000000) bad('invalid-argument','Order amount is too large.');
      snapshots.push({productId:line.id,storeId:product.storeId,name:product.name,
        quantity:line.quantity,unitPriceMinor:product.priceMinor,lineMinor,
        imageUrl:product.imageUrl??''});
    }
    return {totalMinor, snapshots, refs, docs};
  }
  async function quote(request) {
    const uid=auth(request), items=parseItems(request.data?.items);
    return db.runTransaction(async tx=>{
      await validateBuyer(tx,uid,request.auth.token);
      const result=await calculateSouvenirs(tx,items);
      return {totalMinor:result.totalMinor,currency:'MYR',items:result.snapshots};
    });
  }
  async function start(request) {
    const uid=auth(request), data=request.data??{},type=data.type;
    if (!['souvenir','photo'].includes(type) || !reference(data.requestId)) {
      bad('invalid-argument','Select a valid purchase and unique checkout reference.');
    }
    const origin=checkoutOrigin(data.returnUrl,projectId);
    const id=hash(`${uid}\u0000${type}\u0000${data.requestId}`);
    const ref=paymentRef(id);
    const token={uid,email:request.auth.token.email??'',email_verified:true,auth_time:request.auth.token.auth_time};
    let requestBody, amount, snapshot;
    if (type==='souvenir') {
      requestBody={items:parseItems(data.items)};
    } else {
      requestBody={items:data.items,pointsUsed:data.pointsUsed??0,
        promoCode:data.promoCode??'',deliveryEmail:data.deliveryEmail??token.email};
      // The existing photo quote enforces ownership, price, points and discounts.
      const result=await photos.quote({auth:{uid,token},data:requestBody});
      amount=result.totalMinor;
      if(amount>0 && amount<200)bad('failed-precondition','Online payment must be at least RM2.00.');
    }
    const finger=hash(JSON.stringify({type,body:requestBody}));
    const record=await db.runTransaction(async tx=>{
      const existing=await tx.get(ref);
      if (existing.exists) {
        const previous=existing.data();
        if (previous.ownerUid!==uid || previous.fingerprint!==finger || previous.type!==type) {
          bad('already-exists','That checkout reference is already in use.');
        }
        return previous;
      }
      await validateBuyer(tx,uid,request.auth.token);
      if (type==='souvenir') {
        const priced=await calculateSouvenirs(tx,requestBody.items);
        amount=priced.totalMinor; snapshot=priced.snapshots;
        if(amount<200)bad('failed-precondition','Online payment must be at least RM2.00.');
        for(let i=0;i<priced.refs.length;i++) {
          tx.update(priced.refs[i],{stockQuantity:priced.docs[i].data().stockQuantity-requestBody.items[i].quantity});
        }
      }
      const payload={ownerUid:uid,email:token.email,authTime:token.auth_time??0,type,status:'pending',fingerprint:finger,
        requestBody,items:snapshot??[],amountMinor:amount,currency:'MYR',
        sessionId:'',url:'',createdAt:FieldValue.serverTimestamp(),
        // For payment reconciliation. NEVER release stock purely by this timestamp.
        expiresAt:new Date(clock().getTime()+35*60*1000)};
      tx.create(ref,payload);
      return payload;
    });
    if (record.status==='paid') return {status:'paid',orderId:id};
    if (record.status==='manual_review') return {status:'manual_review',orderId:id};
    if (record.status==='expired') bad('failed-precondition','Payment expired. Create a new checkout.');
    if (record.url && record.sessionId) return {status:'pending',orderId:id,url:record.url};
    if (record.amountMinor < 1) {
      if (type==='photo' && record.amountMinor===0) {
        // Free photo orders can use the already guarded zero-cost photo checkout.
        const response=await photos.checkoutPaid({auth:{uid,token},data:{...record.requestBody,requestId:data.requestId,expectedTotalMinor:0}});
        await ref.update({status:'paid',photoOrderId:response.orderId,paidAt:FieldValue.serverTimestamp()});
        return {status:'paid',orderId:id,photoOrderId:response.orderId};
      }
      bad('failed-precondition','Invalid amount.');
    }
    // Stripe may have a currency-dependent minimum. Fail safely instead of bypassing payment.
    if (record.amountMinor<200) bad('failed-precondition','Online payment must be at least RM2.00.');
    const session=await api(getStripeKey(),'POST','/checkout/sessions',{
      mode:'payment',client_reference_id:id,'customer_email':record.email,
      'metadata[checkoutType]':type,'metadata[orderId]':id,'metadata[uid]':uid,
      'line_items[0][price_data][currency]':'myr',
      'line_items[0][price_data][unit_amount]':String(record.amountMinor),
      'line_items[0][price_data][product_data][name]':type==='souvenir'?'Park Souvenirs':'Park Photos',
      'line_items[0][quantity]':'1',
      success_url:`${origin}/?commerce_payment=success&order=${encodeURIComponent(id)}#/`,
      cancel_url:`${origin}/?commerce_payment=cancel&order=${encodeURIComponent(id)}#/`,
    },`park-commerce-${id}`);
    if (typeof session?.id!=='string'||typeof session?.url!=='string'||
        !session.url.startsWith('https://checkout.stripe.com/')) {
      bad('unavailable','Stripe could not create a secure checkout session.');
    }
    await db.runTransaction(async tx=>{
      const prior=await tx.get(ref);
      if(prior.data()?.status==='pending' && (!prior.data().sessionId || prior.data().sessionId===session.id)) {
        tx.update(ref,{sessionId:session.id,url:session.url});
      }
    });
    return {status:'pending',orderId:id,url:session.url};
  }
  async function fulfill(session) {
    const id=session?.metadata?.orderId, type=session?.metadata?.checkoutType;
    if (!/^[a-f0-9]{64}$/.test(id??'')||!['souvenir','photo'].includes(type)) return null;
    const ref=paymentRef(id),saved=await ref.get(),data=saved.data();
    if (!data || data.type!==type || data.ownerUid!==session.metadata?.uid) bad('permission-denied','Payment ownership mismatch.');
    if(session.livemode!==false||session.payment_status!=='paid'||session.client_reference_id!==id||
       session.currency!=='myr'||session.amount_total!==data.amountMinor||
       (data.sessionId && session.id!==data.sessionId)) bad('failed-precondition','Payment verification mismatch.');
    if(data.status==='paid') return 'paid';
    // PARKSMART_V15_PAYMENT_CROWD: paid refund is an immutable terminal state.
    if(data.status==='refunded') return 'refunded';
    if(data.status==='expired') bad('failed-precondition','Expired order received payment; needs manual refund review.');
    if(type==='souvenir') {
      await db.runTransaction(async tx=>{
        const prior=await tx.get(ref);
        if(prior.data()?.status==='paid')return;
        if(prior.data()?.status!=='pending')bad('failed-precondition','Unexpected payment state.');
        tx.create(orderRef(id),{
          ownerUid:data.ownerUid,kind:'souvenir',status:'paid',currency:'MYR',
          totalMinor:data.amountMinor,items:data.items,
          stripeSessionId:session.id,createdAt:FieldValue.serverTimestamp(),
          paidAt:FieldValue.serverTimestamp(),fulfillmentStatus:'awaiting_collection',
        });
        tx.update(ref,{status:'paid',paidAt:FieldValue.serverTimestamp(),sessionId:session.id});
      });
      return 'paid';
    }
    const claim=await db.runTransaction(async tx=>{
      const prior=await tx.get(ref),d=prior.data();
      if(d?.status==='paid')return false;
      if(d?.status==='processing' && d.processingUntil?.toDate?.()>clock()) return false;
      if(!['pending','processing','manual_review'].includes(d?.status))bad('failed-precondition','Unexpected photo payment state.');
      tx.update(ref,{status:'processing',processingUntil:new Date(clock().getTime()+90000)});
      return true;
    });
    if(!claim)return 'pending';
    try {
      const token={uid:data.ownerUid,email:data.email,email_verified:true,auth_time:data.authTime??0};
      // Revalidate within photo.checkout; an existing paid photo order is idempotently recovered.
      const response=await photos.checkoutPaid({auth:{uid:data.ownerUid,token},data:{
        ...data.requestBody,requestId:hash(id).slice(0,48),expectedTotalMinor:data.amountMinor,
      }});
      await ref.update({status:'paid',photoOrderId:response.orderId,
        paidAt:FieldValue.serverTimestamp(),processingUntil:FieldValue.delete(),sessionId:session.id});
      return 'paid';
    } catch (error) {
      console.error('Paid photo fulfillment requires review:',id,error);
      await ref.update({status:'manual_review',reviewReason:String(error.message??error).slice(0,300),processingUntil:FieldValue.delete()});
      return 'manual_review';
    }
  }
  async function expired(session) {
    const id=session?.metadata?.orderId, type=session?.metadata?.checkoutType;
    if(!/^[a-f0-9]{64}$/.test(id??'')||!['souvenir','photo'].includes(type)) return;
    if(session.status!=='expired'||session.payment_status==='paid')return;
    const ref=paymentRef(id);
    await db.runTransaction(async tx=>{
      const d=(await tx.get(ref)).data();
      if(!d||d.status!=='pending'||d.type!==type||d.ownerUid!==session.metadata?.uid||
          (d.sessionId && d.sessionId!==session.id))return;
      if(type==='souvenir'){
        const refs=d.items.map(p=>db.doc('parkMenuItems/'+p.productId));
        const docs=await tx.getAll(...refs);
        for(let i=0;i<refs.length;i++){
          const current=docs[i].data();
          if(current && Number.isInteger(current.stockQuantity)){
            tx.update(refs[i],{stockQuantity:current.stockQuantity+d.items[i].quantity});
          }
        }
      }
      tx.update(ref,{status:'expired',expiredAt:FieldValue.serverTimestamp()});
    });
  }
  async function status(request) {
    const uid=auth(request),id=request.data?.orderId;
    if(!/^[a-f0-9]{64}$/.test(id??''))bad('invalid-argument','Invalid order reference.');
    const ref=paymentRef(id),doc=await ref.get();
    if(!doc.exists||doc.data().ownerUid!==uid)bad('permission-denied','Order not found for this account.');
    const value=doc.data();
    if(value.status==='paid'||value.status==='manual_review'||value.status==='expired'||value.status==='refunded'){
      return {status:value.status,orderId:id,photoOrderId:value.photoOrderId??null};
    }
    if(!value.sessionId)return {status:'pending',orderId:id,url:value.url??null};
    const session=await api(getStripeKey(),'GET','/checkout/sessions/'+encodeURIComponent(value.sessionId));
    if(session.payment_status==='paid')await fulfill(session);
    else if(session.status==='expired')await expired(session);
    const updated=(await ref.get()).data();
    return {status:updated.status,orderId:id,photoOrderId:updated.photoOrderId??null,url:updated.url??null};
  }
  return {quote,start,status,fulfill,expired};
}
module.exports={createCommerceStripeGateway};
