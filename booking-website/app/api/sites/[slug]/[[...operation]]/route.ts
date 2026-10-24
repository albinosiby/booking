import { NextRequest } from "next/server";
import { bookingApiUrl, bookingHeaders } from "../../../../../lib/server-api";
export const dynamic = "force-dynamic";
type Context = { params: Promise<{ slug: string; operation?: string[] }> };
async function dispatch(request: NextRequest, context: Context) {
  const { slug, operation: parts = [] } = await context.params,
    operation = parts.join("/");
  if (
    !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) ||
    slug.length > 80 ||
    (request.method === "GET"
      ? !(
          ["", "catalog", "logo", "payment-qr"].includes(operation) ||
          /^images\/[a-f0-9-]{36}$/.test(operation)
        )
      : !["availability", "quote", "bookings"].includes(operation))
  )
    return Response.json({ message: "Page not found." }, { status: 404 });
  const preview = request.nextUrl.searchParams.get("preview") ?? undefined;
  if (preview && !/^[a-f0-9]{64}$/.test(preview))
    return Response.json({ message: "Invalid preview link." }, { status: 400 });
  let body: string | undefined;
  if (request.method === "POST") {
    if (!request.headers.get("content-type")?.startsWith("application/json"))
      return Response.json({ message: "JSON is required." }, { status: 415 });
    if (Number(request.headers.get("content-length")) > 16384)
      return Response.json(
        { message: "Request is too large." },
        { status: 413 },
      );
    // Bound the stream as well as Content-Length, which a caller may omit.
    const reader = request.body?.getReader(),
      chunks: Uint8Array[] = [];
    let size = 0;
    if (!reader)
      return Response.json(
        { message: "Request body is required." },
        { status: 400 },
      );
    try {
      while (true) {
        const part = await reader.read();
        if (part.done) break;
        size += part.value.length;
        if (size > 16384) {
          await reader.cancel();
          return Response.json(
            { message: "Request is too large." },
            { status: 413 },
          );
        }
        chunks.push(part.value);
      }
    } finally {
      reader.releaseLock();
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    body = new TextDecoder().decode(bytes);
  }
  try {
    const upstreamUrl = new URL(bookingApiUrl(slug, operation, preview));
    const paymentVersion = request.nextUrl.searchParams.get("v");
    if (operation === "payment-qr" && paymentVersion) {
      if (!/^[1-9][0-9]{0,9}$/.test(paymentVersion))
        return Response.json(
          { message: "Invalid payment version." },
          { status: 400 },
        );
      upstreamUrl.searchParams.set("v", paymentVersion);
    }
    const upstream = await fetch(upstreamUrl, {
      method: request.method,
      headers: {
        ...bookingHeaders(),
        ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
      },
      body,
      cache: "no-store",
      signal: AbortSignal.timeout(25000),
    });
    const headers = new Headers({
      "Cache-Control": "no-store",
      "Content-Type":
        upstream.headers.get("content-type") ?? "application/json",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
    });
    return new Response(upstream.body, { status: upstream.status, headers });
  } catch {
    return Response.json(
      { message: "Cannot reach the booking service. Please retry shortly." },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }
}
export const GET = dispatch;
export const POST = dispatch;
