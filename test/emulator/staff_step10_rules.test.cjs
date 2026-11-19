'use strict';
// The test is purposely isolated: never run against a live Firebase database.
const assert = require('node:assert/strict');
const {test, before} = require('node:test');
const {randomUUID} = require('node:crypto');
const project = process.env.GCLOUD_PROJECT;
const host = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!project?.startsWith('demo-') ||
    !/^(localhost|127\.0\.0\.1):\d+$/.test(host || '') ||
    !/^(localhost|127\.0\.0\.1):\d+$/.test(authHost || '')) {
  throw new Error('Local demo-* Auth and Firestore Emulators are required.');
}
const root = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
const authRoot = `http://${authHost}/identitytoolkit.googleapis.com/v1`;
const pref = `step10-${randomUUID()}`;
const str = v => ({stringValue:v});
async function api(url, method='GET', body, token) {
  const response = await fetch(url, {method, headers: {
    'Content-Type':'application/json',
    ...(token ? {Authorization:`Bearer ${token}`} : {}),
  }, body:body===undefined ? undefined : JSON.stringify(body)});
  return {status:response.status, data:await response.json()};
}
async function account(email, claims) {
  const a=await api(`${authRoot}/accounts:signUp?key=test`, 'POST',
      {email,password:'S3cure+Pass999!',returnSecureToken:true});
  assert.equal(a.status,200,JSON.stringify(a.data));
  const user=a.data;
  if (claims) {
    const r=await api(`${authRoot}/projects/${project}/accounts:update`, 'POST',
      {localId:user.localId,customAttributes:JSON.stringify(claims)}, 'owner');
    assert.equal(r.status,200,JSON.stringify(r.data));
    user.idToken=await refresh(user.refreshToken);
  }
  return user;
}
async function refresh(refreshToken) {
  const response=await fetch(`http://${authHost}/securetoken.googleapis.com/v1/token?key=test`,{
    method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({grant_type:'refresh_token',refresh_token:refreshToken}),
  });
  const data=await response.json();
  assert.equal(response.status,200,JSON.stringify(data));
  return data.id_token;
}
async function write(collection, id, fields, token) {
  return api(`${root}:commit`,'POST', {writes:[{
    update:{name:`projects/${project}/databases/(default)/documents/${collection}/${id}`,fields},
    updateTransforms:[{
      fieldPath: collection === 'staffEmailVerifications' ? 'verifiedAt' : 'updatedAt',
      setToServerValue:'REQUEST_TIME',
    }],
  }]},token);
}
let admin, employee, visitor, email;
before(async () => {
  email=`staff-${randomUUID()}@example.com`;
  admin=await account(`admin-${randomUUID()}@example.com`,{admin:true});
  employee=await account(email);
  visitor=await account(`visitor-${randomUUID()}@example.com`);
});
const profile=status=>({
  staffId:str('STF-12345678'),fullName:str('Verified Staff'),email:str(email),
  status:str(status),eligibleRoles:{arrayValue:{values:[str('photographer')]}},
});

// Node's test runner keeps each case here ordered because it is a single file
// with no explicit concurrency; statuses are changed only in these tests.
test('unverified account cannot be activated and cannot fake proof',async()=>{
  assert.equal((await write('staffProfiles',employee.localId,profile('inactive'),admin.idToken)).status,200);
  assert.equal((await write('staffProfiles',employee.localId,profile('active'),admin.idToken)).status,403);
  assert.equal((await write('staffEmailVerifications',employee.localId,
    {email:str(email)},employee.idToken)).status,403);
  assert.equal((await write('staffEmailVerifications',employee.localId,
    {email:str(email)},visitor.idToken)).status,403);
});

test('verified Auth token can register proof; only then can Admin activate',async()=>{
  const update=await api(`${authRoot}/projects/${project}/accounts:update`, 'POST',
      {localId:employee.localId,emailVerified:true}, 'owner');
  assert.equal(update.status,200,JSON.stringify(update.data));
  employee.idToken=await refresh(employee.refreshToken);
  const proof=await write('staffEmailVerifications',employee.localId,
    {email:str(email)},employee.idToken);
  assert.equal(proof.status,200,JSON.stringify(proof.data));
  assert.equal((await write('staffProfiles',employee.localId,profile('active'),admin.idToken)).status,200);
  assert.equal((await write('staffProfiles',employee.localId,profile('inactive'),employee.idToken)).status,403);
});

test('course catalogue is admin-only, staff cannot forge courses',async()=>{
  const courseId=`${pref}-course`;
  const course={title:str('Photography Privacy and Safety'),
    roleCode:str('photographer'),active:{booleanValue:true}};
  assert.equal((await write('staffTrainingCourses',courseId,course,visitor.idToken)).status,403);
  assert.equal((await write('staffTrainingCourses',courseId,course,admin.idToken)).status,200);
  assert.equal((await api(`${root}/staffTrainingCourses/${courseId}`,'GET',undefined,employee.idToken)).status,403);
  const training={staffUid:str(employee.localId),roleCode:str('photographer'),
    title:str('Photography Privacy and Safety'),status:str('approved'),
    attractionId:str(''),courseId:str(courseId),
    completedAt:{timestampValue:'2026-11-01T00:00:00Z'},expiresAt:{nullValue:'NULL_VALUE'}};
  const recordId=`${pref}-record`;
  assert.equal((await write('staffQualifications',recordId,training,employee.idToken)).status,403);
  assert.equal((await write('staffQualifications',recordId,training,admin.idToken)).status,200);
});
