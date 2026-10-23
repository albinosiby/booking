/** Request header the proxy sets after resolving `<slug>.<domain>`; never trusted from clients. */
export const SITE_HOST_HEADER = "x-booking-site-host";
const label = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const reserved = new Set([
  "www",
  "api",
  "app",
  "admin",
  "book",
  "login",
  "sign-in",
  "register",
]);

/** Owner/staff entry points that live in the Flutter app, not on booking websites. */
const appPaths: Record<string, string> = {
  "/login": "/sign-in",
  "/sign-in": "/sign-in",
  "/register": "/register",
  "/signup": "/register",
};

/** Origin of the owner app; configured relative URLs resolve on the main domain. */
export function appOrigin(domain: string, value = process.env.BOOKING_APP_URL) {
  if (value)
    return new URL(
      value,
      domain === "localhost" ? "http://localhost:8080" : `https://${domain}`,
    ).origin;
  return domain === "localhost"
    ? "http://localhost:8080"
    : `https://app.${domain}`;
}

/** `/login` on the main domain or any booking website opens the app's sign-in page. */
export function appRedirect(
  pathname: string,
  domain: string,
  value = process.env.BOOKING_APP_URL,
) {
  const path = appPaths[pathname.replace(/\/$/, "") || "/"];
  if (!path) return null;
  const url = new URL(value || appOrigin(domain, ""), appOrigin(domain, "/"));
  // The shared deployment mounts Flutter at /app; keep that configured prefix.
  url.pathname = `${url.pathname.replace(/\/$/, "")}${path}`;
  url.search = "";
  url.hash = "";
  return url.toString();
}

export type SiteHost =
  { kind: "site"; slug: string } | { kind: "root" } | { kind: "other" };

/** `bookingos.online` in production; `localhost` resolves `<slug>.localhost` in development. */
export function siteDomain(value = process.env.BOOKING_SITE_DOMAIN) {
  return (value || "bookingos.online").trim().toLowerCase().replace(/\.$/, "");
}

export function resolveSiteHost(
  host: string | null | undefined,
  domain: string,
): SiteHost {
  const name = (host ?? "")
    .trim()
    .toLowerCase()
    .replace(/:\d+$/, "")
    .replace(/\.$/, "");
  if (!name) return { kind: "other" };
  if (name === domain || name === `www.${domain}`) return { kind: "root" };
  if (!name.endsWith(`.${domain}`)) return { kind: "other" };
  const slug = name.slice(0, -domain.length - 1);
  return label.test(slug) &&
    slug.length >= 3 &&
    slug.length <= 63 &&
    !reserved.has(slug)
    ? { kind: "site", slug }
    : { kind: "other" };
}

/** Old `/<slug>` links on the main domain move to the organisation's own subdomain. */
export function legacySitePath(pathname: string) {
  const m = /^\/([a-z0-9]+(?:-[a-z0-9]+)*)(\/.*)?$/.exec(pathname);
  if (!m || reserved.has(m[1]) || m[1].length < 3 || m[1].length > 63)
    return null;
  return { slug: m[1], path: m[2] ?? "/" };
}

export function siteOrigin(slug: string, domain: string, requestHost = "") {
  if (domain !== "localhost") return `https://${slug}.${domain}`;
  // Local testing keeps the dev server's port.
  return `http://${slug}.localhost${/:\d+$/.exec(requestHost)?.[0] ?? ""}`;
}
