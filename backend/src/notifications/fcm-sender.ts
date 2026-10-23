import { createSign } from "node:crypto";

export type PushMessage = {
  token: string;
  eventId: string;
  bookingId: string;
  userId: string;
  kind: string;
  reference: string;
};
export class PushFailure extends Error {
  constructor(
    public readonly code: string,
    public readonly retryable: boolean,
    public readonly unregistered = false,
    public readonly retryAfterSeconds = 0,
  ) {
    super(code);
  }
}
export interface PushSender {
  send(message: PushMessage): Promise<void>;
}

/** Small HTTP v1 adapter shared by Node and Supabase's Node-compatible runtime. */
export class FcmSender implements PushSender {
  private access?: { token: string; expires: number };
  private refreshing?: Promise<string>;
  constructor(private readonly http: typeof fetch = fetch) {}

  private credentials() {
    try {
      const value = JSON.parse(
        process.env.FIREBASE_SERVICE_ACCOUNT_JSON ?? "{}",
      );
      if (
        typeof value.project_id !== "string" ||
        !/^[a-z][a-z0-9-]+$/.test(value.project_id) ||
        typeof value.client_email !== "string" ||
        typeof value.private_key !== "string"
      )
        throw new Error();
      return value as {
        project_id: string;
        client_email: string;
        private_key: string;
      };
    } catch {
      throw new PushFailure("FCM_CREDENTIALS", true, false, 300);
    }
  }
  private async accessToken() {
    if (this.access && this.access.expires > Date.now() + 60000)
      return this.access.token;
    if (this.refreshing) return this.refreshing;
    this.refreshing = this.mintToken();
    try {
      return await this.refreshing;
    } finally {
      this.refreshing = undefined;
    }
  }
  private async mintToken() {
    try {
      const key = this.credentials();
      const now = Math.floor(Date.now() / 1000);
      const encode = (value: unknown) =>
        Buffer.from(JSON.stringify(value)).toString("base64url");
      const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({ iss: key.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 })}`;
      const signature = createSign("RSA-SHA256")
        .update(unsigned)
        .sign(key.private_key, "base64url");
      const response = await this.http("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
          assertion: `${unsigned}.${signature}`,
        }),
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) throw new PushFailure("FCM_OAUTH", true, false, 300);
      const result = (await response.json()) as {
        access_token?: string;
        expires_in?: number;
      };
      if (!result.access_token || !result.expires_in)
        throw new PushFailure("FCM_OAUTH", true, false, 300);
      this.access = {
        token: result.access_token,
        expires: Date.now() + result.expires_in * 1000,
      };
      return result.access_token;
    } catch (error) {
      if (error instanceof PushFailure) throw error;
      throw new PushFailure("FCM_OAUTH", true, false, 300);
    }
  }
  async send(m: PushMessage) {
    const title = (
      {
        created: "Order placed",
        cancelled: "Order cancelled",
        rescheduled: "Order rescheduled",
      } as Record<string, string>
    )[m.kind];
    if (!title) throw new PushFailure("INVALID_EVENT", false);
    const key = this.credentials();
    const access = await this.accessToken();
    let response: Response;
    try {
      response = await this.http(
        `https://fcm.googleapis.com/v1/projects/${key.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${access}`,
            "content-type": "application/json",
          },
          signal: AbortSignal.timeout(10000),
          body: JSON.stringify({
            message: {
              token: m.token,
              notification: {
                title,
                body: `Booking ${m.reference}. Open Booking OS for details.`,
              },
              data: {
                event_id: m.eventId,
                booking_id: m.bookingId,
                event_type: m.kind,
                recipient_user_id: m.userId,
              },
              android: {
                priority: "high",
                ttl: "86400s",
                notification: {
                  channel_id: "booking_orders_bell_v2",
                  sound: "new_booking_bell",
                  icon: "ic_stat_booking",
                  tag: m.eventId,
                },
              },
              apns: {
                headers: {
                  "apns-priority": "10",
                  "apns-expiration": String(
                    Math.floor(Date.now() / 1000) + 86400,
                  ),
                },
                payload: {
                  aps: { sound: "default", "thread-id": "booking_orders" },
                },
              },
            },
          }),
        },
      );
    } catch {
      throw new PushFailure("FCM_NETWORK", true);
    }
    if (response.ok) return;
    const failure = (await response.json().catch(() => ({}))) as {
      error?: { details?: { errorCode?: string; "@type"?: string }[] };
    };
    const provider = failure.error?.details?.find(
      (d) =>
        d["@type"] === "type.googleapis.com/google.firebase.fcm.v1.FcmError",
    )?.errorCode;
    if (provider === "UNREGISTERED")
      throw new PushFailure("UNREGISTERED", false, true);
    if (response.status === 401) this.access = undefined;
    const retryable =
      response.status === 429 ||
      response.status >= 500 ||
      response.status === 401 ||
      response.status === 403;
    const header = response.headers.get("retry-after");
    const retryAfter = header
      ? Number(header) || Math.max(0, (Date.parse(header) - Date.now()) / 1000)
      : 0;
    // Do not persist provider text: it can contain a registration token or request body.
    throw new PushFailure(
      `FCM_HTTP_${response.status}`,
      retryable,
      false,
      Number.isFinite(retryAfter) ? Math.min(retryAfter, 3600) : 0,
    );
  }
}
