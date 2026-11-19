'use strict';
// Emulator ONLY. The guard deliberately refuses production projects.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const project = process.env.GCLOUD_PROJECT;
const fh = process.env.FIRESTORE_EMULATOR_HOST;
const ah = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!project?.startsWith('demo-') ||
    !/^(127\.0\.0\.1|localhost):\d+$/.test(fh || '') ||
    !/^(127\.0\.0\.1|localhost):\d+$/.test(ah || '')) {
  throw new Error('Only local demo Auth/Firestore emulator projects are allowed.');
}
const root = `http://${fh}/v1/projects/${project}/databases/(default)/documents`;
const auth = `http://${ah}/identitytoolkit.googleapis.com/v1`;
const prefix = `binding-${randomUUID()}`;
const str = x => ({stringValue:x});
const bool = x => ({booleanValue:x});
const timestamp = x => ({timestampValue:x});
const name = (collection, key) => `projects/${project}/databases/(default)/documents/${collection}/${key}`;
const write = (collection,key,fields) => ({
  update:{name:name(collection,key),fields},
  updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}],
});
async function req(url,method='GET',body,token){
  const r = await fetch(url,{method,
    headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},
    body:body===undefined?undefined:JSON.stringify(body)});
  const data = await r.json();
  return {status:r.status,data};
}
const commit = (writes,token) => req(root+':commit','POST',{writes},token);
let admin, staffUid;
const ferris = `${prefix}-ferris`;
const carousel = `${prefix}-carousel`;
const courseId = `${prefix}-ridecourse`;
const photoCourseId = `${prefix}-photo`;
const oldId = `${prefix}-old`;
const qid = `${prefix}-qualification`;
const getCourse = key => req(`${root}/staffTrainingCourses/${key}`,'GET',undefined,admin);
const entry = (rideId, course=courseId) => ({
  staffUid:str(staffUid),roleCode:str('attraction_operator'),
  title:str('Ferris Wheel Operation Training'),courseId:str(course),
  status:str('approved'),attractionId:str(rideId),
  completedAt:timestamp('2026-11-01T00:00:00Z'),
  expiresAt:timestamp('2027-11-01T00:00:00Z'),
});
const rideCourse = (title, rideId) => ({
  title:str(title),roleCode:str('attraction_operator'),
  attractionId:str(rideId),active:bool(true),
});
before(async()=>{
  const signed = await req(`${auth}/accounts:signUp?key=test`,'POST',{
    email:`${prefix}-root@example.com`,password:'Sample+SafePass91!',returnSecureToken:true,
  });
  assert.equal(signed.status,200,JSON.stringify(signed.data));
  assert.equal((await req(`${auth}/projects/${project}/accounts:update`,'POST',{
    localId:signed.data.localId,customAttributes:JSON.stringify({admin:true})},'owner')).status,200);
  const refreshed=await fetch(`http://${ah}/securetoken.googleapis.com/v1/token?key=test`,{
    method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({grant_type:'refresh_token',refresh_token:signed.data.refreshToken}),
  });
  assert.equal(refreshed.status,200);
  admin=(await refreshed.json()).id_token;
  const employee=await req(`${auth}/accounts:signUp?key=test`,'POST',{
    email:`${prefix}-staff@example.com`,password:'Sample+SafePass91!',returnSecureToken:true,
  });
  assert.equal(employee.status,200);
  staffUid=employee.data.localId;
  // Fixture attractions are admin-seeded in the isolated emulator only.
  for(const [id,title] of [[ferris,'Ferris Wheel'],[carousel,'Carousel']]) {
    assert.equal((await req(`${root}/attractions/${id}`,'PATCH',{
      fields:{name:str(title),category:str('Rides'),status:str('open'),
        minHeightCm:{integerValue:'90'},mapX:{doubleValue:0.3},mapY:{doubleValue:0.4}},
    },'owner')).status,200);
  }
  assert.equal((await commit([write('staffProfiles',staffUid,{
    staffId:str('STF-87654321'),fullName:str('Training Operator'),
    email:str(`${prefix}-staff@example.com`),status:str('inactive'),
    eligibleRoles:{arrayValue:{values:[str('attraction_operator')]}},
  })],admin)).status,200);
});
after(async()=>{
  for(const [col,key] of [
    ['staffQualifications',qid],
    ['staffTrainingCourses',courseId],['staffTrainingCourses',photoCourseId],
    ['staffTrainingCourses',oldId],['staffProfiles',staffUid],
    ['attractions',ferris],['attractions',carousel],
  ]){await req(`${root}/${col}/${key}`,'DELETE',undefined,'owner');}
});
test('ride courses must have a real, fixed attraction',async()=>{
  const missing=await commit([write('staffTrainingCourses',`${prefix}-missing`,{
    title:str('Carousel Operation Training'),roleCode:str('attraction_operator'),active:bool(true),
  })],admin);
  assert.equal(missing.status,403,JSON.stringify(missing.data));
  const invalid=await commit([write('staffTrainingCourses',`${prefix}-bad`,
    rideCourse('Roller Coaster Training',`${prefix}-not-real`))],admin);
  assert.equal(invalid.status,403,JSON.stringify(invalid.data));
  assert.equal((await commit([write('staffTrainingCourses',courseId,
    rideCourse('Ferris Wheel Operation Training',ferris))],admin)).status,200);
  const persisted=await getCourse(courseId);
  assert.equal(persisted.data.fields.attractionId.stringValue,ferris);
});
test('a bound ride cannot be switched to another attraction',async()=>{
  const result=await commit([write('staffTrainingCourses',courseId,
    rideCourse('Ferris Wheel Operation Training',carousel))],admin);
  assert.equal(result.status,403,JSON.stringify(result.data));
  assert.equal((await getCourse(courseId)).data.fields.attractionId.stringValue,ferris);
});
test('qualifications cannot substitute another ride',async()=>{
  const fake=await commit([write('staffQualifications',qid,entry(carousel))],admin);
  assert.equal(fake.status,403,JSON.stringify(fake.data));
  const real=await commit([write('staffQualifications',qid,entry(ferris))],admin);
  assert.equal(real.status,200,JSON.stringify(real.data));
  const saved=await req(`${root}/staffQualifications/${qid}`,'GET',undefined,admin);
  assert.equal(saved.data.fields.attractionId.stringValue,ferris);
});
test('legacy ride courses can be linked once, not silently reassigned',async()=>{
  // Historical unlinked ride course is server-seeded to simulate Step 11 data.
  assert.equal((await req(`${root}/staffTrainingCourses/${oldId}`,'PATCH',{
    fields:{...rideCourse('Carousel Operation Training',carousel),
      attractionId:undefined},
  },'owner')).status,200);
  const legacy=await getCourse(oldId);
  assert.equal(legacy.data.fields.attractionId,undefined);
  const linked=await commit([write('staffTrainingCourses',oldId,
    rideCourse('Carousel Operation Training',carousel))],admin);
  assert.equal(linked.status,200,JSON.stringify(linked.data));
  const switched=await commit([write('staffTrainingCourses',oldId,
    rideCourse('Carousel Operation Training',ferris))],admin);
  assert.equal(switched.status,403,JSON.stringify(switched.data));
});
test('existing non-ride courses remain valid without an attraction',async()=>{
  const created=await commit([write('staffTrainingCourses',photoCourseId,{
    title:str('Photo Workflow Training'),roleCode:str('photographer'),active:bool(true),
  })],admin);
  assert.equal(created.status,200,JSON.stringify(created.data));
});
