'use strict';
// Auth + Firestore emulators only; never execute against a live project.
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const project=process.env.GCLOUD_PROJECT;
const fh=process.env.FIRESTORE_EMULATOR_HOST;
const ah=process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!project?.startsWith('demo-') ||
    !/^(127\.0\.0\.1|localhost):\d+$/.test(fh || '') ||
    !/^(127\.0\.0\.1|localhost):\d+$/.test(ah || '')) {
  throw Error('Staff batch tests must use isolated local emulators.');
}
const docs=`http://${fh}/v1/projects/${project}/databases/(default)/documents`;
const auth=`http://${ah}/identitytoolkit.googleapis.com/v1`;
const id=`batch-${randomUUID()}`;
const str=x=>({stringValue:x});
const timestamp=x=>({timestampValue:x});
const name=(collection,key)=>`projects/${project}/databases/(default)/documents/${collection}/${key}`;
let admin,staffUid;
async function request(url,method='GET',body,token) {
  const res=await fetch(url,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:body===undefined?undefined:JSON.stringify(body)});
  return {status:res.status,data:await res.json()};
}
async function tokenForAdmin(){
  const user=await request(`${auth}/accounts:signUp?key=test`,'POST',{
    email:`${id}-admin@example.com`,password:'S3cure+Pass999!',returnSecureToken:true,
  });
  assert.equal(user.status,200,JSON.stringify(user.data));
  const claims=await request(`${auth}/projects/${project}/accounts:update`,'POST',{
    localId:user.data.localId,customAttributes:JSON.stringify({admin:true})},'owner');
  assert.equal(claims.status,200,JSON.stringify(claims.data));
  const res=await fetch(`http://${ah}/securetoken.googleapis.com/v1/token?key=test`,{
    method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({grant_type:'refresh_token',refresh_token:user.data.refreshToken}),
  });
  const data=await res.json();assert.equal(res.status,200,JSON.stringify(data));
  return data.id_token;
}
function write(collection,key,fields){
  return {update:{name:name(collection,key),fields},
    updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]};
}
async function commit(writes,token){return request(`${docs}:commit`,'POST',{writes},token);}
const training=(courseId,title,roleCode)=>({
  staffUid:str(staffUid),courseId:str(courseId),title:str(title),roleCode:str(roleCode),
  status:str('approved'),attractionId:str(''),
  completedAt:timestamp('2026-11-01T00:00:00Z'),expiresAt:{nullValue:'NULL_VALUE'},
});
before(async()=>{
  admin=await tokenForAdmin();
  const user=await request(`${auth}/accounts:signUp?key=test`,'POST',{
    email:`${id}-staff@example.com`,password:'S3cure+Pass999!',returnSecureToken:true,
  });
  assert.equal(user.status,200,JSON.stringify(user.data));
  staffUid=user.data.localId;
  const profile={staffId:str('STF-23456789'),fullName:str('Batch Training Staff'),
    email:str(`${id}-staff@example.com`),status:str('inactive'),
    eligibleRoles:{arrayValue:{values:[str('photographer'),str('admission_staff')]}}};
  const setup=await commit([
    write('staffProfiles',staffUid,profile),
    write('staffTrainingCourses',`${id}-photo`,{title:str('Photography Workflow Training'),roleCode:str('photographer'),active:{booleanValue:true}}),
    write('staffTrainingCourses',`${id}-admission`,{title:str('Admission Scanner Training'),roleCode:str('admission_staff'),active:{booleanValue:true}}),
  ],admin);
  assert.equal(setup.status,200,JSON.stringify(setup.data));
});
after(async()=>{
  if (!staffUid) return;
  for (const [col,key] of [
    ['staffQualifications',`${id}-one`],['staffQualifications',`${id}-two`],
    ['staffQualifications',`${id}-invalid-good`],['staffQualifications',`${id}-invalid-bad`],
    ['staffTrainingCourses',`${id}-photo`],['staffTrainingCourses',`${id}-admission`],
    ['staffProfiles',staffUid],
  ]) {await request(`${docs}/${col}/${key}`,'DELETE',undefined,'owner');}
});
test('two valid course records save together',async()=>{
  const res=await commit([
    write('staffQualifications',`${id}-one`,training(`${id}-photo`,'Photography Workflow Training','photographer')),
    write('staffQualifications',`${id}-two`,training(`${id}-admission`,'Admission Scanner Training','admission_staff')),
  ],admin);
  assert.equal(res.status,200,JSON.stringify(res.data));
  for(const key of [`${id}-one`,`${id}-two`]) {
    assert.equal((await request(`${docs}/staffQualifications/${key}`,'GET',undefined,admin)).status,200);
  }
});
test('invalid course rolls back the entire batch',async()=>{
  const res=await commit([
    write('staffQualifications',`${id}-invalid-good`,training(`${id}-photo`,'Photography Workflow Training','photographer')),
    write('staffQualifications',`${id}-invalid-bad`,training(`${id}-admission`,'Wrong Course Title','admission_staff')),
  ],admin);
  assert.equal(res.status,403,JSON.stringify(res.data));
  assert.equal((await request(`${docs}/staffQualifications/${id}-invalid-good`,'GET',undefined,admin)).status,404);
  assert.equal((await request(`${docs}/staffQualifications/${id}-invalid-bad`,'GET',undefined,admin)).status,404);
});
