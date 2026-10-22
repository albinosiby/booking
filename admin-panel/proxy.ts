import { NextResponse, type NextRequest } from "next/server";
import { SESSION_COOKIE } from "./lib/session-name";
import { validSession } from "./lib/session-token";

/** Every page except /login needs a valid signed session cookie. */
export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  if (pathname === "/login" || pathname === "/healthz" || pathname.startsWith("/_next"))
    return NextResponse.next();
  if (!(await validSession(request.cookies.get(SESSION_COOKIE)?.value))) {
    const url = request.nextUrl.clone();
    // NextURL keeps the compiled /admin basePath when changing pathname.
    url.pathname = "/login";
    url.search = "";
    // Standalone Next may construct request.url using its loopback listener.
    // The gateway supplies the public Host and overwrites forwarded headers.
    const host = request.headers.get("host");
    if (host) url.host = host;
    const protocol = request.headers.get("x-forwarded-proto");
    if (protocol === "http" || protocol === "https") url.protocol = `${protocol}:`;
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}
export const config = { matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"] };
