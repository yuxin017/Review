'use strict';
// Synthetic, labelled FYP demonstration records only. No Firebase Authentication users.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const DATASET = 'FYP_DEMO_2026_JUN_NOV_V1';
const TAG = 'SYNTHETIC_FYP_DEMO_NOT_REAL_PAYMENT';
const MONTHS = [
  { month: 6, visitors: 12, orders: 20, photos: 3 },
  { month: 7, visitors: 17, orders: 31, photos: 5 },
  { month: 8, visitors: 19, orders: 47, photos: 7 },
  { month: 9, visitors: 21, orders: 63, photos: 9 },
  { month: 10, visitors: 27, orders: 88, photos: 12 },
  { month: 11, visitors: 24, orders: 72, photos: 10 },
];
const names1 = ['Aina','Hana','Amir','Daniel','Mei Ling','Jia Wen','Ariff','Farah','Ethan','Sofia','Nadia','Wei Jun','Izzat','Emma','Adam','Yun Yi','Kevin','Leena','Ravi','Chloe','Hakim','Sarah','Kai Xin','Amira'];
const names2 = ['Tan','Lim','Wong','Lee','Rahman','Ong','Cheong','Ismail','Chong','Ng','Goh','Yap','Chan','Hassan','Low','Chia','Kumar','Teo','Khoo','Aziz'];
const products = [
  { id:'demo_day', name:'1-Day Admission Pass',adult:14000,child:10500,duration:1 },
  { id:'demo_family', name:'Family Adventure Pass',adult:12500,child:9000,duration:1 },
  { id:'demo_two_day', name:'2-Day Explorer Pass',adult:22000,child:16500,duration:2 },
  { id:'demo_annual', name:'Annual Explorer Pass',adult:39000,child:29000,duration:365 },
];
const rides = ['Sky Coaster','River Rapids','Fantasy Carousel','Jungle Expedition','Cloud Wheel','Adventure Tower'];
let state = 20261118;
function rand() { state ^= (state << 13); state ^= (state >>> 17); state ^= (state << 5); return (state >>> 0) / 4294967296; }
function int(min,max) { return min + Math.floor(rand()*(max-min+1)); }
function choose(xs) { return xs[int(0,xs.length-1)]; }
function pad(n,len=2) { return String(n).padStart(len,'0'); }
function dayCount(month) { return month===11 ? 18 : new Date(Date.UTC(2026,month,0)).getUTCDate(); }
function dateAt(month, day, hour=10) { return new Date(Date.UTC(2026,month-1,day,hour-8,int(0,59))); }
function isoDay(dt) { const k=new Date(dt.getTime()+8*3600*1000);return k.toISOString().slice(0,10); }
function datetimeBefore(a,b) { return a.getTime() <= b.getTime(); }
function monthOf(d) { return d.getUTCMonth()+1; }
function validUntil(dt,duration) { const d=new Date(dt.getTime()+(duration-1)*864e5); return isoDay(d); }
function chooseVisitDate(month,orderDate) {
  const add=int(0,6);let d=new Date(orderDate.getTime()+add*864e5);
  const bound=new Date(Date.UTC(2026,10,18,15,0));
  if(d>bound) d=new Date(orderDate);
  return d;
}
function createDataset() {
  const docs = [];const visitors=[];const orders=[];const tickets=[]; const earnings=new Map();const summary=[];
  function add(collection,id,data){ docs.push({collection,id,data:{...data,isDemo:true,demoBatchId:DATASET,demoTag:TAG}}); }
  let vIndex=0, oIndex=0, pIndex=0, rIndex=0, admitIndex=0, rideIndex=0, voucherIndex=0;
  for(const plan of MONTHS) {
    for(let k=0;k<plan.visitors;k++) {
      const id=`demo2026v_${pad(++vIndex,4)}`;
      const joined=dateAt(plan.month,int(1,dayCount(plan.month)),int(9,20));
      const fullName=`${names1[(vIndex*7)%names1.length]} ${names2[(vIndex*11)%names2.length]}`;
      const v={id,fullName,joined,points:0,earned:0};visitors.push(v);earnings.set(id,[]);
    }
  }
  // Register every visitor with a deterministic date, then sample historical orders after sign-up.
  for(const plan of MONTHS) {
    let monthMinor=0, monthTickets=0;
    for(let k=0;k<plan.orders;k++) {
      const date=dateAt(plan.month,int(1,dayCount(plan.month)),int(9,20));
      const eligible=visitors.filter(v=>datetimeBefore(v.joined,date));
      if(!eligible.length) continue;
      // Favor existing visitors, so the report contains real repeat-buyer examples.
      eligible.sort((a,b)=>a.joined-b.joined);
      const bias=rand()<0.40 ? rand()*rand() : rand();
      const owner=eligible[Math.min(eligible.length-1,Math.floor(bias*eligible.length))];
      const product= rand()<0.62 ? products[0] : rand()<0.45 ? products[1] : rand()<0.72 ? products[2] : products[3];
      const quantity=int(1,4), adults=quantity===1?1:int(1,quantity),children=quantity-adults;
      const totalMinor=adults*product.adult+children*product.child;
      const orderId=`demo2026o_${pad(++oIndex,4)}`;const visit=chooseVisitDate(plan.month,date);const visitDate=isoDay(visit);
      const lineId=`${orderId}_line1`;
      const items=Array.from({length:quantity},(_,j)=>({
        packageId:product.id,packageName:product.name,visitDate,
        validUntil:validUntil(visit,product.duration),durationDays:product.duration,
        ticketType:j<adults?'adult':'child',guestName:j===0?owner.fullName:`Demo Guest ${pad(j+1,2)}`,
        guestEmail:`visitor${pad(vIndex,4)}.${pad(oIndex,4)}@example.com`,
        unitPriceMinor:j<adults?product.adult:product.child,
        quantity:1,
      }));
      const ids=items.map((_,j)=>`${orderId}_${j+1}`);
      add('orders',orderId,{
        version:2,ownerUid:owner.id,requestId:orderId,fingerprint:`demo_only_${orderId}`,
        packageId:product.id,packageName:product.name,visitDate,quantity,ticketIds:ids,items,
        lineItems:[{id:lineId,packageId:product.id,packageName:product.name,visitDate,
          adults,children,adultPriceMinor:product.adult,childPriceMinor:product.child,
          durationDays:product.duration,imageAsset:'',category:'day'}],
        subtotalMinor:totalMinor,pointsUsed:0,discountMinor:0,loyaltyEarnRate:1,totalMinor,
        currency:'MYR',paymentMethod:'demo',paymentStatus:'simulated',status:'completed',
        displayCode:`DEMO-ORDER-${pad(oIndex,5)}`,createdAt:date,
      });
      orders.push({id:orderId,ownerUid:owner.id,date,totalMinor});monthMinor+=totalMinor;monthTickets+=quantity;
      const earned=Math.floor(totalMinor/100);owner.earned+=earned;owner.points+=earned;
      add('loyaltyEvents',`demo2026earn_${pad(oIndex,4)}`,{
        ownerUid:owner.id,kind:'earned',sourceId:orderId,delta:earned,createdAt:date,
      });
      for(let j=0;j<quantity;j++) {
        const t=items[j];const ticketId=ids[j];const attended=rand()<0.72;
        const status=attended?'used':'demo';
        add('tickets',ticketId,{
          ...t,item:t,version:2,index:j,orderId,ownerUid:owner.id,purchaserUid:owner.id,
          displayCode:`DEMO-TICKET-${pad(oIndex,5)}-${pad(j+1)}`,
          currency:'MYR',status,createdAt:date,
          admissionDays:attended?[visit]:[],
        });
        tickets.push(ticketId);
        if(attended) {
          add('admissions',`demo2026ad_${pad(++admitIndex,5)}`,{
            ownerUid:owner.id,ticketId,outcome:'admitted',actorUid:'demo-only',createdAt:visit,
          });
          if(rand()<0.73) {
            const rideName=choose(rides);
            add('rideAdmissions',`demo2026ride_${pad(++rideIndex,5)}`,{
              ownerUid:owner.id,ticketId,attractionId:`demo_attraction_${rides.indexOf(rideName)+1}`,
              attractionName:rideName,actorUid:'demo-only',createdAt:visit,
            });
          }
        }
      }
      if(rand()<0.43) {
        const cancelled=rand()<0.12;
        add('reservations',`demo2026res_${pad(++rIndex,5)}`,{
          ownerUid:owner.id,attractionId:`demo_attraction_${int(1,6)}`,
          attractionName:choose(rides),status:cancelled?'cancelled':'completed',
          visitDate,createdAt:date,
        });
      }
    }
    for(let k=0;k<plan.photos;k++) {
      const date=dateAt(plan.month,int(1,dayCount(plan.month)),int(11,18));
      const eligible=visitors.filter(v=>datetimeBefore(v.joined,date));
      if(!eligible.length)continue;
      const v=choose(eligible),priceMinor=int(1,3)*2000;
      add('photoOrders',`demo2026photo_${pad(++pIndex,4)}`,{
        ownerUid:v.id,status:'confirmed',totalMinor:priceMinor,currency:'MYR',
        paymentMethod:'demo',paymentStatus:'simulated',
        items:[{title:'Theme Park Photo Print',quantity:1,priceMinor}],
        deliveryEmail:`demo-photo-${pad(pIndex,4)}@example.com`,createdAt:date,
        kioskCode:null,
      });
    }
    summary.push({month:`2026-${pad(plan.month)}`,registeredVisitors:plan.visitors,orders:plan.orders,photoOrders:plan.photos,orderValueRM:Number((monthMinor/100).toFixed(2)),tickets:monthTickets});
  }
  // Optional expired demo vouchers; never create redeemable/usable synthetic entitlements.
  for(let i=0;i<65;i++) {
    const owner=choose(visitors),issued=dateAt(int(6,11),int(1,12),14);
    const use=rand()<0.52;
    const usedDate=new Date(issued.getTime()+int(1,4)*864e5);
    add('rewardVouchers',`demo2026voucher_${pad(++voucherIndex,4)}`,{
      ownerUid:owner.id,rewardId:'demo_sample_reward',pointsCost:100,
      reward:{name:'Sample Souvenir Discount',subtitle:'Demo only',category:'shopping',
        benefit:'DEMO - not valid for redemption',terms:['Demonstration record'],instructions:['Not redeemable'],validityDays:7},
      status:use?'used':'expired',issuedAt:issued,expiresAt:new Date(issued.getTime()+7*864e5),
      usedAt:use?usedDate:null,usedBy:use?'demo-only':'',
    });
  }
  // Visitors with no purchases are meaningful: conversion never becomes artificially 100%.
  for(const v of visitors) {
    add('visitors',v.id,{
      uid:v.id,fullName:v.fullName,email:`demo.visitor.${v.id}@example.com`,
      phoneNumber:'',role:'visitor',createdAt:v.joined,loyaltyPoints:v.points,
      faceRecognitionConsent:false,parkInterests:[],foodPreferences:[],
      totalDemoEarnedPoints:v.earned,profilePhotoBase64:'',
    });
    add('visitorAdmin',v.id,{
      membership:'normal',riskLevel:'normal',watchlisted:false,notes:'Synthetic demo visitor; not a real Firebase Auth account',
    });
  }
  // Dates serialized as ISO, converted into Firestore timestamps only at writing stage.
  return {docs,summary,totals:{visitors:visitors.length,orders:orders.length,tickets:tickets.length,
    admissions:admitIndex,rideAdmissions:rideIndex,reservations:rIndex,photoOrders:pIndex,vouchers:voucherIndex,
    loyaltyEvents:orders.length,documents:docs.length}};
}
function flags(args) {
  const result = {apply:false,delete:false,preview:false,project:'',key:''};
  for(let i=0;i<args.length;i++){
    const a=args[i];
    if(a==='--apply')result.apply=true;
    else if(a==='--delete-demo')result.delete=true;
    else if(a==='--preview')result.preview=true;
    else if(a==='--project')result.project=args[++i]||'';
    else if(a==='--key')result.key=args[++i]||'';
    else throw Error(`Unknown argument: ${a}`);
  }
  return result;
}
async function run(){
  const opts=flags(process.argv.slice(2));
  if(opts.apply&&opts.delete)throw Error('Choose one action only.');
  const data=createDataset();
  const out=path.join(__dirname,'DEMO_PREVIEW.json');
  fs.writeFileSync(out,JSON.stringify({dataset:DATASET,source:TAG,summary:data.summary,totals:data.totals},null,2)+'\n');
  console.log('Synthetic FYP data for June-Nov 2026 (not real purchases):');
  console.table(data.summary);console.log(data.totals);
  console.log('Preview saved:',out);
  if(!opts.apply&&!opts.delete){console.log('PREVIEW ONLY. Nothing written. Use --apply or --delete-demo with explicit --project and --key.');return;}
  if(!opts.project || !/^[a-z][a-z0-9-]{5,40}$/.test(opts.project))throw Error('Provide --project YOUR_FIREBASE_PROJECT_ID');
  if(!opts.key || !fs.existsSync(opts.key))throw Error('Provide --key with a locally stored Firebase service-account JSON path (do not share it).');
  const service = JSON.parse(fs.readFileSync(opts.key,'utf8'));
  if(service.project_id!==opts.project)throw Error(`Service-account project mismatch: ${service.project_id} vs ${opts.project}. No writes performed.`);
  const admin=require('firebase-admin');
  const app=admin.initializeApp({credential:admin.credential.cert(service),projectId:opts.project});
  const db=app.firestore();
  try{
    const collections=[...new Set(data.docs.map(x=>x.collection))];
    if(opts.delete){
      console.log('Removing ONLY labelled demo documents from these collections:',collections.join(', '));
      let deleted=0;
      for(const col of collections){
        const result=await db.collection(col).where('demoBatchId','==',DATASET).get();
        for(let i=0;i<result.docs.length;i+=350){
          const batch=db.batch();for(const doc of result.docs.slice(i,i+350)){
            if(doc.data().isDemo!==true || doc.data().demoTag!==TAG)throw Error('Unexpected record: abort deletion.');
            batch.delete(doc.ref);
          }
          await batch.commit();deleted+=Math.min(350,result.docs.length-i);
        }
      }
      console.log(`Removed ${deleted} matching demo records. Real records are untouched.`);return;
    }
    console.log('Checking target IDs before import; existing non-demo records must never be overwritten.');
    for(let i=0;i<data.docs.length;i+=100){
      const chunk=data.docs.slice(i,i+100),snapshots=await db.getAll(...chunk.map(x=>db.collection(x.collection).doc(x.id)));
      for(const snap of snapshots) if(snap.exists && (snap.data().isDemo!==true || snap.data().demoTag!==TAG || snap.data().demoBatchId!==DATASET)) {
        throw Error(`Existing non-demo record would be overwritten: ${snap.ref.path}. Aborted.`);
      }
    }
    const convert=o=>o instanceof Date ? admin.firestore.Timestamp.fromDate(o) :
      Array.isArray(o)?o.map(convert):o && typeof o==='object'?Object.fromEntries(Object.entries(o).map(([k,v])=>[k,convert(v)])):o;
    console.log(`Importing ${data.docs.length} demo records into ${opts.project}...`);
    for(let i=0;i<data.docs.length;i+=300){
      const batch=db.batch();for(const d of data.docs.slice(i,i+300))batch.set(db.collection(d.collection).doc(d.id),convert(d.data));
      await batch.commit();console.log(`Saved ${Math.min(i+300,data.docs.length)}/${data.docs.length}`);
    }
    console.log('IMPORT COMPLETE. IMPORTANT: These are FAKE demo orders; they are NOT real Stripe payments and MUST NOT be reported as genuine sales.');
  }finally{await app.delete();}
}
run().catch(e=>{console.error('ERROR:',e.message);process.exitCode=1;});
