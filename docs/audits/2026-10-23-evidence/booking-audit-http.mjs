import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
const origin = 'http://127.0.0.1:3101/public/v1/sites/eden-sports';
let checks = 0;
async function request(path = '', body) {
  const response = await fetch(origin + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: body === undefined ? {} : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(45000),
  });
  return { status: response.status, data: await response.json() };
}
function check(value, expected, label) {
  assert.equal(value, expected, label);
  checks++;
}
const catalog = await request();
check(catalog.status, 200, 'catalog');
check(catalog.data.businesses.length, 6, 'six business types');
for (const business of catalog.data.businesses) {
  const resource = business.resources[0];
  const option = resource.options[0];
  let selection;
  let slots;
  for (let offset = 1; offset <= 7; offset++) {
    const date = new Date(Date.parse(business.today + 'T12:00:00Z') + offset * 86400000).toISOString().slice(0, 10);
    selection = { business_id: business.id, resource_id: resource.id, option_id: option.id,
      date, time: option.fixed_time || '06:00', duration_minutes: option.minimum_duration || option.default_duration, people: 1 };
    slots = await request('/availability', { selection });
    check(slots.status, 200, business.type + ' availability');
    const available = slots.data.slots.find(slot => slot.available);
    if (available) { selection.time = available.time; break; }
  }
  const quote = await request('/quote', { selection });
  check(quote.status, 200, business.type + ' quote ' + JSON.stringify(quote.data));
  const command = { command_key: randomUUID(), selection, quote_token: quote.data.quote_token,
    customer: { name: 'Disposable QA customer', phone: '+919999' + String(100000 + catalog.data.businesses.indexOf(business)) } };
  const booking = await request('/bookings', command);
  check(booking.status, 201, business.type + ' confirm ' + JSON.stringify(booking.data));
  check(booking.data.payment_status, quote.data.total_minor ? 'unpaid' : 'paid', business.type + ' payment status');
  const replay = await request('/bookings', command);
  check(replay.status, 201, business.type + ' replay');
  check(replay.data.reference, booking.data.reference, business.type + ' idempotency');
  console.log(JSON.stringify({ business: business.type, result: 'PASS', reference: booking.data.reference }));
}
const malformed = await request('/quote', { selection: {} });
check(malformed.status, 422, 'malformed quote');
const missing = await fetch('http://127.0.0.1:3101/public/v1/sites/no-such-qa-venue');
check(missing.status, 404, 'missing website');
console.log(JSON.stringify({ checks, result: 'PASS', persistence: 'isolated memory only' }));
