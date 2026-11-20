'use strict';
const crypto=require('node:crypto'),{HttpsError}=require('firebase-functions/v2/https'),{promotionPrice,recordPromotion}=require('./promotion_pricing');
const fail=(code,message)=>{throw new HttpsError(code,message);},validId=v=>typeof v==='string'&&/^[\w-]{1,100}$/.test(v),day=d=>new Date(d.getTime()+8*3600000).toISOString().slice(0,10),reference=(id,date)=>'TP-'+date.replaceAll('-','').slice(2)+'-'+id.slice(0,8).toUpperCase();
function createTicketPromotionHandlers({db,FieldValue,exchangeRates,clock=()=>new Date()}){
  const currency=d=>d.paymentCurrency??'MYR';
  const basket=(d,total)=>crypto.createHash('sha256').update(JSON.stringify({lines:d.lines,guests:d.guests,pointsUsed:d.pointsUsed??0,promoCode:d.promoCode??'',total,paymentCurrency:currency(d)})).digest('hex');
  function input(request){const d=request.data;if(!request.auth?.uid||request.auth.token?.email_verified!==true)fail('unauthenticated','Sign in with a verified account.');if(!d||!/^[a-f0-9]{48}$/.test(d.requestId)||!Array.isArray(d.lines)||!d.lines.length||d.lines.length>5||!Array.isArray(d.guests)||d.guests.length<1||d.guests.length>10||!Number.isInteger(d.pointsUsed??0)||(d.pointsUsed??0)<0||(d.pointsUsed??0)%100!==0)fail('invalid-argument','Review your selected passes and guest details.');return d;}
  async function price(tx,request){
    const d=input(request),uid=request.auth.uid,[profile,access,security,loyalty]=await tx.getAll(db.doc('visitors/'+uid),db.doc('visitorAccess/'+uid),db.doc('accountSecurity/'+uid),db.doc('parkSettings/loyalty'));
    if(!profile.exists)fail('failed-precondition','Complete your visitor profile first.');if(access.exists&&access.data().status!=='active')fail('permission-denied','This account is restricted. Please contact support.');if(security.data()?.closing||security.data()?.revokedBefore>=(request.auth.token.auth_time??0))fail('unauthenticated','Your session has ended.');
    const items=[],lineIds=new Set(),guests=new Set(),selfDates=new Set();let subtotal=0;
    const buyerEmail=String(request.auth.token.email??'').trim().toLowerCase();
    for(const line of d.lines){
      if(!validId(line.id)||lineIds.has(line.id)||!validId(line.packageId)||typeof line.visitDate!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(line.visitDate)||!Number.isInteger(line.adults)||!Number.isInteger(line.children)||line.adults<0||line.children<0||line.adults+line.children<1||line.adults+line.children>10)fail('invalid-argument','Review the pass quantities and visit date.');lineIds.add(line.id);
      const visit=new Date(line.visitDate+'T00:00:00Z'),today=day(clock());if(!Number.isFinite(visit.getTime())||visit.toISOString().slice(0,10)!==line.visitDate||line.visitDate<today||visit>new Date(today+'T00:00:00Z').getTime()+365*86400000)fail('invalid-argument','Choose a valid visit date within the next year.');
      const saved=await tx.get(db.doc('ticketPackages/'+line.packageId)),p=saved.data(),duration=p?.durationDays??1;
      if(!p||p.active!==true||p.currency!=='MYR'||!Number.isInteger(p.priceMinor)||p.priceMinor<1||p.priceMinor>10000000||!Number.isInteger(p.childPriceMinor??p.priceMinor)||!Number.isInteger(duration)||duration<1||duration>366||line.packageName!==p.name||line.adultPriceMinor!==p.priceMinor||line.childPriceMinor!==(p.childPriceMinor??p.priceMinor)||line.durationDays!==duration)fail('failed-precondition','A selected pass or price has changed. Review the cart again.');
      const rows=d.guests.filter(g=>g.lineId===line.id);if(rows.length!==line.adults+line.children||rows.filter(g=>g.type==='adult').length!==line.adults||rows.filter(g=>g.type==='child').length!==line.children)fail('invalid-argument','Add each guest to the correct pass.');
      for(const guest of rows){if(!validId(guest.id)||guests.has(guest.id)||typeof guest.fullName!=='string'||guest.fullName.trim().length<2||guest.fullName.length>100||typeof guest.email!=='string'||guest.email.length>254||!/^\S+@\S+\.\S+$/.test(guest.email))fail('invalid-argument','Complete each guest’s name and email.');guests.add(guest.id);
        const guestEmail=guest.email.trim().toLowerCase();
        const self=buyerEmail!==''&&guestEmail===buyerEmail;
        if(guest.assignedToMe===true&&!self)fail('invalid-argument','Assign this ticket using your account email.');
        if(self){
          if(selfDates.has(line.visitDate))fail('invalid-argument','You can assign yourself one ticket per visit date.');
          selfDates.add(line.visitDate);
        }
        const amount=guest.type==='child'?(p.childPriceMinor??p.priceMinor):p.priceMinor;subtotal+=amount;items.push({packageId:saved.id,packageName:p.name,visitDate:line.visitDate,validUntil:new Date(visit.getTime()+(duration-1)*86400000).toISOString().slice(0,10),durationDays:duration,ticketType:guest.type,guestName:guest.fullName.trim(),guestEmail,unitPriceMinor:amount});}
    }
    if(items.length!==d.guests.length||items.length>10)fail('invalid-argument','Review your guest list.');
    const promotion=await promotionPrice({db,tx,code:d.promoCode??'',scope:'tickets',subtotal,uid,now:clock()}),balance=profile.data().loyaltyPoints??0,maxPoints=promotion.offer?.allowPoints===false?0:Math.floor(Math.min(balance,subtotal-promotion.discountMinor)/100)*100,used=d.pointsUsed??0,rate=loyalty.data()?.purchasePointsPerRinggit??1;
    if(!Number.isInteger(balance)||balance<0||used>maxPoints)fail('failed-precondition','Review your points. This promotion may not allow points, or your balance has changed.');if(!Number.isInteger(rate)||rate<0||rate>100)fail('failed-precondition','Points earning rules need an administrator review.');
    return{items,subtotalMinor:subtotal,discountMinor:promotion.discountMinor,pointsUsed:used,totalMinor:subtotal-promotion.discountMinor-used,maxPoints,allowPoints:promotion.offer?.allowPoints!==false,profile,balance,rate,promotion};
  }
  const fields=v=>({subtotalMinor:v.subtotalMinor,discountMinor:v.discountMinor,pointsUsed:v.pointsUsed,totalMinor:v.totalMinor,maxPoints:v.maxPoints,allowPoints:v.allowPoints,currency:'MYR'});
  async function quote(request){
    const d=input(request),code=currency(d);if(!['MYR','USD','SGD','CNY','EUR'].includes(code))fail('invalid-argument','Choose a supported payment currency.');
    const rates=code==='MYR'?null:exchangeRates?await exchangeRates(request):fail('unavailable','Currency conversion is temporarily unavailable.');
    const rate=code==='MYR'?1:rates.rates[code];if(!Number.isFinite(rate)||rate<=0)fail('unavailable','Currency conversion is temporarily unavailable.');
    return db.runTransaction(async tx=>{
      const value=await price(tx,request),paymentTotalMinor=Math.round(value.totalMinor*rate);
      if(code==='MYR')return{...fields(value),paymentCurrency:code,paymentTotalMinor,exchangeRate:1};
      const ref=db.collection('ticketCurrencyQuotes').doc(),expiresAt=new Date(clock().getTime()+15*60000);
      tx.create(ref,{ownerUid:request.auth.uid,basket:basket(d,value.totalMinor),paymentCurrency:code,paymentTotalMinor,exchangeRate:rate,exchangeRateDate:rates.asOf,expiresAt});
      return{...fields(value),paymentCurrency:code,paymentTotalMinor,exchangeRate:rate,exchangeRateDate:rates.asOf,currencyQuoteId:ref.id,quoteExpiresAt:expiresAt.toISOString()};
    });
  }
  async function checkout(request){
    const d=input(request),uid=request.auth.uid;if(!['card','fpx','touch-go','apple-pay','nfc'].includes(d.paymentMethod)||typeof d.clientFingerprint!=='string'||!/^[a-f0-9]{64}$/.test(d.clientFingerprint)||!/^$|^\d{4}$/.test(d.cardLast4??''))fail('invalid-argument','Review the payment option.');
    const code=currency(d);if(!['MYR','USD','SGD','CNY','EUR'].includes(code))fail('invalid-argument','Choose a supported payment currency.');
    const ref=db.doc('orders/'+d.requestId),fingerprint=crypto.createHash('sha256').update(JSON.stringify({lines:d.lines,guests:d.guests,pointsUsed:d.pointsUsed??0,promoCode:d.promoCode??'',expectedTotalMinor:d.expectedTotalMinor,paymentMethod:d.paymentMethod,cardLast4:d.cardLast4??'',...(code!=='MYR'?{paymentCurrency:code,currencyQuoteId:d.currencyQuoteId,paymentTotalMinor:d.paymentTotalMinor}:{})})).digest('hex');
    return db.runTransaction(async tx=>{const previous=await tx.get(ref);if(previous.exists){if(previous.data().ownerUid!==uid||previous.data().serverFingerprint!==fingerprint)fail('already-exists','This checkout reference belongs to another order.');return{orderId:ref.id};}
      const value=await price(tx,request);if(value.totalMinor!==d.expectedTotalMinor)fail('failed-precondition','The promotion or prices changed. Apply the promotion again before confirming.');
      let conversion={paymentCurrency:'MYR',paymentTotalMinor:value.totalMinor,exchangeRate:1};
      if(code!=='MYR'){
        if(!validId(d.currencyQuoteId))fail('invalid-argument','Review the currency quote before confirming.');
        const quote=(await tx.get(db.doc('ticketCurrencyQuotes/'+d.currencyQuoteId))).data();
        if(!quote||quote.ownerUid!==uid||quote.paymentCurrency!==code||quote.basket!==basket(d,value.totalMinor)||quote.expiresAt.toDate()<=clock()||quote.paymentTotalMinor!==d.paymentTotalMinor)fail('failed-precondition','Your currency quote has expired or the booking changed. Review the total again before confirming.');
        conversion={paymentCurrency:code,paymentTotalMinor:quote.paymentTotalMinor,exchangeRate:quote.exchangeRate,exchangeRateDate:quote.exchangeRateDate};
      }
      const ticketIds=value.items.map((_,i)=>d.requestId+'_'+(i+1)),visitDate=d.lines[0].visitDate;
      const safeLines=d.lines.map(l=>({id:l.id,packageId:l.packageId,packageName:l.packageName,visitDate:l.visitDate,adults:l.adults,children:l.children,adultPriceMinor:l.adultPriceMinor,childPriceMinor:l.childPriceMinor,durationDays:l.durationDays,category:l.category==='annual'?'annual':'day',imageAsset:l.category==='annual'?'assets/images/ticketing/annual-pass.png':'assets/images/ticketing/castle.png'}));
      tx.create(ref,{...conversion,version:2,ownerUid:uid,requestId:ref.id,fingerprint:d.clientFingerprint,serverFingerprint:fingerprint,packageId:d.lines[0].packageId,packageName:d.lines.length===1?d.lines[0].packageName:'Theme Park Tickets',visitDate,quantity:value.items.length,ticketIds,items:value.items,lineItems:safeLines,subtotalMinor:value.subtotalMinor,discountMinor:value.discountMinor,pointsUsed:value.pointsUsed,totalMinor:value.totalMinor,loyaltyEarnRate:value.rate,promoCode:d.promoCode??'',paymentMethod:d.paymentMethod,cardLast4:d.paymentMethod==='card'?(d.cardLast4??''):'',currency:'MYR',status:'completed',displayCode:reference(ref.id,visitDate),createdAt:FieldValue.serverTimestamp()});
      for(let i=0;i<value.items.length;i++){const item=value.items[i],displayCode=reference(ref.id,item.visitDate)+'-'+String(i+1).padStart(2,'0');tx.create(db.doc('tickets/'+ticketIds[i]),{...item,item,version:2,index:i,ownerUid:uid,purchaserUid:uid,orderId:ref.id,displayCode,currency:'MYR',status:'valid',createdAt:FieldValue.serverTimestamp()});tx.create(db.doc('ticketReferences/'+displayCode),{ticketId:ticketIds[i],ownerUid:uid,guestEmail:item.guestEmail});}
      if(value.pointsUsed)tx.update(value.profile.ref,{loyaltyPoints:value.balance-value.pointsUsed,lastRedemptionOrderId:ref.id});recordPromotion(tx,value.promotion,uid,ref.id,FieldValue);return{orderId:ref.id};
    });
  }

  // Secure Stripe ticket checkout: price and guest lists are validated on the server.
  async function reserveStripe(request){
    const d=input(request),uid=request.auth.uid,ref=db.doc('ticketPayments/'+d.requestId);
    if(typeof d.clientFingerprint!=='string'||!/^[a-f0-9]{64}$/.test(d.clientFingerprint)||d.paymentCurrency&&d.paymentCurrency!=='MYR')fail('invalid-argument','Review your ticket order in MYR.');
    if(!Number.isInteger(d.expectedTotalMinor))fail('invalid-argument','Review the total before paying.');
    return db.runTransaction(async tx=>{
      const previous=await tx.get(ref);
      if(previous.exists){
        const saved=previous.data();
        if(saved.ownerUid!==uid||saved.fingerprint!==d.clientFingerprint)fail('already-exists','This checkout belongs to a different booking.');
        return{orderId:ref.id,amountMinor:saved.amountMinor,status:saved.status,sessionId:saved.sessionId??'',url:saved.url??''};
      }
      const v=await price(tx,request);
      if(v.totalMinor!==d.expectedTotalMinor)fail('failed-precondition','The ticket price or promotion changed. Please review the total.');
      // Current Stripe MYR settlement minimum is RM 2.00.
      if(v.totalMinor<200)fail('failed-precondition','Online payment requires at least RM 2.00 after discounts.');
      if(v.totalMinor>99999999)fail('failed-precondition','The payment exceeds the online payment limit.');
      const lines=d.lines.map(l=>({id:l.id,packageId:l.packageId,packageName:l.packageName,visitDate:l.visitDate,adults:l.adults,children:l.children,adultPriceMinor:l.adultPriceMinor,childPriceMinor:l.childPriceMinor,durationDays:l.durationDays,category:l.category==='annual'?'annual':'day',imageAsset:l.category==='annual'?'assets/images/ticketing/annual-pass.png':'assets/images/ticketing/castle.png'}));
      tx.create(ref,{
        ownerUid:uid,fingerprint:d.clientFingerprint,amountMinor:v.totalMinor,currency:'MYR',
        status:'pending',sessionId:'',url:'',packageId:d.lines[0].packageId,
        packageName:d.lines.length===1?d.lines[0].packageName:'Theme Park Tickets',
        visitDate:d.lines[0].visitDate,quantity:v.items.length,items:v.items,lineItems:lines,
        subtotalMinor:v.subtotalMinor,discountMinor:v.discountMinor,pointsUsed:v.pointsUsed,
        promoCode:d.promoCode??'',loyaltyEarnRate:v.rate,
        createdAt:FieldValue.serverTimestamp(),
      });
      return{orderId:ref.id,amountMinor:v.totalMinor,status:'pending',sessionId:'',url:''};
    });
  }
  async function completeStripe(session){
    if(!session||session.payment_status!=='paid'||session.currency!=='myr'||!Number.isInteger(session.amount_total))return'pending';
    const id=session.client_reference_id;
    if(typeof id!=='string'||!/^[a-f0-9]{48}$/.test(id))throw new Error('Invalid ticket payment reference');
    const paymentRef=db.doc('ticketPayments/'+id),orderRef=db.doc('orders/'+id);
    return db.runTransaction(async tx=>{
      const [attempt,existing]=await tx.getAll(paymentRef,orderRef);
      if(!attempt.exists)throw new Error('Ticket payment record missing');
      const d=attempt.data();
      if(existing.exists){
        if(existing.data().paymentProvider!=='stripe'||existing.data().stripeSessionId!==session.id)throw new Error('Order reference conflict');
        if(d.status!=='paid')tx.update(paymentRef,{status:'paid',paidAt:FieldValue.serverTimestamp()});
        return'paid';
      }
      if(d.ownerUid!==session.metadata?.uid||d.amountMinor!==session.amount_total||d.currency!=='MYR'||(d.sessionId&&d.sessionId!==session.id))throw new Error('Payment verification mismatch');
      const profileRef=db.doc('visitors/'+d.ownerUid),profile=await tx.get(profileRef);
      if(!profile.exists)throw new Error('Visitor profile missing after payment');
      const balance=profile.data().loyaltyPoints??0;
      if(d.pointsUsed>balance){
        tx.update(paymentRef,{status:'manual_review',reason:'loyalty_balance_changed',sessionId:session.id,paidAt:FieldValue.serverTimestamp()});
        return'manual_review';
      }
      let promo=null;
      if(d.promoCode){
        const code=d.promoCode,ref=db.doc('campaigns/'+code),usageRef=db.doc('campaignRedemptions/'+crypto.createHash('sha256').update(d.ownerUid+'\0'+code).digest('hex'));
        const [offer,usage]=await tx.getAll(ref,usageRef);
        if(offer.exists){promo={ref,usageRef,offer:offer.data(),usage:usage.data()?.count??0};}
        else{
          tx.update(paymentRef,{status:'manual_review',reason:'promotion_unavailable',sessionId:session.id,paidAt:FieldValue.serverTimestamp()});
          return'manual_review';
        }
      }
      const ticketIds=d.items.map((_,i)=>id+'_'+(i+1));
      tx.create(orderRef,{
        version:2,ownerUid:d.ownerUid,requestId:id,fingerprint:d.fingerprint,
        packageId:d.packageId,packageName:d.packageName,visitDate:d.visitDate,
        quantity:d.quantity,ticketIds,items:d.items,lineItems:d.lineItems,
        subtotalMinor:d.subtotalMinor,discountMinor:d.discountMinor,pointsUsed:d.pointsUsed,
        totalMinor:d.amountMinor,loyaltyEarnRate:d.loyaltyEarnRate,promoCode:d.promoCode,
        paymentMethod:'stripe',paymentProvider:'stripe',paymentStatus:'paid',
        stripeSessionId:session.id,currency:'MYR',status:'completed',
        displayCode:reference(id,d.visitDate),createdAt:FieldValue.serverTimestamp(),
      });
      for(let i=0;i<d.items.length;i++){
        const item=d.items[i],code=reference(id,item.visitDate)+'-'+String(i+1).padStart(2,'0');
        tx.create(db.doc('tickets/'+ticketIds[i]),{...item,item,version:2,index:i,ownerUid:d.ownerUid,purchaserUid:d.ownerUid,orderId:id,displayCode:code,currency:'MYR',status:'valid',createdAt:FieldValue.serverTimestamp()});
        tx.create(db.doc('ticketReferences/'+code),{ticketId:ticketIds[i],ownerUid:d.ownerUid,guestEmail:item.guestEmail});
      }
      if(d.pointsUsed)tx.update(profileRef,{loyaltyPoints:balance-d.pointsUsed,lastRedemptionOrderId:id});
      if(promo){
        // Honour the server-approved discount at payment time; record it once.
        tx.update(promo.ref,{usageCount:(promo.offer.usageCount??0)+1,updatedAt:FieldValue.serverTimestamp()});
        tx.set(promo.usageRef,{ownerUid:d.ownerUid,campaignId:promo.ref.id,count:promo.usage+1,lastSourceId:id,updatedAt:FieldValue.serverTimestamp()});
      }
      tx.update(paymentRef,{status:'paid',sessionId:session.id,paidAt:FieldValue.serverTimestamp()});
      return'paid';
    });
  }
  return{quote,checkout,reserveStripe,completeStripe};
}
module.exports={createTicketPromotionHandlers};
