'use strict';
// Small in-memory contract check. Does NOT connect Firebase/Stripe.
const assert=require('node:assert/strict');
const Module=require('node:module');
const original=Module._load;
class HttpsError extends Error {constructor(code,message){super(message);this.code=code;}}
Module._load=function(name,parent,isMain){
  if(name==='firebase-functions/v2/https')return{HttpsError};
  if(name==='./stripe_ticket_gateway')return{checkoutOrigin:url=>new URL(url).origin};
  return original.apply(this,arguments);
};
const {createCommerceStripeGateway}=require('./functions/src/stripe_commerce_gateway.js');
Module._load=original;
const clone=v=>structuredClone(v);
const records=new Map([
 ['visitors/test-user',{loyaltyPoints:0}],
 ['parkMenuItems/p1',{storeId:'s1',name:'Cap',priceMinor:1800,stockQuantity:2,active:true,currency:'MYR',imageUrl:''}],
 ['attractions/s1',{kind:'shops',category:'shopping',status:'open'}],
]);
function ref(path){return{path,get:async()=>snap(path),update:async data=>update(path,data)}}
function snap(path){return{id:path.split('/').at(-1),exists:records.has(path),data(){return clone(records.get(path))}}}
function update(path,changes){const p=records.get(path);if(!p)throw Error('not found: '+path);records.set(path,{...p,...clone(changes)})}
const db={doc:ref,runTransaction:async callback=>{
 const actions=[];
 const tx={
  get:async r=>snap(r.path),getAll:async(...refs)=>refs.map(r=>snap(r.path)),
  create:(r,doc)=>actions.push(()=>{if(records.has(r.path))throw Error('duplicate');records.set(r.path,clone(doc))}),
  update:(r,doc)=>actions.push(()=>update(r.path,doc)),
 };
 const result=await callback(tx);
 for(const a of actions)a();
 return result;
}};
const FieldValue={serverTimestamp:()=>new Date(),delete:()=>null};
let createdSession;
const api=async(_key,method,path,body)=>{
 if(method==='POST'){
   createdSession={id:'cs_test_123',url:'https://checkout.stripe.com/c/pay/cs_test_123',
     metadata:{checkoutType:'souvenir',orderId:body.client_reference_id,uid:'test-user'},
     client_reference_id:body.client_reference_id,amount_total:Number(body['line_items[0][price_data][unit_amount]']),
     currency:'myr',payment_status:'paid',status:'complete',livemode:false};
   return createdSession;
 }
 if(method==='GET')return createdSession;
 throw Error('unexpected');
};
const commerce=createCommerceStripeGateway({db,FieldValue,api,photos:{quote:async()=>({totalMinor:500}),checkoutPaid:async()=>({orderId:'phototest'})},getStripeKey:()=> 'sk_test_local',projectId:'themeparksmartmanagement'});
const request={auth:{uid:'test-user',token:{email_verified:true,email:'test@example.com',auth_time:1000}},data:{
  type:'souvenir',requestId:'a'.repeat(48),items:[{id:'p1',quantity:1}],returnUrl:'http://localhost:5173/',
}};
(async()=>{
 const q=await commerce.quote(request);assert.equal(q.totalMinor,1800);
 const s=await commerce.start(request);assert.equal(s.status,'pending');assert.equal(records.get('parkMenuItems/p1').stockQuantity,1);
 const again=await commerce.start(request);assert.equal(again.orderId,s.orderId);assert.equal(records.get('parkMenuItems/p1').stockQuantity,1);
 assert.equal(await commerce.fulfill(createdSession),'paid');assert.equal(records.get('souvenirOrders/'+s.orderId).status,'paid');
 assert.equal(await commerce.fulfill(createdSession),'paid');assert.equal(records.get('parkMenuItems/p1').stockQuantity,1);
 console.log('PASS: quote, stock reservation, repeat-checkout idempotency, paid fulfillment, repeat webhook');
})().catch(e=>{console.error(e);process.exitCode=1});
