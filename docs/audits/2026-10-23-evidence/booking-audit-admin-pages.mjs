import assert from 'node:assert/strict';
import { createSession } from '/Users/albinosiby/Tatos Dev/booking/admin-panel/lib/session-token.ts';
process.env.ADMIN_SESSION_SECRET='qa-audit-session-secret-01234567890123456789';
const session=await createSession();
const paths=['/admin','/admin/organizations','/admin/organizations/00000000-0000-4000-8000-000000000001','/admin/users','/admin/support','/admin/agent-requests','/admin/audit'];
for(const path of paths){
  const response=await fetch('http://127.0.0.1:3100'+path,{headers:{Cookie:'admin_session='+session},redirect:'manual',signal:AbortSignal.timeout(30000)});
  const html=await response.text();
  assert.equal(response.status,200,path);
  assert.doesNotMatch(html,/Let's try that again\./,path);
  assert.match(html, /BookingOS/);
  console.log(JSON.stringify({path,status:response.status,result:'PASS',htmlBytes:html.length}));
}
for(const path of paths.slice(1)){
  const response=await fetch('http://127.0.0.1:3100'+path,{headers:{Host:'bookingos.online','x-forwarded-proto':'https'},redirect:'manual',signal:AbortSignal.timeout(30000)});
  assert.equal(new URL(response.headers.get('location'),'https://bookingos.online').toString(),'https://bookingos.online/admin/login',path);
}
console.log('PASS: seven authenticated fixture pages and six public-origin redirect checks. Session generated only from a disposable fixture secret; no production credentials.');
