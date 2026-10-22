import {
  BadRequestException,
  ServiceUnavailableException,
} from "@nestjs/common";

export const MCP = "https://mcp.sarvam.ai/voice-agents";
type Json = Record<string, any>;

/** Supported Sarvam OAuth + Streamable HTTP MCP interface; no dashboard cookies. */
export class SarvamAuthoring {
  private deadline = Date.now() + 14000;
  constructor(
    private http: typeof fetch,
    private token = "",
  ) {}
  private async request(
    url: string,
    init: RequestInit,
    registrationRedirectUri?: string,
  ) {
    let response: Response;
    try {
      response = await this.http(url, {
        ...init,
        redirect: "error",
        signal: AbortSignal.timeout(Math.max(1, this.deadline - Date.now())),
      });
    } catch {
      throw new ServiceUnavailableException(
        "Sarvam did not respond. Retry setup to resume.",
      );
    }
    if (response.status === 401 || response.status === 403)
      throw new BadRequestException(
        "Sarvam authorization expired or lacks permission. Connect again to authorize.",
      );
    if (response.status === 400) {
      // Match only known provider error codes. Descriptions may echo credentials
      // or request bodies, so they must never be logged or returned to Flutter.
      const failure = await response.json().catch(() => null);
      if (registrationRedirectUri) {
        if (failure?.error === "invalid_redirect_uri")
          throw new BadRequestException(
            `Sarvam has not approved this app's sign-in callback. Ask Sarvam to allow-list this exact URL, then retry Connect: ${registrationRedirectUri}`,
          );
        throw new BadRequestException(
          "Sarvam rejected OAuth client registration. Ask Sarvam to confirm BookingOS registration requirements or provide an approved client ID for the booking server.",
        );
      }
      if (url === `${MCP}/token`)
        throw new BadRequestException(
          "Sarvam authorization expired or could not be completed. Press Connect to start a new sign-in.",
        );
      throw new BadRequestException(
        "Sarvam rejected the authoring request (400). Check MCP compatibility for the current setup step.",
      );
    }
    if (!response.ok)
      throw new ServiceUnavailableException(
        `Sarvam setup request failed (${response.status}). Retry or check workspace permissions.`,
      );
    return response;
  }
  async register(redirectUri: string) {
    return (
      await this.request(
        `${MCP}/register`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            client_name: "BookingOS",
            redirect_uris: [redirectUri],
            grant_types: ["authorization_code"],
            response_types: ["code"],
            token_endpoint_auth_method: "none",
          }),
        },
        redirectUri,
      )
    ).json() as Promise<Json>;
  }
  async exchange(fields: Record<string, string>) {
    const result = (await (
      await this.request(`${MCP}/token`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ ...fields, resource: MCP }).toString(),
      })
    ).json()) as Json;
    if (
      typeof result.access_token !== "string" ||
      result.token_type?.toLowerCase() !== "bearer"
    )
      throw new ServiceUnavailableException(
        "Sarvam returned an invalid authorization response.",
      );
    return result;
  }
  private async rpc(method: string, params: Json, session?: string) {
    const id = crypto.randomUUID();
    const response = await this.request(MCP, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.token}`,
        "Content-Type": "application/json",
        Accept: "application/json, text/event-stream",
        "MCP-Protocol-Version": "2025-03-26",
        ...(session ? { "Mcp-Session-Id": session } : {}),
      },
      body: JSON.stringify({ jsonrpc: "2.0", id, method, params }),
    });
    let data: Json | undefined;
    if (response.headers.get("content-type")?.includes("text/event-stream")) {
      const reader = response.body!.getReader();
      const decoder = new TextDecoder();
      let buffer = "",
        size = 0;
      try {
        while (!data) {
          const part = await reader.read();
          if (part.done) break;
          size += part.value.length;
          if (size > 2 * 1024 * 1024) throw new Error("Response too large");
          buffer = (
            buffer + decoder.decode(part.value, { stream: true })
          ).replace(/\r\n/g, "\n");
          let boundary: number;
          while ((boundary = buffer.indexOf("\n\n")) >= 0) {
            const event = buffer.slice(0, boundary);
            buffer = buffer.slice(boundary + 2);
            const value = event
              .split("\n")
              .filter((l) => l.startsWith("data:"))
              .map((l) => l.slice(5).trimStart())
              .join("\n");
            if (!value) continue;
            const message = JSON.parse(value);
            if (message.id === id) {
              data = message;
              break;
            }
          }
        }
      } finally {
        await reader.cancel();
      }
    } else data = (await response.json()) as Json;
    if (!data || data.error)
      throw new ServiceUnavailableException(
        "Sarvam could not complete the authoring operation. Check workspace permissions and retry.",
      );
    return {
      result: data.result as Json,
      session: response.headers.get("mcp-session-id") ?? session,
    };
  }
  private async session() {
    const initialized = await this.rpc("initialize", {
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: { name: "bookingos", version: "1.0.0" },
    });
    await this.request(MCP, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.token}`,
        "Content-Type": "application/json",
        Accept: "application/json, text/event-stream",
        "MCP-Protocol-Version": "2025-03-26",
        ...(initialized.session
          ? { "Mcp-Session-Id": initialized.session }
          : {}),
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: "notifications/initialized",
      }),
    });
    return initialized.session;
  }
  async capabilities() {
    const session = await this.session();
    const { result } = await this.rpc("tools/list", {}, session);
    return result.tools as Json[];
  }
  async call(name: string, args: Json): Promise<Json> {
    const session = await this.session();
    const { result } = await this.rpc(
      "tools/call",
      { name, arguments: args },
      session,
    );
    if (result.isError)
      throw new BadRequestException(
        "Sarvam refused this setup step. Check agent permissions and configuration, then retry.",
      );
    let value: Json = result.structuredContent;
    if (!value) {
      const content = result.content?.find(
        (c: Json) => c.type === "text",
      )?.text;
      try {
        value = JSON.parse(content);
      } catch {
        throw new ServiceUnavailableException(
          "Sarvam returned an unreadable setup result.",
        );
      }
    }
    if (value.validation?.length || value.not_applied?.length)
      throw new BadRequestException(
        "Sarvam did not apply all setup fields. Review the agent configuration and retry.",
      );
    return value;
  }
}
