'use strict';
const assert=require('node:assert/strict'),Module=require('node:module');
class HttpsError extends Error{constructor(code,message){super(message);this.code=code}}
const prev=Module._load;
Module._load=function(name){if(name==='firebase-functions/v2/https')return{HttpsError};if(name==='./stripe_ticket_gateway')return{checkoutOrigin:url=>new URL(url).origin};return prev.apply(this,arguments)};
const {createCommerceStripeGateway}=require('./functions/src/stripe_commerce_gateway.js');Module._load=prev;
const store=new Map([['visitors/u1',{}]]),clone=v=>structuredClone(v);
const snap=p=>({exists:store.has(p),data:()=>clone(store.get(p))});
const db={doc:p=>({path:p,get:async()=>snap(p),update:async d=>store.set(p,{...store.get(p),...clone(d)})}),runTransaction:async fn=>{
  const actions=[],tx={get:async r=>snap(r.path),getAll:async(...r)=>r.map(x=>snap(x.path)),create:(r,d)=>actions.push(()=>store.set(r.path,clone(d))),update:(r,d)=>actions.push(()=>store.set(r.path,{...store.get(r.path),...clone(d)}))};
  const v=await fn(tx);actions.forEach(f=>f());return v;
}};
const FieldValue={serverTimestamp:()=>new Date(),delete:()=>null};
let calls=0,session;
const photos={quote:async()=>({totalMinor:2500}),checkoutPaid:async()=>{calls++;return{orderId:'photo-verified'};}};
const api=async(_k,method,_path,body)=>{
  if(method==='POST'){
    session={id:'cs_photo_1',url:'https://checkout.stripe.com/c/pay/test',status:'complete',
      metadata:{checkoutType:'photo',orderId:body.client_reference_id,uid:'u1'},
      client_reference_id:body.client_reference_id,amount_total:2500,currency:'myr',payment_status:'paid',livemode:false};return session;
  }
  return session;
};
const gateway=createCommerceStripeGateway({db,FieldValue,api,photos,getStripeKey:()=> 'sk_test_test',projectId:'themeparksmartmanagement'});
const request={auth:{uid:'u1',token:{email_verified:true,email:'user@example.com',auth_time:123}},data:{type:'photo',requestId:'f'.repeat(48),returnUrl:'http://localhost:5173/',items:[{photoId:'test',format:'digital'}],deliveryEmail:'user@example.com'}};
(async()=>{
 const before=await gateway.start(request);assert.equal(before.status,'pending');assert.equal(calls,0);
 const payment=await gateway.status({auth:request.auth,data:{orderId:before.orderId}});
 assert.equal(payment.status,'paid');assert.equal(payment.photoOrderId,'photo-verified');assert.equal(calls,1);
 assert.equal(await gateway.fulfill(session),'paid');assert.equal(calls,1);
 console.log('PASS: paid photo not fulfilled before Stripe, verified then once only');
})().catch(e=>{console.error(e);process.exitCode=1});
