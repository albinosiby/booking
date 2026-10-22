import { NextResponse, type NextRequest } from "next/server";
import {
  SITE_HOST_HEADER,
  appRedirect,
  legacySitePath,
  resolveSiteHost,
  siteDomain,
  siteOrigin,
} from "./lib/site-host";

/**
 * Serves `https://<slug>.bookingos.online/...` from the `/<slug>/...` routes.
 * Hosts outside the configured domain (local IPs, hosting previews) keep path routing.
 */
export function proxy(request: NextRequest) {
  const domain = siteDomain(),
    // Hosting proxies (and Next's own rewrite pass) report the visitor's host here.
    hostHeader =
      request.headers.get("x-forwarded-host")?.split(",")[0].trim() ||
      request.headers.get("host") ||
      "",
    host = process.env.BOOKING_ROUTING_MODE === "path"
      ? { kind: "other" as const }
      : resolveSiteHost(hostHeader, domain),
    { pathname, search } = request.nextUrl;
  if (host.kind !== "other") {
    const app = appRedirect(pathname, domain);
    if (app) return NextResponse.redirect(app, 307);
  }
  if (host.kind === "site" && !pathname.startsWith("/api/")) {
    const prefix = `/${host.slug}`,
      prefixed = pathname === prefix || pathname.startsWith(`${prefix}/`);
    // Next runs the proxy again for the rewritten path; leave that pass alone.
    if (prefixed && request.headers.get(SITE_HOST_HEADER) === host.slug)
      return NextResponse.next();
    if (prefixed) {
      const url = request.nextUrl.clone();
      url.pathname = pathname.slice(prefix.length) || "/";
      return NextResponse.redirect(url, 308);
    }
    const headers = new Headers(request.headers);
    headers.set(SITE_HOST_HEADER, host.slug);
    const url = request.nextUrl.clone();
    url.pathname = pathname === "/" ? prefix : `${prefix}${pathname}`;
    return NextResponse.rewrite(url, { request: { headers } });
  }
  if (host.kind === "root") {
    const legacy = legacySitePath(pathname);
    if (legacy)
      return NextResponse.redirect(
        `${siteOrigin(legacy.slug, domain, hostHeader)}${legacy.path}${search}`,
        308,
      );
  }
  // Path routing never trusts a client-supplied site header.
  const headers = new Headers(request.headers);
  headers.delete(SITE_HOST_HEADER);
  return NextResponse.next({ request: { headers } });
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|robots.txt).*)"],
};
