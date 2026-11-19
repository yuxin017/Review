'use strict';
// Runs ONLY on local Auth + Firestore emulators with demo project IDs.
const {test,before} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const project = process.env.GCLOUD_PROJECT;
const host = process.env.FIRESTORE_EMULATOR_HOST;
const auth = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if(!project?.startsWith('demo-') || !/^(127\.0\.0\.1|localhost):\d+$/.test(host || '') ||
    !/^(127\.0\.0\.1|localhost):\d+$/.test(auth || '')) {
  throw Error('Use only local demo Auth and Firestore emulators.');
}
const root = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
const aroot = `http://${auth}/identitytoolkit.googleapis.com/v1`;
const prefix = `step13-${randomUUID()}`;
const str = x => ({stringValue: x});
const bool = x => ({booleanValue: x});
const number = x => ({doubleValue: x});
const int = x => ({integerValue: String(x)});
const url = (c,id) => `${root}/${c}/${id}`;
const name = (c,id) => `projects/${project}/databases/(default)/documents/${c}/${id}`;
async function request(endpoint,method='GET',body,token){
  const response = await fetch(endpoint,{method,
    headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},
    body:body===undefined?undefined:JSON.stringify(body)});
  let data;
  try {data=await response.json()}catch {data={}};
  return {status:response.status,data};
}
const ride = {
  name:str('Ferris Wheel'),category:str('Family rides'),status:str('closed'),
  minHeightCm:int(0),mapX:number(0.3),mapY:number(0.4),
};
const course = rideId => ({
  title:str('Ferris Wheel Operation & Safety Training'),
  roleCode:str('attraction_operator'),attractionId:str(rideId),active:bool(true),
});
const write = (collection,id,fields) => ({
  update:{name:name(collection,id),fields},
  updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}],
});
const commit = (writes,token) => request(root+':commit','POST',{writes},token);
let admin,visitor;
before(async()=>{
  const a = await request(aroot+'/accounts:signUp?key=test','POST',{
    email:`${prefix}-root@example.com`,password:'Strong+Pass98!',returnSecureToken:true});
  assert.equal(a.status,200,JSON.stringify(a.data));
  assert.equal((await request(
      aroot+`/projects/${project}/accounts:update`,'POST',{
        localId:a.data.localId,customAttributes:JSON.stringify({admin:true})},'owner'
  )).status,200);
  const r = await fetch(`http://${auth}/securetoken.googleapis.com/v1/token?key=test`,{
    method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({grant_type:'refresh_token',refresh_token:a.data.refreshToken})});
  assert.equal(r.status,200);admin=(await r.json()).id_token;
  const v=await request(aroot+'/accounts:signUp?key=test','POST',{
    email:`${prefix}-guest@example.com`,password:'Strong+Pass98!',returnSecureToken:true});
  assert.equal(v.status,200);visitor=v.data.idToken;
});

test('admin can create ride and required course together',async()=>{
  const id=prefix+'-ride';
  const result=await commit([write('attractions',id,ride),
    write('staffTrainingCourses','ride_'+id,course(id))],admin);
  assert.equal(result.status,200,JSON.stringify(result.data));
  const stored=await request(url('staffTrainingCourses','ride_'+id),'GET',undefined,admin);
  assert.equal(stored.status,200);
  assert.equal(stored.data.fields.attractionId.stringValue,id);
});

test('invalid course means attraction is not created',async()=>{
  const id=prefix+'-rollback';
  const result=await commit([write('attractions',id,ride),
    write('staffTrainingCourses','ride_'+id,{
      ...course(id),attractionId:str(prefix+'-wrong'),
    })],admin);
  assert.equal(result.status,403,JSON.stringify(result.data));
  const stored=await request(url('attractions',id),'GET',undefined,admin);
  assert.equal(stored.status,404,JSON.stringify(stored.data));
});

test('visitor cannot create attraction and course',async()=>{
  const id=prefix+'-visitor';
  const result=await commit([write('attractions',id,ride),
    write('staffTrainingCourses','ride_'+id,course(id))],visitor);
  assert.equal(result.status,403,JSON.stringify(result.data));
});

test('course without any attraction is rejected',async()=>{
  const id=prefix+'-absent';
  const result=await commit([write('staffTrainingCourses','ride_'+id,course(id))],admin);
  assert.equal(result.status,403,JSON.stringify(result.data));
});
