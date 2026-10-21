/** Authenticated client for the hosted booking-api Edge Function. */
import { randomUUID } from "node:crypto";

export type Config = {
  supabaseUrl: string;
  publishableKey: string;
  apiUrl: string;
  email?: string;
  password?: string;
  refreshToken?: string;
};

const DEFAULT_PROJECT = "https://scwwkaywewecspsrskft.supabase.co";
const DEFAULT_KEY = "sb_publishable_d6iVFApYyh41BlF9GkTsgw_h0d-chZN";

export function configFromEnv(env = process.env): Config {
  const supabaseUrl = (env.BOOKING_SUPABASE_URL ?? DEFAULT_PROJECT).replace(
    /\/$/,
    "",
  );
  const config: Config = {
    supabaseUrl,
    publishableKey: env.BOOKING_PUBLISHABLE_KEY ?? DEFAULT_KEY,
    apiUrl: (
      env.BOOKING_API_URL ?? `${supabaseUrl}/functions/v1/booking-api/v1`
    ).replace(/\/$/, ""),
    email: env.BOOKING_EMAIL,
    password: env.BOOKING_PASSWORD,
    refreshToken: env.BOOKING_REFRESH_TOKEN,
  };
  if (!config.refreshToken && !(config.email && config.password))
    throw new Error(
      "Set BOOKING_EMAIL and BOOKING_PASSWORD (or BOOKING_REFRESH_TOKEN) for the owner/staff account the MCP server acts as.",
    );
  return config;
}

/** Error returned by the API with its HTTP status and server message. */
export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

type Session = { accessToken: string; refreshToken: string; expiresAt: number };

export class BookingClient {
  private session?: Session;
  private signingIn?: Promise<Session>;

  constructor(
    private readonly config: Config,
    private readonly http: typeof fetch = fetch,
  ) {}

  private async grant(type: "password" | "refresh_token", body: object) {
    const res = await this.http(
      `${this.config.supabaseUrl}/auth/v1/token?grant_type=${type}`,
      {
        method: "POST",
        headers: {
          apikey: this.config.publishableKey,
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
      },
    );
    const data = (await res.json().catch(() => ({}))) as Record<string, any>;
    if (!res.ok)
      throw new ApiError(
        `Sign-in failed: ${data.error_description ?? data.msg ?? data.message ?? res.statusText}`,
        res.status,
      );
    return {
      accessToken: data.access_token as string,
      refreshToken: data.refresh_token as string,
      expiresAt: Date.now() + Number(data.expires_in ?? 3600) * 1000,
    };
  }

  private async signIn(): Promise<Session> {
    const refresh = this.session?.refreshToken ?? this.config.refreshToken;
    if (refresh) {
      try {
        return await this.grant("refresh_token", { refresh_token: refresh });
      } catch (error) {
        if (!(this.config.email && this.config.password)) throw error;
      }
    }
    return this.grant("password", {
      email: this.config.email,
      password: this.config.password,
    });
  }

  private async token(force = false) {
    if (!force && this.session && this.session.expiresAt - 60_000 > Date.now())
      return this.session.accessToken;
    this.signingIn ??= this.signIn().finally(() => (this.signingIn = undefined));
    this.session = await this.signingIn;
    return this.session.accessToken;
  }

  async request<T = any>(
    method: "GET" | "POST",
    path: string,
    options: { body?: unknown; query?: Record<string, unknown> } = {},
  ): Promise<T> {
    const url = new URL(this.config.apiUrl + path);
    for (const [k, v] of Object.entries(options.query ?? {}))
      if (v !== undefined && v !== null && v !== "") url.searchParams.set(k, String(v));
    const send = async (force: boolean) =>
      this.http(url, {
        method,
        headers: {
          apikey: this.config.publishableKey,
          authorization: `Bearer ${await this.token(force)}`,
          ...(options.body === undefined
            ? {}
            : { "content-type": "application/json" }),
        },
        body: options.body === undefined ? undefined : JSON.stringify(options.body),
      });
    let res = await send(false);
    // Commands are idempotent by command_key, so one retry after refresh is safe.
    if (res.status === 401) res = await send(true);
    const text = await res.text();
    const data = text ? JSON.parse(text) : null;
    if (!res.ok)
      throw new ApiError(data?.message ?? res.statusText, res.status);
    return data as T;
  }

  /**
   * Sends a booking command. If the outcome is uncertain (network failure or
   * 5xx), the committed result is recovered by its command key before failing.
   */
  async command(path: string, body: Record<string, unknown>) {
    const command_key = (body.command_key as string | undefined) ?? randomUUID();
    const payload = { ...body, command_key };
    try {
      return {
        command_key,
        ...(await this.request<{ id: string }>("POST", path, { body: payload })),
      };
    } catch (error) {
      if (error instanceof ApiError && error.status < 500) throw error;
      const recovered = await this.request<{ id: string | null }>(
        "GET",
        `/bookings/commands/${command_key}`,
      ).catch(() => ({ id: null }));
      if (recovered.id) return { command_key, ...recovered };
      throw new Error(
        `${(error as Error).message}. The outcome is uncertain; retry with the same command_key ${command_key} and identical inputs.`,
      );
    }
  }
}
