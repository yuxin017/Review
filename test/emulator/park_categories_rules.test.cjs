'use strict';
// Local demo emulator only; never touches your live Firebase project.
const {before, test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const project = process.env.GCLOUD_PROJECT;
const host = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!project?.startsWith('demo-') ||
    !/^(localhost|127\.0\.0\.1):\d+$/.test(host || '') ||
    !/^(localhost|127\.0\.0\.1):\d+$/.test(authHost || '')) {
  throw Error('Use local demo Auth + Firestore emulators only.');
}
const base=`http://${host}/v1/projects/${project}/databases/(default)/documents`;
const authBase=`http://${authHost}/identitytoolkit.googleapis.com/v1`;
const prefix='categories-'+randomUUID();
const str=s=>({stringValue:s});
const bool=b=>({booleanValue:b});
const int=n=>({integerValue:String(n)});
const dbl=n=>({doubleValue:n});
async function req(url,method='GET',body,token){
  const response=await fetch(url,{method,
    headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},
    body:body===undefined?undefined:JSON.stringify(body)});
  let data;try{data=await response.json();}catch{data={};}
  return {status:response.status,data};
}
const doc=(collection,id)=>`projects/${project}/databases/(default)/documents/${collection}/${id}`;
function create(collection,id,fields){
  return {update:{name:doc(collection,id),fields},
    updateTransforms:[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'},
      {fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]};
}
function attraction(id, categoryId, kind='dining'){
  return {update:{name:doc('attractions',id),fields:{
    name:str('Pasta Corner'),kind:str(kind),category:str('Western'),
    categoryId:str(categoryId),status:str('closed'),
    minHeightCm:int(0),mapX:dbl(.5),mapY:dbl(.5),
  }},updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]};
}
async function commit(writes,token){
  return req(base+':commit','POST',{writes},token);
}
let admin, visitor;
before(async()=>{
  const a=await req(authBase+'/accounts:signUp?key=test','POST',{
    email:`${prefix}-admin@example.com`,password:'StrongPassword123!',returnSecureToken:true});
  assert.equal(a.status,200,JSON.stringify(a.data));
  const c=await req(authBase+`/projects/${project}/accounts:update`,'POST',{
    localId:a.data.localId,customAttributes:JSON.stringify({admin:true})},'owner');
  assert.equal(c.status,200,JSON.stringify(c.data));
  const refresh=await fetch(`http://${authHost}/securetoken.googleapis.com/v1/token?key=test`,{
    method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({grant_type:'refresh_token',refresh_token:a.data.refreshToken})});
  assert.equal(refresh.status,200);admin=(await refresh.json()).id_token;
  const v=await req(authBase+'/accounts:signUp?key=test','POST',{
    email:`${prefix}-visitor@example.com`,password:'StrongPassword123!',returnSecureToken:true});
  assert.equal(v.status,200);visitor=v.data.idToken;
});

test('admin creates distinct Food and Attraction categories',async()=>{
  const food=await commit([create('parkCategories',prefix+'-western',{
    kind:str('dining'),name:str('Western'),active:bool(true)})],admin);
  assert.equal(food.status,200,JSON.stringify(food.data));
  const ride=await commit([create('parkCategories',prefix+'-family',{
    kind:str('attractions'),name:str('Family rides'),active:bool(true)})],admin);
  assert.equal(ride.status,200,JSON.stringify(ride.data));
});

test('Food data keeps Food kind even with Western category',async()=>{
  const result=await commit([attraction(prefix+'-food',prefix+'-western')],admin);
  assert.equal(result.status,200,JSON.stringify(result.data));
});

test('cannot assign Food category to a Ride',async()=>{
  const result=await commit([attraction(prefix+'-wrong',prefix+'-western','attractions')],admin);
  assert.equal(result.status,403,JSON.stringify(result.data));
});

test('visitor cannot create categories or attractions',async()=>{
  const category=await commit([create('parkCategories',prefix+'-denied',{
    kind:str('dining'),name:str('Asian'),active:bool(true)})],visitor);
  assert.equal(category.status,403,JSON.stringify(category.data));
  const food=await commit([attraction(prefix+'-visitor-food',prefix+'-western')],visitor);
  assert.equal(food.status,403,JSON.stringify(food.data));
});
