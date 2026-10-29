import { createHash, randomUUID } from "node:crypto";
import { AdminClient, AdminMcpError, type Json } from "./client.js";
import { SarvamProvider } from "./provider.js";
import { createSarvamClient } from "./sarvam-auth.js";

export type ProviderSession = {
  provider: SarvamProvider;
  close(): Promise<void>;
};
export type SessionFactory = () => Promise<ProviderSession>;

export class AdminWorkflow {
  constructor(
    readonly api: AdminClient,
    private sessions: SessionFactory = async () => {
      const session = await createSarvamClient({
        tokenFile: process.env.BOOKINGOS_SARVAM_TOKEN_FILE,
      });
      return {
        provider: new SarvamProvider(session.client),
        close: session.close,
      };
    },
    private http: typeof fetch = fetch,
  ) {}

  private templateConfig(language?: string) {
    const c = this.api.config;
    if (
      !c.templateAgentId ||
      !c.templateVersion ||
      !c.templateLanguage ||
      !c.templateLanguagePath ||
      !c.templateLanguageValue
    )
      throw new AdminMcpError(
        "TEMPLATE_REQUIRED",
        "Set the reviewed committed template ID/version, language, native language field path and value in the private admin configuration.",
      );
    if (language && language !== c.templateLanguage)
      throw new AdminMcpError(
        "TEMPLATE_LANGUAGE_MISMATCH",
        "The requested language differs from the reviewed template. Select a matching committed template before setup.",
      );
    return {
      id: c.templateAgentId,
      version: c.templateVersion,
      language: c.templateLanguage,
      language_path: c.templateLanguagePath,
      language_value: c.templateLanguageValue,
    };
  }
  private unwrap(value: Json) {
    return value.job ?? value;
  }
  private async provider<T>(fn: (p: SarvamProvider) => Promise<T>) {
    const session = await this.sessions();
    try {
      await session.provider.inspect();
      return await fn(session.provider);
    } finally {
      await session.close();
    }
  }
  async preflight(org: string, language?: string) {
    const request = await this.api.request("GET", `/requests/${org}`);
    const template = this.templateConfig(language);
    return this.provider(async (p) => {
      const a = await p.agent(template.id, template.version);
      const scope = [a.config.org_id, a.config.workspace_id];
      if (scope.some((x) => typeof x !== "string" || !x))
        throw new AdminMcpError(
          "WORKSPACE_MISMATCH",
          "Template workspace identity was not returned.",
        );
      const existing = request.connection ?? {};
      if (
        (existing.sarvam_org_id && existing.sarvam_org_id !== scope[0]) ||
        (existing.workspace_id && existing.workspace_id !== scope[1])
      )
        throw new AdminMcpError(
          "WORKSPACE_MISMATCH",
          "The Sarvam workspace differs from the request connection.",
        );
      const checked = await p.template(template.id, template.version, scope, {
        path: template.language_path,
        value: template.language_value,
      });
      const inventory = await p.inventory();
      return {
        organization_id: org,
        request,
        provider_capabilities_verified: true,
        sarvam_org_id: scope[0],
        workspace_id: scope[1],
        template: { ...template, initial_state: checked.initial },
        numbers: inventory.numbers.map((n) => ({
          ...n,
          assigned: inventory.deployments.some((d: Json) =>
            (d.connection_configs ?? []).some((c: Json) =>
              c.phone_numbers?.includes(n.phone_number),
            ),
          ),
        })),
        next_action:
          "Choose an available onboarded number; prepare_connection with the returned versions, workspace and language. No live setup changes have been made.",
      };
    });
  }
  async prepare(org: string, fields: Json) {
    const preflight = await this.preflight(org, fields.language);
    if (
      fields.sarvam_org_id !== preflight.sarvam_org_id ||
      fields.workspace_id !== preflight.workspace_id
    )
      throw new AdminMcpError(
        "WORKSPACE_MISMATCH",
        "Use the workspace returned by preflight_connection.",
      );
    const number = preflight.numbers.find(
      (n: Json) =>
        n.phone_number === fields.phone_number &&
        n.connection_id === fields.connection_id,
    );
    if (!number || number.assigned)
      throw new AdminMcpError(
        "NUMBER_IN_USE",
        "Choose an available number returned by preflight. This workflow does not transfer assigned numbers.",
      );
    return this.api.request("POST", `/requests/${org}/prepare`, {
      ...fields,
      template_agent_id: preflight.template.id,
      template_version: preflight.template.version,
      template_language: preflight.template.language,
      template_language_path: preflight.template.language_path,
      template_language_value: preflight.template.language_value,
      initial_state: preflight.template.initial_state,
    });
  }
  async start(org: string, fields: Json) {
    // Revalidate immediately before the first write; plans and provider inventory can change.
    const plan = fields.plan;
    if (!plan || plan.organization_id !== org)
      throw new AdminMcpError(
        "STALE_PLAN",
        "Use the complete saved plan returned by prepare_connection.",
      );
    const fresh = await this.preflight(org, plan.language);
    if (
      fresh.sarvam_org_id !== plan.sarvam_org_id ||
      fresh.workspace_id !== plan.workspace_id ||
      fresh.template.id !== plan.template_agent_id ||
      fresh.template.version !== plan.template_version
    )
      throw new AdminMcpError(
        "STALE_PLAN",
        "The reviewed provider workspace or template changed. Prepare a fresh plan.",
      );
    if (
      !fresh.numbers.some(
        (n: Json) =>
          n.connection_id === plan.connection_id &&
          n.phone_number === plan.phone_number &&
          !n.assigned,
      )
    )
      throw new AdminMcpError(
        "NUMBER_IN_USE",
        "The selected number is no longer available. No reservation was made.",
      );
    return this.api.request("POST", `/requests/${org}/start`, {
      ...fields,
      ...(this.api.config.workspaceApiKey
        ? { workspace_api_key: this.api.config.workspaceApiKey }
        : {}),
    });
  }
  private async catalogCredentialCheck(job: Json, key: string) {
    const catalog = job.spec?.tools?.find(
      (t: Json) => t.config?.lifecycle === "on_start",
    );
    const target = new URL(catalog?.config?.url ?? "");
    const backend = new URL(this.api.config.apiUrl);
    // A specification cannot turn the installer into an arbitrary key-forwarding proxy.
    const expectedPath = backend.pathname.replace(
      /\/v1\/admin-mcp\/voice$/,
      "/voice/v1/catalog",
    );
    if (
      !backend.pathname.endsWith("/v1/admin-mcp/voice") ||
      target.origin !== backend.origin ||
      target.pathname !== expectedPath ||
      target.username ||
      target.password ||
      target.search ||
      target.hash
    )
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "The catalog credential check must target this BookingOS backend.",
      );
    let response: Response;
    try {
      response = await this.http(target, {
        method: "POST",
        redirect: "error",
        signal: AbortSignal.timeout(12000),
        headers: { "content-type": "application/json", "X-API-Key": key },
        body: "{}",
      });
    } catch {
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "The read-only catalog credential check did not return. Resume the saved job.",
      );
    }
    const data = await response.json().catch(() => null);
    if (
      response.status !== 403 ||
      data?.code !== "FORBIDDEN" ||
      data?.message !== "The voice agent is turned off."
    )
      throw new AdminMcpError(
        "VERIFICATION_FAILED",
        "The catalog did not confirm a valid key with client booking switched off.",
      );
    return true;
  }
  /** Performs one leased step. Codex continues calling until state is done. */
  async resume(org: string) {
    let job = this.unwrap(await this.api.request("GET", `/jobs/${org}`));
    if (!job)
      throw new AdminMcpError(
        "REQUEST_REJECTED",
        "No saved setup job exists. Prepare and start the connection first.",
      );
    if (job.step === "done") return job;
    const planTemplate = job.plan;
    const template = {
      id: planTemplate?.template_agent_id,
      version: planTemplate?.template_version,
      language_path: planTemplate?.template_language_path,
      language_value: planTemplate?.template_language_value,
    };
    if (
      !template.id ||
      !template.version ||
      !template.language_path ||
      !template.language_value
    )
      throw new AdminMcpError(
        "STALE_PLAN",
        "This job has no frozen reviewed template manifest.",
      );
    return this.provider(async (p) => {
      job = this.unwrap(
        await this.api.request("POST", `/jobs/${org}/claim`, {
          job_id: job.job_id,
          version: job.version,
        }),
      );
      const base = {
        job_id: job.job_id,
        version: job.version,
        lease_id: job.lease_id,
      };
      const plan = job.plan;
      const resources = job.resources ?? {};
      const scope = [plan.sarvam_org_id, plan.workspace_id];
      const updated: Json = {};
      const receipt: Json = {};
      try {
        const languageRule = {
          path: template.language_path,
          value: template.language_value,
        };
        const checked = await p.template(
          template.id,
          template.version,
          scope,
          languageRule,
        );
        const initial = checked.initial;
        if (initial !== plan.initial_state)
          throw new AdminMcpError(
            "STALE_PLAN",
            "The saved template initial state differs from the job plan.",
          );
        const confirmedNewOperation = job.error_code !== "OUTCOME_UNKNOWN";
        if (job.step === "agent") {
          const name =
            job.agent_name ?? `BookingOS ${org.slice(0, 8)} ${job.job_id}`;
          let id = resources.agent_id ?? (await p.findAgent(name));
          if (!id && !confirmedNewOperation)
            throw new AdminMcpError(
              "OUTCOME_UNKNOWN",
              "The previous agent creation has not appeared in read-back. No second agent was created.",
            );
          id ??= await p.createAgent(name, template.id, template.version);
          const a = await p.agent(id);
          p.assertScope(a.config, scope, id);
          updated.agent_id = id;
        } else if (job.step === "credential") {
          // Keep the raw value inside this process; never return this response to Codex.
          const credential = await this.api.request(
            "POST",
            `/jobs/${org}/credential`,
            {
              job_id: job.job_id,
              lease_id: job.lease_id,
              operation_key: job.credential_operation ?? randomUUID(),
            },
          );
          if (
            typeof credential.tool_key !== "string" ||
            !/^bkv_[A-Za-z0-9_-]+$/.test(credential.tool_key) ||
            typeof credential.secret_name !== "string"
          )
            throw new AdminMcpError(
              "VERIFICATION_FAILED",
              "Backend did not provide a valid private installation credential.",
            );
          updated.secret_id = await p.installSecret(
            credential.secret_name,
            credential.tool_key,
            confirmedNewOperation,
          );
          await this.catalogCredentialCheck(job, credential.tool_key);
          receipt.credential_verified = true;
        } else if (/^tool_\d+$/.test(job.step)) {
          const index = Number(job.step.slice(5));
          const spec = job.spec?.tools?.[index];
          if (!spec || !resources.agent_id || !resources.secret_id)
            throw new AdminMcpError(
              "VERIFICATION_FAILED",
              "Job tool or prerequisite references are missing.",
            );
          await p.addTool(
            resources.agent_id,
            spec,
            resources.secret_id,
            confirmedNewOperation,
          );
        } else if (job.step === "configure") {
          await p.configurePrompt(resources.agent_id, initial, job.spec);
          const c = await p.verifyTools(
            resources.agent_id,
            scope,
            initial,
            job.spec,
            resources.secret_id,
            undefined,
            languageRule,
          );
          updated.draft_version = c.app_version;
          receipt.tools_verified = true;
          receipt.language_verified = true;
          receipt.configuration_hash = createHash("sha256")
            .update(JSON.stringify(job.spec))
            .digest("hex");
        } else if (job.step === "commit") {
          await p.verifyTools(
            resources.agent_id,
            scope,
            initial,
            job.spec,
            resources.secret_id,
            resources.draft_version,
            languageRule,
          );
          updated.agent_version = await p.commit(
            resources.agent_id,
            resources.draft_version,
            confirmedNewOperation,
          );
        } else if (job.step === "deployment") {
          const d = await p.deploy(
            resources.agent_id,
            resources.agent_version,
            plan.connection_id,
            plan.phone_number,
            job.agent_name ?? `BookingOS ${job.job_id}`,
            confirmedNewOperation,
          );
          if (
            !p.matchesDeployment(
              d,
              resources.agent_id,
              resources.agent_version,
              plan.connection_id,
              plan.phone_number,
            ) ||
            d.status !== "active"
          )
            throw new AdminMcpError(
              "VERIFICATION_FAILED",
              "The new deployment is not active on the exact selected version and number.",
            );
          updated.deployment_id = d.deployment_id;
        } else if (job.step === "verify") {
          await p.verifyTools(
            resources.agent_id,
            scope,
            initial,
            job.spec,
            resources.secret_id,
            resources.agent_version,
            languageRule,
          );
          const d = await p.domain(
            "telephony",
            "get_deployment",
            resources.deployment_id,
          );
          if (
            !p.matchesDeployment(
              d,
              resources.agent_id,
              resources.agent_version,
              plan.connection_id,
              plan.phone_number,
            ) ||
            d.status !== "active"
          )
            throw new AdminMcpError(
              "VERIFICATION_FAILED",
              "Deployment changed before final verification.",
            );
          return await this.api.request("POST", `/jobs/${org}/verify`, {
            ...base,
            tools_verified: true,
            credential_verified: !!job.receipt?.credential_verified,
            language_verified: true,
            committed_version: resources.agent_version,
            secret_id: resources.secret_id,
          });
        } else if (job.step === "activate") {
          return await this.api.request("POST", `/jobs/${org}/activate`, base);
        } else
          throw new AdminMcpError(
            "VERIFICATION_FAILED",
            "Unknown saved setup step; no provider mutation was attempted.",
          );
        return await this.api.request("POST", `/jobs/${org}/checkpoint`, {
          ...base,
          step: job.step,
          resources: updated,
          receipt,
        });
      } catch (error) {
        const originalCode =
          error instanceof AdminMcpError
            ? error.code
            : (error as { code?: string })?.code === "PROVIDER_AUTH_REQUIRED"
              ? "PROVIDER_AUTH_REQUIRED"
              : "PROVIDER_ERROR";
        const code = [
          "PROVIDER_AUTH_REQUIRED",
          "PROVIDER_CAPABILITY_MISSING",
          "OUTCOME_UNKNOWN",
          "VERIFICATION_FAILED",
          "PROVIDER_ERROR",
          "STALE_PLAN",
        ].includes(originalCode)
          ? originalCode
          : "VERIFICATION_FAILED";
        await this.api
          .request("POST", `/jobs/${org}/release`, {
            job_id: job.job_id,
            lease_id: job.lease_id,
            error_code: code,
          })
          .catch(() => undefined);
        throw error;
      }
    });
  }
}
