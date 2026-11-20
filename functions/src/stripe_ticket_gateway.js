 'use strict';
// Stripe Checkout hosted payment flow. Node 22 built-in fetch is used; no extra npm dependency.
const crypto = require('node:crypto');
const {HttpsError} = require('firebase-functions/v2/https');
const {createTicketPromotionHandlers} = require('./ticket_promotions');
const fail=(code,message)=>{throw new HttpsError(code,message);};

function checkoutOrigin(returnUrl,projectId){
  let url;
  try{url=new URL(returnUrl);}catch(_){fail('invalid-argument','The payment return address is invalid.');}
  const local=['localhost','127.0.0.1'].includes(url.hostname)&&url.protocol==='http:';
  const hosted=url.protocol==='https:'&&[`${projectId}.web.app`,`${projectId}.firebaseapp.com`].includes(url.hostname);
  if(!local&&!hosted)fail('invalid-argument','Use the authorised app address to complete payment.');
  return url.origin;
}

async function stripeApi(secret,method,path,params,idempotencyKey){
  const headers={'Authorization':`Bearer ${secret}`};
  if(idempotencyKey)headers['Idempotency-Key']=idempotencyKey;
  const options={method,headers,signal:AbortSignal.timeout(20000)};
  if(params){headers['Content-Type']='application/x-www-form-urlencoded';options.body=new URLSearchParams(params).toString();}
  const response=await fetch('https://api.stripe.com/v1'+path,options);
  let data;
  try{data=await response.json();}catch(_){throw new Error('Stripe returned an invalid response');}
  if(!response.ok){
    const message=String(data.error?.message??'Payment service unavailable').slice(0,240);
    throw new Error(message);
  }
  return data;
}

function verifyStripeEvent(raw,header,secret,now=Math.floor(Date.now()/1000)){
  if(!Buffer.isBuffer(raw)||raw.length>1048576||typeof header!=='string')throw new Error('Invalid Stripe webhook');
  const entries=header.split(',').map(s=>s.trim().split('=',2));
  const stamp=Number(entries.find(([key])=>key==='t')?.[1]);
  const signatures=entries.filter(([key,value])=>key==='v1'&&/^[a-f0-9]{64}$/.test(value??'')).map(([,value])=>value);
  if(!Number.isInteger(stamp)||Math.abs(now-stamp)>300||!signatures.length)throw new Error('Invalid Stripe webhook signature');
  const expected=crypto.createHmac('sha256',secret).update(String(stamp)+'.').update(raw).digest();
  if(!signatures.some(sig=>crypto.timingSafeEqual(expected,Buffer.from(sig,'hex'))))throw new Error('Webhook signature mismatch');
  const event=JSON.parse(raw.toString('utf8'));
  if(!event||typeof event.type!=='string')throw new Error('Invalid Stripe event');
  return event;
}

function createStripeGateway({db,FieldValue,getStripeKey,getWebhookSecret,projectId,api=stripeApi}){
  const ticket=createTicketPromotionHandlers({db,FieldValue});
  async function quote(request){return ticket.quote(request);}
  async function start(request){
    if(!request.auth?.uid||request.auth.token?.email_verified!==true)fail('unauthenticated','Sign in with a verified email address.');
    const data=request.data??{},origin=checkoutOrigin(data.returnUrl,projectId);
    // Validate the basket, authenticated user, price and promotion before creating Stripe session.
    const attempt=await ticket.reserveStripe(request);
    if(attempt.status==='expired')fail('failed-precondition','Checkout was cancelled or expired. Start a new payment.');
    if(attempt.status==='paid')return{status:'paid',orderId:attempt.orderId};
    if(attempt.status==='manual_review')fail('failed-precondition','Payment requires staff review. Contact support.');
    if(attempt.url)return{status:'pending',url:attempt.url,orderId:attempt.orderId};
    const encoded=encodeURIComponent(attempt.orderId);
    let session;
    try{
      session=await api(getStripeKey(),'POST','/checkout/sessions',{
        mode:'payment',client_reference_id:attempt.orderId,
        'customer_email':String(request.auth.token.email??''),
        'metadata[uid]':request.auth.uid,
        'metadata[orderId]':attempt.orderId,
        'line_items[0][price_data][currency]':'myr',
        'line_items[0][price_data][unit_amount]':String(attempt.amountMinor),
        'line_items[0][price_data][product_data][name]':'Theme Park Tickets',
        'line_items[0][quantity]':'1',
        success_url:`${origin}/?ticket_payment=success&order=${encoded}#/`,
        cancel_url:`${origin}/?ticket_payment=cancel&order=${encoded}#/`,
      },`park-tickets-${attempt.orderId}`);
    }catch(error){console.error('Stripe session creation failed',error);fail('unavailable','Unable to open the secure payment page. Please try again.');}
    if(typeof session?.url!=='string'||typeof session?.id!=='string'||!session.url.startsWith('https://checkout.stripe.com/'))fail('unavailable','Secure payment session could not be created.');
    const ref=db.doc('ticketPayments/'+attempt.orderId);
    const ready=await db.runTransaction(async tx=>{
      const current=await tx.get(ref);
      if(current.data()?.status!=='pending')return false;
      tx.update(ref,{sessionId:session.id,url:session.url});
      return true;
    });
    if(!ready)fail('failed-precondition','Checkout is no longer available.');
    return{status:'pending',url:session.url,orderId:attempt.orderId};
  }
  async function status(request){
    const id=request.data?.orderId;
    if(!request.auth?.uid||typeof id!=='string'||!/^[a-f0-9]{48}$/.test(id))fail('invalid-argument','Choose a valid checkout to verify.');
    const doc=await db.doc('ticketPayments/'+id).get();
    if(!doc.exists||doc.data().ownerUid!==request.auth.uid)fail('permission-denied','This payment is not linked to your account.');
    const attempt=doc.data();
    if(attempt.status==='paid')return{status:'paid',orderId:id};
    if(['manual_review','expired'].includes(attempt.status))return{status:attempt.status,orderId:id};
    if(!attempt.sessionId)return{status:'pending',orderId:id};
    let session;
    try{session=await api(getStripeKey(),'GET','/checkout/sessions/'+encodeURIComponent(attempt.sessionId));}
    catch(error){console.error('Stripe status verification failed',error);fail('unavailable','Unable to verify payment right now. Try again in a moment.');}
    if(session.payment_status==='paid'){
      const result=await ticket.completeStripe(session);
      return{status:result,orderId:id};
    }
    return{status:'pending',orderId:id};
  }
  async function cancel(request){
    const uid=request.auth?.uid,id=request.data?.orderId;
    if(!uid||request.auth.token?.email_verified!==true||!/^[a-f0-9]{48}$/.test(id??''))
      fail('invalid-argument','Choose a valid checkout to cancel.');
    const ref=db.doc('ticketPayments/'+id);
    const markExpired=async sessionId=>db.runTransaction(async tx=>{
      const doc=await tx.get(ref);
      if(!doc.exists){
        tx.create(ref,{ownerUid:uid,status:'expired',cancelledAt:FieldValue.serverTimestamp()});
        return {status:'expired'};
      }
      const saved=doc.data();
      if(saved.ownerUid!==uid)fail('permission-denied','This payment is not linked to your account.');
      if(saved.status!=='pending')return saved;
      if((saved.sessionId??'')!==sessionId)return saved;
      tx.update(ref,{status:'expired',url:'',cancelledAt:FieldValue.serverTimestamp()});
      return {status:'expired'};
    });
    const saved=await markExpired('');
    if(saved.status!=='pending')return {status:saved.status,orderId:id};
    const path='/checkout/sessions/'+encodeURIComponent(saved.sessionId);
    const verify=session=>{
      if(session.id!==saved.sessionId||session.client_reference_id!==id||
          session.metadata?.uid!==uid||session.metadata?.orderId!==id||
          session.currency!=='myr'||session.amount_total!==saved.amountMinor)
        fail('failed-precondition','Stripe session did not match this booking.');
      return session;
    };
    let session=verify(await api(getStripeKey(),'GET',path));
    if(session.status==='open'&&session.payment_status==='unpaid'){
      try{session=verify(await api(getStripeKey(),'POST',path+'/expire'));}
      catch(_){session=verify(await api(getStripeKey(),'GET',path));}
    }
    if(session.payment_status==='paid')
      return {status:await ticket.completeStripe(session),orderId:id};
    if(session.status==='expired'&&session.payment_status==='unpaid')
      return {status:(await markExpired(session.id)).status,orderId:id};
    return {status:'pending',orderId:id};
  }
  async function webhook(req,res){
    if(req.method!=='POST'){res.status(405).send('Method not allowed');return;}
    let event;
    try{event=verifyStripeEvent(req.rawBody,req.headers['stripe-signature'],getWebhookSecret());}
    catch(_){res.status(400).send('Invalid signature');return;}
    try{
      if(['checkout.session.completed','checkout.session.async_payment_succeeded'].includes(event.type)){
        const session=event.data?.object;
        if(session?.payment_status==='paid')await ticket.completeStripe(session);
      }
      res.status(200).json({received:true});
    }catch(error){console.error('Ticket payment fulfillment failed',error);res.status(500).send('Retry later');}
  }
  return{quote,start,status,cancel,webhook};
}
module.exports={createStripeGateway,verifyStripeEvent,checkoutOrigin};
