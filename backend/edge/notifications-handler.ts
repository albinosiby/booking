import { createHash, timingSafeEqual } from "node:crypto";
import type { NotificationDispatcher } from "../src/notifications/notification-dispatcher";

export function notificationHandler(dispatcher: NotificationDispatcher) {
  return async (request: Request): Promise<Response> => {
    const headers = {
      "cache-control": "no-store",
      "content-type": "application/json",
    };
    if (request.method !== "POST")
      return new Response('{"error":"METHOD_NOT_ALLOWED"}', {
        status: 405,
        headers,
      });
    const expected = process.env.BOOKING_PUSH_DISPATCH_SECRET;
    const supplied = request.headers.get("x-booking-push-secret") ?? "";
    const digest = (v: string) => createHash("sha256").update(v).digest();
    if (
      !expected ||
      expected.length < 32 ||
      !timingSafeEqual(digest(expected), digest(supplied))
    )
      return new Response('{"error":"UNAUTHORIZED"}', { status: 401, headers });
    if (process.env.BOOKING_PUSH_DISPATCH_ENABLED !== "true")
      return new Response('{"disabled":true}', { status: 200, headers });
    try {
      // Deliberately ignore caller input; only queued, authoritative events can send.
      const result = await dispatcher.dispatch(20);
      console.info(
        JSON.stringify({ event: "booking_push_dispatch", ...result }),
      );
      return Response.json(result, { headers });
    } catch {
      console.error(JSON.stringify({ event: "booking_push_dispatch_failed" }));
      return new Response('{"error":"DISPATCH_FAILED"}', {
        status: 503,
        headers,
      });
    }
  };
}
