'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createStaffAccountHandler} = require('../src/staff_onboarding');

class HttpsError extends Error {
  constructor(code, message) {super(message);this.code = code;}
}
function setup(overrides = {}) {
  const created = [], claims = [], deleted = [], saved = [];
  const actor = {disabled:false,emailVerified:true,customClaims:{admin:true}};
  const auth = {
    async getUser() {return overrides.actor || actor;},
    async createUser(data) {if (overrides.createError) throw overrides.createError;created.push(data);return {uid:'generated-uid'};},
    async setCustomUserClaims(uid, attributes) {claims.push({uid,attributes});},
    async deleteUser(uid) {deleted.push(uid);},
  };
  const db = {
    collection(name) {return {doc(id) {return {name,id};}};},
    async runTransaction(handler) {
      if (overrides.transactionError) throw Error('storage unavailable');
      const tx = {
        async get() {return {exists:false};},
        set(ref,data) {saved.push({ref,data});},
        create(ref,data) {saved.push({ref,data});},
      };
      return handler(tx);
    },
  };
  const FieldValue = {serverTimestamp: () => 'SERVER_TIME'};
  const run = createStaffAccountHandler({auth,db,FieldValue,HttpsError});
  const request = (data, token={email_verified:true}) => ({auth:{uid:'root-uid',token},data});
  return {run,request,created,claims,deleted,saved};
}
const valid = {fullName:'Mary Tan',email:'Mary@Example.com',eligibleRoles:['photographer','admission_staff']};

test('only a verified, active root admin can create a staff account',async()=>{
  const f=setup({actor:{disabled:false,emailVerified:true,customClaims:{staff:true}}});
  await assert.rejects(f.run(f.request(valid)),e=>e.code==='permission-denied');
  assert.equal(f.created.length,0);
  const g=setup();
  await assert.rejects(g.run({data:valid}),e=>e.code==='unauthenticated');
});

test('does not allow self-assignment of super admin or bad role codes',async()=>{
  for(const roles of [['super_admin'],['photographer','photographer'],[],['x']]) {
    const f=setup();
    await assert.rejects(f.run(f.request({...valid,eligibleRoles:roles})),e=>e.code==='invalid-argument');
    assert.equal(f.created.length,0);
  }
});

test('creates a unique auth identity and an inactive staff record; no password is disclosed',async()=>{
  const f=setup();const response=await f.run(f.request(valid));
  assert.deepEqual(response,{uid:'generated-uid',staffId:'STF-00001',email:'mary@example.com',invitationRequired:true,accountStatus:'inactive'});
  assert.equal(f.created[0].email,'mary@example.com');
  assert.ok(f.created[0].password.length>32);
  assert.equal(Object.hasOwn(response,'password'),false);
  assert.deepEqual(f.claims,[{uid:'generated-uid',attributes:{staff:true}}]);
  const profile = f.saved.find(s=>s.ref.name==='staffProfiles');
  assert.equal(profile.data.status,'inactive');
  assert.equal(profile.data.staffId,'STF-00001');
  assert.deepEqual(profile.data.eligibleRoles,['admission_staff','photographer']);
});

test('existing email is rejected without modifying current account',async()=>{
  const f=setup({createError:{code:'auth/email-already-exists'}});
  await assert.rejects(f.run(f.request(valid)),e=>e.code==='already-exists');
  assert.equal(f.deleted.length,0);
});

test('a Firestore write failure rolls back the new Auth account',async()=>{
  const f=setup({transactionError:true});
  await assert.rejects(f.run(f.request(valid)),e=>e.code==='internal');
  assert.deepEqual(f.deleted,['generated-uid']);
});
