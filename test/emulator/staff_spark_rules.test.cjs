'use strict';
// This test intentionally REFUSES to access a real Firebase project.
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const project = process.env.GCLOUD_PROJECT;
const firestore = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!project?.startsWith('demo-') ||
    !/^(127\.0\.0\.1|localhost):\d+$/.test(firestore || '') ||
    !/^(127\.0\.0\.1|localhost):\d+$/.test(authHost || '')) {
  throw Error('Spark Staff Security test must use local Auth/Firestore emulators and a demo-* project.');
}
const root = `http://${firestore}/v1/projects/${project}/databases/(default)/documents`;
const auth = `http://${authHost}/identitytoolkit.googleapis.com/v1`;
const key = `spark-${randomUUID()}`;
const text = value => ({stringValue:value});
const roleList = roles => ({arrayValue:{values:roles.map(text)}});
async function request(url, method='GET', body, token) {
  const response = await fetch(url, {
    method,
    headers:{'Content-Type':'application/json', ...(token ? {Authorization:`Bearer ${token}`} : {})},
    body:body === undefined ? undefined : JSON.stringify(body),
  });
  return {status:response.status, body:response.status===204 ? null : await response.json()};
}
async function account(claims) {
  const r = await request(`${auth}/accounts:signUp?key=demo`, 'POST', {returnSecureToken:true});
  assert.equal(r.status,200,JSON.stringify(r.body));
  const a = r.body;
  if (!claims) return a;
  const change = await request(`${auth}/projects/${project}/accounts:update`,'POST',{
    localId:a.localId,customAttributes:JSON.stringify(claims),
  },'owner');
  assert.equal(change.status,200,JSON.stringify(change.body));
  const token = await fetch(`http://${authHost}/securetoken.googleapis.com/v1/token?key=demo`,{
    method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({grant_type:'refresh_token',refresh_token:a.refreshToken}),
  });
  const data = await token.json();
  assert.equal(token.status,200,JSON.stringify(data));
  a.idToken = data.id_token;
  return a;
}
function staffProfile(changes={}) {
  return {staffId:text('STF-12345678'),fullName:text('Park Photographer'),
    email:text('photographer@example.com'),status:text('inactive'),
    eligibleRoles:roleList(['photographer']),...changes};
}
const documentName = uid => `projects/${project}/databases/(default)/documents/staffProfiles/${uid}`;
async function save(uid,fields,token) {
  return request(`${root}:commit`,'POST',{writes:[{
    update:{name:documentName(uid),fields},
    updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}],
  }]},token);
}
let admin,employee,visitor;
before(async()=>{
  admin = await account({admin:true});
  employee = await account(); // No staff:true claim, as in Spark client signup.
  visitor = await account();
});
after(async()=>{
  if (employee) await request(`${root}/staffProfiles/${employee.localId}`,'DELETE',undefined,'owner');
});
test('root admin can link a normal Firebase Auth employee UID and eight-digit Staff ID',async()=>{
  const r=await save(employee.localId,staffProfile(),admin.idToken);
  assert.equal(r.status,200,JSON.stringify(r.body));
  const own=await request(`${root}/staffProfiles/${employee.localId}`,'GET',undefined,employee.idToken);
  assert.equal(own.status,200,JSON.stringify(own.body));
  assert.equal(own.body.fields.staffId.stringValue,'STF-12345678');
  assert.equal(own.body.fields.status.stringValue,'inactive');
});
test('employee without staff claim cannot change eligible roles or status',async()=>{
  const edit=await save(employee.localId,staffProfile({status:text('active')}),employee.idToken);
  assert.equal(edit.status,403,JSON.stringify(edit.body));
  const forged=await save(visitor.localId,staffProfile({eligibleRoles:roleList(['operations_manager'])}),visitor.idToken);
  assert.equal(forged.status,403,JSON.stringify(forged.body));
});
test('Staff ID is immutable, visitor cannot read another employee profile',async()=>{
  const otherId=await save(employee.localId,staffProfile({staffId:text('STF-87654321')}),admin.idToken);
  assert.equal(otherId.status,403,JSON.stringify(otherId.body));
  const otherRead=await request(`${root}/staffProfiles/${employee.localId}`,'GET',undefined,visitor.idToken);
  assert.equal(otherRead.status,403,JSON.stringify(otherRead.body));
});
