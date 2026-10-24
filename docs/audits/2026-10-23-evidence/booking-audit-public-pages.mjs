import assert from 'node:assert/strict';
const origin = 'http://127.0.0.1:3002';
const catalogResponse = await fetch(origin + '/api/sites/eden-sports');
assert.equal(catalogResponse.status, 200);
assert.equal(catalogResponse.headers.get('cache-control'), 'no-store');
const site = await catalogResponse.json();
for (const path of ['/eden-sports', ...site.businesses.map(business => `/eden-sports/book/${business.id}`)]) {
  const response = await fetch(origin + path);
  const html = await response.text();
  assert.equal(response.status, 200, path);
  assert.match(html, /Eden Sports Arena/);
  assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
  console.log(JSON.stringify({path,status:response.status,htmlBytes:html.length,result:'PASS'}));
}
for (const [path, status] of [['/api/sites/eden-sports/private',404], ['/api/sites/eden-sports?preview=bad-token',400], ['/api/sites/no-such-qa-venue',404]]) {
  const response = await fetch(origin + path);
  assert.equal(response.status,status,path);
  console.log(JSON.stringify({path,status,result:'PASS'}));
}
const unsupported = await fetch(origin + '/api/sites/eden-sports/bookings',{method:'POST',body:'invalid'});
assert.equal(unsupported.status,415);
console.log('PASS: homepage, six booking pages, no-store proxy, operation allowlist, preview validation and JSON enforcement.');
