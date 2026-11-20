'use strict';
// FYP local Stripe Sandbox backend. Demo on your own Windows computer without Firebase Blaze.
// Reuses the exact Stripe checkout / signed-webhook / idempotent ticket-issuance logic
// already shipped in functions/src/stripe_ticket_gateway.js.
// NEVER expose this HTTP process to the public Internet or use live Stripe keys.
const http = require('node:http');
const {initializeApp, getApps, applicationDefault} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {createStripeGateway,verifyStripeEvent} = require('./src/stripe_ticket_gateway');
const {createCommerceStripeGateway} = require('./src/stripe_commerce_gateway');
const {createPhotoHandlers} = require('./src/photos');
const {createCommerceOperations} = require('./src/stripe_commerce_operations'); // PARKSMART_V15_PAYMENT_CROWD
const {createRefundRequestHandlers} = require('./src/stripe_refund_requests'); // PARKSMART_V16_REFUND_CROWD_HISTORY

const port = Number(process.env.LOCAL_STRIPE_PORT || 8788);
const host = '127.0.0.1';
const projectId = process.env.FIREBASE_PROJECT_ID || 'themeparksmartmanagement';
if (!process.env.STRIPE_SECRET_KEY?.startsWith('sk_test_')) {
  console.error('Missing STRIPE_SECRET_KEY (must be a Stripe sandbox sk_test_ key).'); process.exit(1);
}
if (!process.env.STRIPE_WEBHOOK_SECRET?.startsWith('whsec_')) {
  console.error('Missing STRIPE_WEBHOOK_SECRET from `stripe listen`.'); process.exit(1);
}
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('Missing GOOGLE_APPLICATION_CREDENTIALS path to a private Firebase service account JSON.'); process.exit(1);
}
if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  console.error('Invalid LOCAL_STRIPE_PORT'); process.exit(1);
}
if (!getApps().length) initializeApp({credential:applicationDefault(),projectId});
const gateway = createStripeGateway({
  db:getFirestore(), FieldValue,projectId,
  getStripeKey:()=>process.env.STRIPE_SECRET_KEY,
  getWebhookSecret:()=>process.env.STRIPE_WEBHOOK_SECRET,
});
const commerce=createCommerceStripeGateway({db:getFirestore(),FieldValue,projectId,
  photos:createPhotoHandlers({db:getFirestore(),FieldValue,
    ai:{call:async()=>{throw new Error('Photo rendering uses the main Node server.');}},
    mailReady:()=>true}),
  getStripeKey:()=>process.env.STRIPE_SECRET_KEY,
});
const operations=createCommerceOperations({
  db:getFirestore(),FieldValue,commerce,
  getStripeKey:()=>process.env.STRIPE_SECRET_KEY,
});
const refundRequests=createRefundRequestHandlers({db:getFirestore(),FieldValue,operations});
const handlers = {
  '/stripeSouvenirRefundRequest':refundRequests.requestRefund,
  '/stripeSouvenirRefundDecision':refundRequests.decideRefund,
  '/stripeCommerceRecover':refundRequests.recoverCheckout,
  '/stripeCommerceCancel':operations.cancel,
  // v16: removed direct refund route; approval is mandatory.

  '/stripeSouvenirQuote':commerce.quote,
  '/stripeCommerceCheckout':commerce.start,
  '/stripeCommerceStatus':commerce.status,
  '/stripeTicketQuote':gateway.quote,
  '/stripeTicketCheckout':gateway.start,
  '/stripeTicketStatus':gateway.status,
  '/stripeTicketCancel':gateway.cancel,
};
const MAX_BODY = 1024 * 1024;
function originAllowed(origin) {
  if (!origin) return true;
  try {
    const url=new URL(origin);
    return url.protocol==='http:' && ['localhost','127.0.0.1'].includes(url.hostname) ||
      url.protocol==='https:' && [`${projectId}.web.app`,`${projectId}.firebaseapp.com`].includes(url.hostname);
  } catch (_) {return false;}
}
function reply(res, status, payload) {
  res.writeHead(status, {'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});
  res.end(JSON.stringify(payload));
}
// PARKSMART_V19_ANDROID_PAYMENT_RETURN: browser-only landing page for USB-connected Android Stripe TEST.
// Never infer a paid order from URL parameters; the authenticated mobile client checks Stripe status.
function mobilePaymentReturnPage(res, parsedUrl) {
  const ticket = parsedUrl.searchParams.has('ticket_payment');
  const commerce = parsedUrl.searchParams.has('commerce_payment');
  if (ticket === commerce) {reply(res, 400, {error:'Invalid return type.'});return;}
  const order = parsedUrl.searchParams.get('order') || '';
  if (!(ticket ? /^[a-f0-9]{48}$/ : /^[a-f0-9]{64}$/).test(order)) {
    reply(res, 400, {error:'Invalid checkout reference.'});return;
  }
  const kind = ticket ? 'ticket' :
    parsedUrl.searchParams.get('purchase_type') === 'photo' ? 'photo' : 'souvenir';
  const outcome = parsedUrl.searchParams.get(ticket ? 'ticket_payment' : 'commerce_payment');
  if (!['success','cancel'].includes(outcome)) {
    reply(res, 400, {error:'Invalid checkout return.'});return;
  }
  // Chrome may block programmatic external-app launches without a user gesture.
  // The prominent link is a real user click and remains available as a fallback.
  const intentLink = `intent://payment?kind=${kind}&order=${order}#Intent;scheme=parksmart-fyp;package=my.edu.tarumt.collaborative_asg;end`;
  const heading = outcome === 'success' ? 'Return to Theme Park' : 'Checkout closed';
  const detail = 'Open the app to verify your payment with Stripe. This page does not confirm payment.';
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${heading}</title>
  <style>body{margin:0;background:#fff6f4;color:#352528;font-family:system-ui,-apple-system,sans-serif;display:grid;min-height:100vh;place-items:center;padding:20px;box-sizing:border-box}main{max-width:420px;background:white;border:1px solid #e3d5d3;border-radius:20px;padding:30px;box-shadow:0 12px 30px #3b1c1c16}h1{font-size:24px;margin:0 0 14px}p{line-height:1.55}.btn{display:block;text-align:center;padding:15px;background:#ad7472;color:white;text-decoration:none;border-radius:12px;font-weight:650;margin:22px 0 16px}.sub{font-size:13px;color:#645257}</style></head><body><main><h1>${heading}</h1><p>${detail}</p><a class="btn" href="${intentLink}">Return to Theme Park App</a><p class="sub">If Chrome stays on this page, tap the button above. If the app isn't installed, reopen it manually. Your payment status is verified inside the app.</p></main><script>try{window.location.href=${JSON.stringify(intentLink)}}catch(_){}</script></body></html>`;
  res.writeHead(200, {
    'Content-Type':'text/html; charset=utf-8', 'Cache-Control':'no-store',
    'X-Content-Type-Options':'nosniff', 'Referrer-Policy':'no-referrer',
    'Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  });
  res.end(html);
}

function readBuffer(req) {
  return new Promise((resolve, reject)=>{
    const chunks=[]; let size=0;
    req.on('data', chunk=>{
      size+=chunk.length;
      if(size>MAX_BODY){reject(new Error('Payload too large'));req.destroy();return;}
      chunks.push(chunk);
    });
    req.on('end',()=>resolve(Buffer.concat(chunks)));
    req.on('error',reject);
  });
}
http.createServer(async(req,res)=>{
  const parsedUrl = new URL(req.url || '/', 'http://127.0.0.1'); // PARKSMART_V19_ANDROID_PAYMENT_RETURN
  const route = parsedUrl.pathname;
  const origin=req.headers.origin;
  if(!originAllowed(origin)) {reply(res,403,{error:'This application origin is not allowed.'});return;}
  if (origin) {
    res.setHeader('Access-Control-Allow-Origin',origin);
    res.setHeader('Vary','Origin');
    res.setHeader('Access-Control-Allow-Headers','Authorization, Content-Type');
    res.setHeader('Access-Control-Allow-Methods','POST, OPTIONS');
  }
  if(req.method==='OPTIONS'){res.writeHead(204);res.end();return;}
  if (req.method==='GET' && route==='/health') {reply(res,200,{ok:true,mode:'stripe_test',projectId});return;}
  if(req.method==='GET' && route==='/' && (parsedUrl.searchParams.has('commerce_payment') || parsedUrl.searchParams.has('ticket_payment'))) {
    mobilePaymentReturnPage(res, parsedUrl);return;
  }
  if(req.method!=='POST'||(route!=='/stripeTicketWebhook'&&!handlers[route])){
    reply(res,404,{error:'Unknown payment endpoint.'});return;
  }
  try {
    if(route==='/stripeTicketWebhook') {
      const raw=await readBuffer(req);
      // Signature verification MUST occur before any payment/order mutation.
      const event=verifyStripeEvent(raw,req.headers['stripe-signature'],process.env.STRIPE_WEBHOOK_SECRET);
      const session=event.data?.object;
      if(['refund.created','refund.updated','refund.failed'].includes(event.type)) {
        const verified=await operations.onRefundEvent(event);
        if (verified) await refundRequests.syncRefundStatus(event.data?.object?.metadata?.orderId);
        reply(res,200,{received:true});return;
      }
      if(['souvenir','photo'].includes(session?.metadata?.checkoutType)) {
        if(['checkout.session.completed','checkout.session.async_payment_succeeded'].includes(event.type) && session.payment_status==='paid') {
          await commerce.fulfill(session);
        } else if(event.type==='checkout.session.expired') {
          await commerce.expired(session);
        }
        reply(res,200,{received:true});return;
      }
      const webhookReq={method:req.method,headers:req.headers,rawBody:raw};
      // The original handler expects an Express-like response.
      const webhookRes={
        status(s){this.statusCode=s;return this;},
        send(value){if(!res.writableEnded) reply(res,this.statusCode||200,{message:String(value)});},
        json(value){if(!res.writableEnded) reply(res,this.statusCode||200,value);},
      };
      await gateway.webhook(webhookReq,webhookRes);
      return;
    }
    const authHeader=req.headers.authorization || '';
    if(!authHeader.startsWith('Bearer ')) {reply(res,401,{error:'Sign in to your Visitor account first.'});return;}
    const token=authHeader.slice('Bearer '.length);
    const decoded=await getAuth().verifyIdToken(token,true);
    if(!decoded.email_verified){reply(res,403,{error:'Verify your email before payment.'});return;}
    const body=JSON.parse((await readBuffer(req)).toString('utf8'));
    if(!body || Array.isArray(body) || typeof body!=='object') {reply(res,400,{error:'Invalid checkout data.'});return;}
    const result=await handlers[route]({data:body,auth:{uid:decoded.uid,token:decoded}});
    reply(res,200,result);
  } catch(err) {
    const mapped={
      'invalid-argument':400,'unauthenticated':401,'permission-denied':403,
      'not-found':404,'already-exists':409,'failed-precondition':412,
      'resource-exhausted':429,'unavailable':503,
    };
    const status=mapped[err.code] || 500;
    if(status>=500) console.error('[Payment backend]',err);
    reply(res,status,{error:status>=500?'Payment service is temporarily unavailable. Please try again.':String(err.message || 'Payment request failed.')});
  }
}).listen(port,host,()=>{
  console.log(`Stripe sandbox payment backend ready: http://${host}:${port}`);
  console.log('Use Stripe CLI `stripe listen --forward-to 127.0.0.1:'+port+'/stripeTicketWebhook` in a separate terminal.');
  console.log('This process must remain running while you test payment.');
});

// PARKSMART_V15_PAYMENT_CROWD: a bounded reconciliation pass while local TEST server runs.
let commerceReconcileBusy=false;
const commerceReconcileTimer=setInterval(async()=>{
  if(commerceReconcileBusy)return;
  commerceReconcileBusy=true;
  try{const summary=await operations.reconcilePending({limit:35});
    if(summary.expired||summary.paid||summary.refundsSettled||summary.errors||summary.missing)
      console.log('[commerce-reconcile]',summary);
  }catch(e){console.error('[commerce-reconcile]',e);}
  finally{commerceReconcileBusy=false;}
},60000);
commerceReconcileTimer.unref();
