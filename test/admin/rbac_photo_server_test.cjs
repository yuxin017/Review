const test=require('node:test');
const assert=require('node:assert/strict');
const Module=require('node:module');
const load=Module._load;
Module._load=function(name,parent,main){if(name==='firebase-functions/v2/https')return{HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}};return load.call(this,name,parent,main);};
const {requirePhotoStaff}=require('../../functions/src/staff_photo_access');
const NOW=new Date('2026-11-18T00:00:00Z');
const role='photographer';
function request(admin=false){return {auth:{uid:'s1',token:{email_verified:true,email:'staff@park.test',admin}}};}
function mock(profile={status:'active',email:'staff@park.test',eligibleRoles:['photographer']}, training=[{
  completedAt:{toDate:()=>new Date('2026-11-01T00:00:00Z')},expiresAt:null,
}]){
 return {doc:()=>({get:async()=>({data:()=>profile})}),collection:()=>({
  where(){return this;},limit(){return this;},get:async()=>({docs:training.map(v=>({data:()=>v}))})
 })};
}
const call=(db,r=request())=>requirePhotoStaff({db,request:r,role,clock:()=>NOW});
test('active verified qualified photographer allowed',async()=>assert.equal(await call(mock()),'s1'));
test('super admin allowed with admin claim',async()=>assert.equal(await call(mock(null,[]),request(true)),'s1'));
test('unverified email rejected',async()=>assert.rejects(()=>call(mock(),{auth:{uid:'s1',token:{email_verified:false}}}),/verified account/));
test('suspended staff denied',async()=>assert.rejects(()=>call(mock({status:'suspended',email:'staff@park.test',eligibleRoles:['photographer']})),/not approved/));
test('role not assigned denied',async()=>assert.rejects(()=>call(mock({status:'active',email:'staff@park.test',eligibleRoles:['admission_staff']})),/not approved/));
test('missing training denied',async()=>assert.rejects(()=>call(mock(undefined,[])),/training/));
test('expired training denied',async()=>assert.rejects(()=>call(mock(undefined,[{completedAt:{toDate:()=>new Date('2026-10-01')},expiresAt:{toDate:()=>new Date('2026-11-01')}}])),/training/));
