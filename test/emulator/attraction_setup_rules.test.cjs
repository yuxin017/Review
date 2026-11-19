'use strict';
const {test,before} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const project = process.env.GCLOUD_PROJECT;
const host = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!project?.startsWith('demo-') ||
    !/^(127\.0\.0\.1|localhost):\d+$/.test(host || '') ||
    !/^(127\.0\.0\.1|localhost):\d+$/.test(authHost || '')) {
  throw Error('Run with local demo Firebase emulators only.');
}
const root = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
const authRoot = `http://${authHost}/identitytoolkit.googleapis.com/v1`;
const prefix = 'attraction-ux-' + randomUUID();
const str = value => ({stringValue:value});
const int = value => ({integerValue:String(value)});
const dbl = value => ({doubleValue:value});
async function api(url,method='GET',data,token) {
  const r = await fetch(url, {
    method,
    headers:{'Content-Type':'application/json', ...(token ? {Authorization:'Bearer '+token}:{})},
    body:data===undefined?undefined:JSON.stringify(data),
  });
  let json;try{json=await r.json()}catch{json={}}
  return {status:r.status,json};
}
let adminToken;
before(async()=>{
  const u=await api(authRoot+'/accounts:signUp?key=test','POST',{
    email:`${prefix}@example.com`, password:'Example+Password123!',returnSecureToken:true,
  });
  assert.equal(u.status,200,JSON.stringify(u.json));
  const claim=await api(authRoot+`/projects/${project}/accounts:update`,'POST',{
    localId:u.json.localId,customAttributes:JSON.stringify({admin:true}),
  },'owner');
  assert.equal(claim.status,200,JSON.stringify(claim.json));
  const refresh=await fetch(`http://${authHost}/securetoken.googleapis.com/v1/token?key=test`,{
    method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({grant_type:'refresh_token',refresh_token:u.json.refreshToken}),
  });
  assert.equal(refresh.status,200);
  adminToken=(await refresh.json()).id_token;
});
function fields(details={}){
  return {
    name:str('Ferris Wheel'),category:str('Family rides'),status:str('closed'),
    minHeightCm:int(110),mapX:dbl(.4),mapY:dbl(.6),
    ...details,
  };
}
async function create(suffix,extra){
  const id=prefix+'-'+suffix;
  const url=root+':commit';
  const docName=`projects/${project}/databases/(default)/documents/attractions/${id}`;
  return api(url,'POST',{writes:[{update:{name:docName,fields:fields(extra)},
    updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]}]},adminToken);
}
test('real ride setup fields are accepted',async()=>{
  const r=await create('valid',{
    rideDurationMinutes:int(5),ridersPerCycle:int(24),
    safetyNotes:str('Remain seated until stopped.'),
  });
  assert.equal(r.status,200,JSON.stringify(r.json));
});
test('invalid ride capacity is rejected',async()=>{
  const r=await create('capacity',{ridersPerCycle:int(-1)});
  assert.equal(r.status,403,JSON.stringify(r.json));
});
test('legacy attraction shape remains valid',async()=>{
  const r=await create('legacy');
  assert.equal(r.status,200,JSON.stringify(r.json));
});
