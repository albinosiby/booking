import "reflect-metadata";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { SarvamService } from "../src/sarvam/sarvam.service";
import {
  AdminMcpAuthService,
  hashAdminMcpToken,
  ADMIN_MCP_SCOPES,
} from "../src/admin/admin-mcp-auth";
import { AdminMcpService } from "../src/admin/admin-mcp.service";
import { openSecret } from "../src/sarvam/sarvam-secrets";
delete process.env.DATABASE_URL;
Object.assign(process.env, {
  NODE_ENV: "test",
  PGLITE_PATH: "memory://",
  BOOKING_SECRETS_KEY: Buffer.alloc(32, 19).toString("base64"),
});
const db = new Database(),
  workspace = new WorkspaceService(db),
  provider = new SarvamService(db, workspace),
  service = new AdminMcpService(db, provider, workspace),
  auth = new AdminMcpAuthService(db);
workspace.publicAppUrl = "https://api.example.test/functions/v1/booking-api";
let actor: any, other: any;
let actualVersion = 7;
before(async () => {
  await db.onModuleInit();
  async function operator() {
    const id = randomUUID(),
      token = "bkam_" + randomBytes(32).toString("base64url");
    await db.query(
      "INSERT INTO admin_mcp_credentials(id,name,operator_email,issued_by,token_hash,token_prefix,scopes,expires_at) VALUES($1,'Test MCP',$2,'test',$3,$4,$5,now()+interval '1 day')",
      [
        id,
        `${id}@example.com`,
        hashAdminMcpToken(token),
        token.slice(0, 10),
        [...ADMIN_MCP_SCOPES],
      ],
    );
    return auth.authenticate(`Bearer ${token}`, "voice:write");
  }
  actor = await operator();
  other = await operator();
  provider.http = async (input) => {
    const url = new URL(String(input));
    assert.equal(url.origin, "https://apps.sarvam.ai");
    if (url.pathname.includes("/deployments/"))
      return Response.json({
        deployment_id: "deployment-1",
        app_id: "agent-1",
        app_version: actualVersion,
        status: "active",
        channel_direction: "inbound",
        connection_configs: [
          { connection_id: "connection-1", phone_numbers: ["+919876543210"] },
        ],
      });
    if (url.pathname.endsWith("/interactions"))
      return Response.json({ total: 0, items: [] });
    throw new Error("Unexpected provider request");
  };
});
after(() => db.onModuleDestroy());
async function tenant(name = "MCP Arena") {
  const owner = {
    uid: randomUUID(),
    email: `${randomUUID()}@example.com`,
    name: "Owner",
  };
  await workspace.createOrganization(owner, {
    name,
    contact_phone: "9876543210",
    currency: "INR",
    location: {
      name: "Main",
      address_line_1: "Road",
      address_line_2: null,
      city: "Kochi",
      state_code: "KL",
      country_code: "IN",
      postal_code: "682001",
      timezone: "Asia/Kolkata",
    },
  });
  const m = await workspace.member(owner),
    org = m.organization_id as string;
  await db.query(
    "INSERT INTO agent_call_requests(id,organization_id,membership_id,requested_services,note) VALUES($1,$2,$3,$4,'English booking and rescheduling')",
    [randomUUID(), org, m.id, ["booking", "rescheduling"]],
  );
  return { org, owner };
}
async function plan(org: string, phone = "+919876543210") {
  const detail = await service.get(actor, org);
  return service.prepare(actor, org, {
    request_version: detail.request.version,
    integration_version: detail.connection.version,
    approved_services: ["booking", "rescheduling"],
    phone_number: phone,
    connection_id: "connection-1",
    sarvam_org_id: "provider-org",
    workspace_id: "workspace-1",
    language: "en-IN",
    template_agent_id: "template-1",
    template_version: 1,
    template_language: "en-IN",
    template_language_path: "speech_config.language",
    template_language_value: "en-IN",
    initial_state: "main",
  });
}
async function start(org: string, phone?: string) {
  const prepared = await plan(org, phone);
  const input = {
    plan_id: prepared.plan_id,
    plan: prepared.plan,
    idempotency_key: randomUUID(),
    workspace_api_key: "private-workspace-key",
  };
  return { job: (await service.start(actor, org, input))!, input };
}
async function advance(
  org: string,
  job: any,
  resources: any = {},
  receipt?: any,
) {
  const leased = await service.claim(actor, org, {
    job_id: job.job_id,
    version: job.version,
  });
  return service.checkpoint(actor, org, {
    job_id: job.job_id,
    version: leased.version,
    lease_id: leased.lease_id,
    step: leased.step,
    resources,
    receipt,
  });
}
test("prepare snapshots only approved tools; signed plans reject changes and stale versions", async () => {
  const t = await tenant("Plan arena"),
    p = await plan(t.org, "+919800000001");
  assert.equal(p.spec.tools.length, 6);
  assert.ok(!p.spec.tools.some((t) => t.name.includes("cancel")));
  assert.ok(p.spec.prompt.includes("English"));
  await assert.rejects(
    service.start(actor, t.org, {
      plan_id: p.plan_id,
      plan: { ...p.plan, phone_number: "+919800000002" },
      idempotency_key: randomUUID(),
      workspace_api_key: "private-workspace-key",
    }),
    /plan does not match/,
  );
  await assert.rejects(
    service.start(other, t.org, {
      plan_id: p.plan_id,
      plan: p.plan,
      idempotency_key: randomUUID(),
      workspace_api_key: "private-workspace-key",
    }),
    /plan does not match/,
  );
  await db.query(
    "UPDATE agent_call_requests SET version=version+1 WHERE organization_id=$1",
    [t.org],
  );
  await assert.rejects(
    service.start(actor, t.org, {
      plan_id: p.plan_id,
      plan: p.plan,
      idempotency_key: randomUUID(),
      workspace_api_key: "private-workspace-key",
    }),
    /changed/,
  );
  assert.equal((await service.get(actor, t.org)).job, null);
});
test("start is idempotent, reserves the line, prevents unapproved services and leaks no secrets", async () => {
  const t = await tenant("Reservation arena"),
    started = await start(t.org, "+919800000003");
  const repeated = await service.start(actor, t.org, started.input);
  assert.equal(repeated!.job_id, started.job.job_id);
  assert.ok(!JSON.stringify(repeated).includes("private-workspace-key"));
  assert.equal(repeated!.client_enabled, false);
  const s = (
    await db.query<any>(
      "SELECT api_key_ciphertext FROM sarvam_integrations WHERE organization_id=$1",
      [t.org],
    )
  ).rows[0];
  assert.equal(openSecret(s.api_key_ciphertext), "private-workspace-key");
  const second = await tenant("Another arena");
  await assert.rejects(
    plan(second.org, "+919800000003"),
    /assigned to another/,
  );
  const detail = await service.get(actor, second.org);
  const good = await plan(second.org, "+919800000004");
  const {
    principal_id,
    organization_id,
    request_id,
    expires_at,
    ...prepareInput
  } = good.plan;
  await assert.rejects(
    service.prepare(actor, second.org, {
      ...prepareInput,
      approved_services: ["cancellation"],
    }),
    /only services requested/,
  );
  assert.equal(detail.connection.version, 0);
});
test("expired leases and uncertain failures preserve the existing job and resource references", async () => {
  const t = await tenant("Recovery arena");
  let { job } = await start(t.org, "+919800000009");
  const first = await service.claim(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
  });
  await db.query(
    "UPDATE sarvam_integrations SET setup_lease_until=now()-interval '1 second' WHERE organization_id=$1",
    [t.org],
  );
  await assert.rejects(
    service.checkpoint(actor, t.org, {
      job_id: job.job_id,
      version: job.version,
      lease_id: first.lease_id,
      step: "agent",
      resources: { agent_id: "expired-agent" },
    }),
    /lease expired/,
  );
  const second = await service.claim(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
  });
  job = (await service.checkpoint(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
    lease_id: second.lease_id,
    step: "agent",
    resources: { agent_id: "recovered-agent" },
  }))!;
  const third = await service.claim(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
  });
  job = (await service.release(actor, t.org, {
    job_id: job.job_id,
    lease_id: third.lease_id,
    error_code: "OUTCOME_UNKNOWN",
  }))!;
  assert.equal(job.step, "credential");
  assert.equal(job.error_code, "OUTCOME_UNKNOWN");
  assert.equal(job.resources.agent_id, "recovered-agent");
  const fourth = await service.claim(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
  });
  await assert.rejects(
    service.checkpoint(actor, t.org, {
      job_id: job.job_id,
      version: job.version,
      lease_id: fourth.lease_id,
      step: "credential",
      resources: { agent_id: "replacement-agent", secret_id: "anything" },
    }),
    /reference cannot be changed/,
  );
  const result = await service.job(actor, t.org);
  assert.equal(result!.job_id, job.job_id);
  assert.equal(result!.resources.agent_id, "recovered-agent");
  await assert.rejects(
    service.release(actor, t.org, {
      job_id: job.job_id,
      lease_id: fourth.lease_id,
      error_code: "secret-value-in-error",
    }),
    /Invalid admin MCP request/,
  );
});
test("leases prevent racing; credential delivery is idempotent, scoped and absent from safe output", async () => {
  const t = await tenant("Credential arena"),
    started = await start(t.org, "+919800000005"),
    job = started.job;
  const claimed = await service.claim(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
  });
  await assert.rejects(
    service.claim(actor, t.org, { job_id: job.job_id, version: job.version }),
    /Another connection step/,
  );
  await assert.rejects(
    service.checkpoint(actor, t.org, {
      job_id: job.job_id,
      version: job.version,
      lease_id: claimed.lease_id,
      step: "agent",
      resources: {},
    }),
    /provider reference/,
  );
  let next = (await service.checkpoint(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
    lease_id: claimed.lease_id,
    step: "agent",
    resources: { agent_id: "credential-agent" },
  }))!;
  const credentialLease = await service.claim(actor, t.org, {
      job_id: next.job_id,
      version: next.version,
    }),
    operation_key = randomUUID();
  const input = {
    job_id: next.job_id,
    lease_id: credentialLease.lease_id!,
    operation_key,
  };
  const one = await service.credential(actor, t.org, input),
    two = await service.credential(actor, t.org, input);
  assert.equal(one.tool_key, two.tool_key);
  await assert.rejects(
    service.credential(other, t.org, input),
    /another automation principal/,
  );
  await assert.rejects(
    service.credential(actor, t.org, { ...input, operation_key: randomUUID() }),
    /Reuse the saved/,
  );
  const safe = await service.job(actor, t.org);
  assert.ok(!JSON.stringify(safe).includes(one.tool_key));
  assert.equal(safe!.credential_operation, operation_key);
  next = (await service.checkpoint(actor, t.org, {
    job_id: next.job_id,
    version: next.version,
    lease_id: credentialLease.lease_id,
    step: "credential",
    resources: { secret_id: "isolated-secret" },
    receipt: { credential_verified: true },
  }))!;
  assert.equal(next.step, "tool_0");
  await assert.rejects(
    service.credential(actor, t.org, input),
    /lease expired|only during credential/i,
  );
  const audit = (
    await db.query<any>(
      "SELECT admin_email,detail FROM admin_audit_log WHERE target_id=$1",
      [t.org],
    )
  ).rows;
  assert.ok(audit.every((a) => a.admin_email === actor.email));
  assert.ok(!JSON.stringify(audit).includes(one.tool_key));
});
test("full checkpoint workflow refuses wrong deployment versions, activates safely and blocks key export afterward", async () => {
  const t = await tenant("Complete arena");
  let { job } = await start(t.org);
  job = (await advance(t.org, job, { agent_id: "agent-1", draft_version: 7 }))!;
  const c = await service.claim(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
  });
  await service.credential(actor, t.org, {
    job_id: job.job_id,
    lease_id: c.lease_id,
    operation_key: randomUUID(),
  });
  job = (await service.checkpoint(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
    lease_id: c.lease_id,
    step: "credential",
    resources: { secret_id: "secret-1" },
    receipt: { credential_verified: true },
  }))!;
  while (job.step.startsWith("tool_")) job = (await advance(t.org, job))!;
  job = (await advance(
    t.org,
    job,
    {},
    { tools_verified: true, language_verified: true },
  ))!;
  job = (await advance(t.org, job, { agent_version: 7 }))!;
  job = (await advance(t.org, job, { deployment_id: "deployment-1" }))!;
  assert.equal(job.step, "verify");
  const claim = await service.claim(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
  });
  const verify = {
    job_id: job.job_id,
    version: job.version,
    lease_id: claim.lease_id,
    tools_verified: true as const,
    credential_verified: true as const,
    language_verified: true as const,
    committed_version: 7,
    secret_id: "secret-1",
  };
  actualVersion = 6;
  await assert.rejects(
    service.verify(actor, t.org, verify),
    /another agent version/,
  );
  actualVersion = 7;
  job = (await service.verify(actor, t.org, verify))!;
  assert.equal(job.step, "activate");
  const activeLease = await service.claim(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
  });
  job = (await service.activate(actor, t.org, {
    job_id: job.job_id,
    version: job.version,
    lease_id: activeLease.lease_id,
  }))!;
  assert.equal(job.done, true);
  assert.equal(job.client_enabled, false);
  const saved = (
    await db.query<any>(
      "SELECT s.enabled,s.verified_at,s.tool_key_ciphertext,r.status FROM sarvam_integrations s JOIN agent_call_requests r USING(organization_id) WHERE s.organization_id=$1",
      [t.org],
    )
  ).rows[0];
  assert.equal(saved.status, "active");
  assert.equal(saved.enabled, false);
  assert.ok(saved.verified_at);
  assert.equal(saved.tool_key_ciphertext, null);
  const detail = await service.get(actor, t.org);
  await service.pause(actor, t.org, {
    request_version: detail.request.version,
  });
  assert.equal((await service.get(actor, t.org)).request.status, "paused");
});
