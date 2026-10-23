import { spawn } from "node:child_process";
import { access, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { routingConfiguration } from "./routing.mjs";

const root = fileURLToPath(new URL("../", import.meta.url)).replace(/\/$/, "");
const children = new Map();
let stopping = false;
let exitCode = 0;
let healthServer;

function port(name, fallback) {
  const value = process.env[name] || String(fallback);
  if (!/^\d+$/.test(value) || Number(value) < 1024 || Number(value) > 65535)
    throw new Error(`${name} must be an unprivileged TCP port (1024–65535).`);
  return Number(value);
}

function stop(code) {
  if (stopping) return;
  stopping = true;
  exitCode = code;
  healthServer?.close();
  for (const [child, name] of children) child.kill(name === "gateway" ? "SIGQUIT" : "SIGTERM");
  const timer = setTimeout(() => {
    for (const child of children.keys()) child.kill("SIGKILL");
    process.exit(exitCode);
  }, 10_000);
  timer.unref();
  if (!children.size) process.exit(exitCode);
}

function launch(name, command, args, options = {}) {
  const child = spawn(command, args, { stdio: "inherit", ...options });
  children.set(child, name);
  child.on("error", (error) => {
    console.error(`[deploy] Could not start ${name}: ${error.code || "spawn failed"}`);
    stop(1);
  });
  child.on("exit", (code, signal) => {
    children.delete(child);
    if (!stopping) {
      console.error(`[deploy] ${name} exited (${signal || code}); restarting the service is required.`);
      stop(1);
    } else if (!children.size) {
      process.exit(exitCode);
    }
  });
}

process.on("SIGTERM", () => stop(0));
process.on("SIGINT", () => stop(0));

try {
  const routing = routingConfiguration();
  const publicPort = port("PORT", 8080);
  const bookingPort = port("BOOKING_INTERNAL_PORT", 3000);
  const adminPort = port("ADMIN_INTERNAL_PORT", 3100);
  const healthPort = port("HEALTH_INTERNAL_PORT", 3102);
  if (new Set([publicPort, bookingPort, adminPort, healthPort]).size !== 4)
    throw new Error("The public and internal ports must be different.");
  if (/[\r\n"$\\]/.test(root)) throw new Error("Unsupported deployment directory.");

  const required = ["ADMIN_PANEL_PASSWORD", "ADMIN_SESSION_SECRET", "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "BOOKING_API_BASE_URL", "BOOKING_API_PUBLISHABLE_KEY"];
  const missing = required.filter((name) => !process.env[name]?.trim());
  if (missing.length) throw new Error(`Set the required Railway variables: ${missing.join(", ")}.`);
  if (process.env.ADMIN_SESSION_SECRET.length < 32)
    throw new Error("ADMIN_SESSION_SECRET must contain at least 32 characters.");
  for (const name of ["SUPABASE_URL", "BOOKING_API_BASE_URL"]) {
    let url;
    try { url = new URL(process.env[name]); } catch { throw new Error(`${name} must be an HTTPS URL.`); }
    const local = url.protocol === "http:" && ["localhost", "127.0.0.1"].includes(url.hostname);
    if ((!local && url.protocol !== "https:") || url.username || url.password || url.search || url.hash)
      throw new Error(`${name} must use HTTPS without credentials, query parameters or fragments.`);
  }
  for (const name of ["SUPABASE_PUBLISHABLE_KEY", "BOOKING_API_PUBLISHABLE_KEY"])
    if (!process.env[name].startsWith("sb_publishable_")) throw new Error(`${name} must be a public Supabase publishable key.`);

  const staticFiles = ["static/landing/index.html", "static/app/index.html", "static/app/flutter_bootstrap.js", "static/app/main.dart.js"];
  await Promise.all([...staticFiles, "booking/server.js", "admin/server.js"].map((path) => access(join(root, path))));
  const runtime = await mkdtemp(join(tmpdir(), "bookingos-"));
  for (const dir of ["client-body", "proxy", "fastcgi", "uwsgi", "scgi"])
    await mkdir(join(runtime, dir));
  const template = await readFile(join(root, "deploy/nginx.conf.template"), "utf8");
  const substitutions = { ROOT: root, RUNTIME: runtime, PORT: publicPort, BOOKING_PORT: bookingPort, ADMIN_PORT: adminPort, HEALTH_PORT: healthPort, TENANT_HOST_RULE: routing.tenantHostRule };
  const config = template.replace(/__(\w+)__/g, (_, name) => {
    if (!(name in substitutions)) throw new Error(`Unknown gateway placeholder: ${name}`);
    return String(substitutions[name]);
  });
  const configPath = join(runtime, "nginx.conf");
  await writeFile(configPath, config);

  healthServer = createServer(async (request, response) => {
    if (request.url !== "/healthz" || !["GET", "HEAD"].includes(request.method)) {
      response.writeHead(404).end();
      return;
    }
    try {
      await Promise.all([
        ...staticFiles.map((path) => access(join(root, path))),
        ...[`http://127.0.0.1:${bookingPort}/api/health`, `http://127.0.0.1:${adminPort}/admin/healthz`].map(async (url) => {
          const result = await fetch(url, { redirect: "manual", signal: AbortSignal.timeout(3000) });
          await result.body?.cancel();
          if (result.status !== 200) throw new Error("A frontend is unavailable.");
        }),
      ]);
      if (stopping) throw new Error("Shutting down.");
      response.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" }).end('{"status":"ok"}');
    } catch {
      response.writeHead(503, { "Content-Type": "application/json", "Cache-Control": "no-store" }).end('{"status":"unavailable"}');
    }
  });
  healthServer.on("error", () => { console.error("[deploy] Health listener failed."); stop(1); });
  healthServer.listen(healthPort, "127.0.0.1");

  // Forward only frontend settings; unrelated Railway/database secrets stay out
  // of both child servers, and admin credentials stay out of the booking server.
  const commonEnv = Object.fromEntries(Object.entries(process.env).filter(([name]) =>
    ["NODE_ENV", "NODE_OPTIONS", "NEXT_TELEMETRY_DISABLED", "PATH", "TZ"].includes(name)));
  const bookingEnv = { ...commonEnv, ...Object.fromEntries(Object.entries(process.env).filter(([name]) => name.startsWith("BOOKING_"))), BOOKING_SITE_DOMAIN: routing.domain, BOOKING_ROUTING_MODE: routing.mode };
  const adminEnv = { ...commonEnv, ...Object.fromEntries(Object.entries(process.env).filter(([name]) =>
    name.startsWith("ADMIN_") || ["BOOKING_API_PUBLISHABLE_KEY", "BOOKING_API_BASE_URL"].includes(name))) };
  launch("booking", process.execPath, [join(root, "booking/server.js")], {
    cwd: join(root, "booking"), env: { ...bookingEnv, PORT: String(bookingPort), HOSTNAME: "127.0.0.1" },
  });
  launch("admin", process.execPath, [join(root, "admin/server.js")], {
    cwd: join(root, "admin"), env: { ...adminEnv, PORT: String(adminPort), HOSTNAME: "127.0.0.1" },
  });
  launch("gateway", "nginx", ["-c", configPath, "-g", "daemon off;"]);
  console.info(`[deploy] Gateway listening on port ${publicPort}; readiness: /_health`);
} catch (error) {
  // Configuration errors name missing settings but never print their values.
  console.error(`[deploy] ${error.message}`);
  stop(1);
}
