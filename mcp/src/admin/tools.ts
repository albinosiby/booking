import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { AdminMcpError, safeOutput } from "./client.js";
import { AdminWorkflow } from "./workflow.js";
import { SarvamTokenStore } from "./sarvam-auth.js";

export const ADMIN_INSTRUCTIONS =
  "BookingOS voice administration only. Resolve the named request with list_connection_requests then get_connection_request. Run preflight_connection before preparing or starting. Approve only requested services and use an explicitly selected available phone. prepare_connection returns a signed plan; start_connection starts that plan. Continue resume_connection until done; each call performs one leased step. Do not stop after merely starting a job. Never make bookings or calls, transfer an occupied number, return credentials, extract other MCP tokens or use browser configuration as a fallback. Sarvam MCP in Codex is separately authorized from this private installer; use its tools for inventory/diagnostics, but do not race this saved setup job with manual edits. On PROVIDER_AUTH_REQUIRED, run the documented private login outside this tool then resume. On OUTCOME_UNKNOWN, read the same job and resume it; never create another job to retry. Final Connected keeps client booking off pending client space selection. Report setup results separately from a real call test.";

const orgSchema = {
  organization_id: z
    .uuid()
    .describe(
      "Stable organization ID from list_connection_requests; resolve ambiguous names first.",
    ),
};
const read = {
  readOnlyHint: true,
  destructiveHint: false,
  openWorldHint: true,
};
const write = {
  readOnlyHint: false,
  destructiveHint: false,
  openWorldHint: true,
};
const result = (data: unknown) => ({
  content: [
    { type: "text" as const, text: JSON.stringify(safeOutput(data), null, 2) },
  ],
});
export async function adminToolRun(fn: () => Promise<unknown>) {
  try {
    return result(await fn());
  } catch (e) {
    const auth = (e as { code?: string })?.code === "PROVIDER_AUTH_REQUIRED";
    const code =
      e instanceof AdminMcpError
        ? e.code
        : auth
          ? "PROVIDER_AUTH_REQUIRED"
          : "SETUP_FAILED";
    const message =
      e instanceof AdminMcpError
        ? e.message
        : auth
          ? "Run the private Sarvam installer login command, then resume the saved job."
          : "Setup did not complete. Read the saved job and private setup documentation; no raw provider diagnostic is returned.";
    return { isError: true, ...result({ code, message }) };
  }
}

export function registerAdminTools(server: McpServer, workflow: AdminWorkflow) {
  const api = workflow.api;
  server.registerTool(
    "get_setup_status",
    {
      title: "Admin MCP setup status",
      description:
        "Safe installation status only; never exposes credentials or starts sign-in.",
      annotations: read,
    },
    () =>
      adminToolRun(async () => ({
        admin_token_configured: !!api.config.token,
        template_configured: !!(
          api.config.templateAgentId &&
          api.config.templateVersion &&
          api.config.templateLanguage &&
          api.config.templateLanguagePath &&
          api.config.templateLanguageValue
        ),
        sarvam_installer: await new SarvamTokenStore(
          process.env.BOOKINGOS_SARVAM_TOKEN_FILE,
        ).status(),
        instructions:
          "Follow docs/bookingos-admin-mcp.md for private installation/login. Both authorizations and provider capabilities must pass before setup.",
      })),
  );
  server.registerTool(
    "list_connection_requests",
    {
      title: "Find call-service requests",
      description:
        "Resolve a client organization name, requested services, status and stable IDs. A name can match multiple organizations; do not guess.",
      inputSchema: {
        name: z.string().trim().max(200).optional(),
        status: z
          .enum([
            "requested",
            "in_review",
            "setting_up",
            "active",
            "paused",
            "rejected",
          ])
          .optional(),
        limit: z.number().int().min(1).max(100).default(30),
      },
      annotations: read,
    },
    (query) =>
      adminToolRun(() => api.request("GET", "/requests", undefined, query)),
  );
  server.registerTool(
    "get_connection_request",
    {
      title: "Read the client connection request",
      description:
        "Read client requirements, approved services, safe current connection, versions and existing job. No secret values.",
      inputSchema: orgSchema,
      annotations: read,
    },
    ({ organization_id }) =>
      adminToolRun(() => api.request("GET", `/requests/${organization_id}`)),
  );
  server.registerTool(
    "preflight_connection",
    {
      title: "Check connection prerequisites",
      description:
        "Read-only check of private provider authorization, secret-install capabilities, pinned empty template/native language, workspace and onboarded number inventory. Makes no setup allocations.",
      inputSchema: {
        ...orgSchema,
        language: z
          .string()
          .regex(/^[a-z]{2}(?:-[A-Z]{2})?$/)
          .optional(),
      },
      annotations: read,
    },
    ({ organization_id, language }) =>
      adminToolRun(() => workflow.preflight(organization_id, language)),
  );
  server.registerTool(
    "prepare_connection",
    {
      title: "Prepare the exact call-service connection",
      description:
        "Create a signed, expiring plan after provider preflight. Choose only services requested by the client and an explicitly selected free number. Template fields are inserted privately from the reviewed installation manifest.",
      inputSchema: {
        ...orgSchema,
        request_version: z.number().int().nonnegative(),
        integration_version: z.number().int().nonnegative(),
        approved_services: z
          .array(z.enum(["booking", "rescheduling", "enquiry", "cancellation"]))
          .min(1)
          .max(4),
        phone_number: z.string().regex(/^\+[1-9][0-9]{7,14}$/),
        connection_id: z.string().min(1).max(200),
        sarvam_org_id: z.uuid(),
        workspace_id: z.uuid(),
        language: z.string().regex(/^[a-z]{2}(?:-[A-Z]{2})?$/),
      },
      annotations: read,
    },
    ({ organization_id, ...fields }) =>
      adminToolRun(() => workflow.prepare(organization_id, fields)),
  );
  server.registerTool(
    "start_connection",
    {
      title: "Start the approved connection plan",
      description:
        "Reserve the exact plan and start a durable setup job. Does not transfer occupied numbers or switch client booking on. Continue resume_connection until done; keep the same idempotency key on uncertain outcome.",
      inputSchema: {
        ...orgSchema,
        plan_id: z.string().min(1).max(200),
        plan: z.record(z.string(), z.unknown()),
        idempotency_key: z.uuid(),
      },
      annotations: write,
    },
    ({ organization_id, ...fields }) =>
      adminToolRun(() => workflow.start(organization_id, fields)),
  );
  server.registerTool(
    "get_connection_job",
    {
      title: "Read setup progress and recovery state",
      description:
        "Read the existing saved job/checkpoint without credentials. Read this after any uncertain result; resume the same job.",
      inputSchema: orgSchema,
      annotations: read,
    },
    ({ organization_id }) =>
      adminToolRun(() => api.request("GET", `/jobs/${organization_id}`)),
  );
  server.registerTool(
    "resume_connection",
    {
      title: "Run the next saved setup step",
      description:
        "Perform one leased provider/setup step, safely installing secrets internally and verifying committed config. Repeat until done. Never returns raw keys. Missing/expired Sarvam authorization requires the private CLI login, not an admin callback.",
      inputSchema: orgSchema,
      annotations: write,
    },
    ({ organization_id }) =>
      adminToolRun(() => workflow.resume(organization_id)),
  );
  for (const [name, step, title] of [
    [
      "install_tool_credential",
      "credential",
      "Install the job credential privately",
    ],
    ["verify_connection", "verify", "Verify the committed client connection"],
    ["activate_connection", "activate", "Mark the verified request Connected"],
  ] as const) {
    server.registerTool(
      name,
      {
        title,
        description: `Perform only the saved ${step} step, with the same safeguards as resume_connection. Credentials remain inside the trusted adapter. Client booking remains off.`,
        inputSchema: orgSchema,
        annotations: write,
      },
      ({ organization_id }) =>
        adminToolRun(async () => {
          const response = await api.request("GET", `/jobs/${organization_id}`);
          const job = response.job ?? response;
          if (job?.step !== step)
            throw new AdminMcpError(
              "REQUEST_REJECTED",
              `This job is not at the ${step} step. Use get_connection_job and resume_connection.`,
            );
          return workflow.resume(organization_id);
        }),
    );
  }
  server.registerTool(
    "pause_connection",
    {
      title: "Pause this client call service",
      description:
        "Immediately block this organization’s call-service actions and pause its request. Does not delete a provider deployment or transfer its number.",
      inputSchema: {
        ...orgSchema,
        request_version: z.number().int().positive(),
        reason: z.string().trim().min(2).max(500),
      },
      annotations: write,
    },
    ({ organization_id, ...body }) =>
      adminToolRun(() =>
        api.request("POST", `/requests/${organization_id}/pause`, body),
      ),
  );
  server.registerResource(
    "connection_workflow",
    "bookingos-admin://voice/connection-workflow",
    {
      title: "BookingOS and Sarvam connection workflow",
      mimeType: "text/plain",
    },
    async (uri) => ({
      contents: [
        { uri: uri.href, mimeType: "text/plain", text: ADMIN_INSTRUCTIONS },
      ],
    }),
  );
}
