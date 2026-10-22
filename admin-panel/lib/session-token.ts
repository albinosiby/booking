/** Signed, expiring session value usable from both the proxy and server code. */
const encoder = new TextEncoder();
function secret() {
  return process.env.ADMIN_SESSION_SECRET || "";
}
async function sign(payload: string) {
  if (secret().length < 32) throw new Error("ADMIN_SESSION_SECRET must contain at least 32 characters.");
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret()),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  return Array.from(new Uint8Array(mac), (b) => b.toString(16).padStart(2, "0")).join("");
}
export async function createSession(hours = 12) {
  const payload = String(Date.now() + hours * 3600_000);
  return `${payload}.${await sign(payload)}`;
}
export async function validSession(value?: string) {
  if (!value || secret().length < 32) return false;
  const match = /^(\d{13})\.([a-f0-9]{64})$/.exec(value);
  if (!match) return false;
  const [, payload, mac] = match;
  if (Number(payload) <= Date.now()) return false;
  const expected = await sign(payload);
  if (expected.length !== mac.length) return false;
  let diff = 0;
  for (let i = 0; i < mac.length; i++) diff |= mac.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}
