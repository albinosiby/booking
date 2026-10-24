const base = 'https://bookingos.online';
const paths = ['/', '/app/', '/app/sign-in', '/app/register', '/app/home', '/app/profile/booking-website', '/app/flutter_bootstrap.js', '/app/main.dart.js', '/admin', '/admin/login', '/admin/organizations', '/admin/users', '/admin/support', '/admin/agent-requests', '/admin/audit', '/_health', '/api/health'];
for (const path of paths) {
  const start = Date.now();
  try {
    const response = await fetch(base + path, { redirect: 'manual', signal: AbortSignal.timeout(20000) });
    const text = await response.text();
    console.log(JSON.stringify({ path, status: response.status, ms: Date.now() - start,
      bytes: Buffer.byteLength(text), location: response.headers.get('location'),
      contentType: response.headers.get('content-type'), cache: response.headers.get('cache-control'),
      frame: response.headers.get('x-frame-options'), nosniff: response.headers.get('x-content-type-options'),
      hsts: response.headers.get('strict-transport-security'),
      title: text.match(/<title>([^<]*)<\/title>/)?.[1] ?? null }));
  } catch (error) { console.log(JSON.stringify({ path, error: error.message })); }
}
