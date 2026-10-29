import { test } from "node:test";
import assert from "node:assert/strict";
import type { CallService } from "../src/agent-calls/agent-call-policy";
import {
  BOOKING_PROMPT,
  bookingPromptForServices,
  bookingToolIndexes,
  TOOLS,
} from "../src/sarvam/sarvam-booking-config";
import {
  managedBookingSpecification,
  SarvamProvisioningRemote,
  type SarvamProvisioningClient,
} from "../src/sarvam/sarvam-provisioning-remote";

const baseUrl = "https://api.example.test/voice/v1";
const secretId = "__BOOKINGOS_SECRET_ID__";

test("each service receives only its required tools and matching prompt references", () => {
  const cases: [CallService[], number[]][] = [
    [["booking"], [0, 1, 2]],
    [["rescheduling"], [0, 1, 3, 4]],
    [["enquiry"], [0, 1]],
    [["cancellation"], [0, 3, 5]],
    [
      ["booking", "rescheduling"],
      [0, 1, 2, 3, 4],
    ],
  ];
  for (const [services, indexes] of cases) {
    const spec = managedBookingSpecification(services, { baseUrl, secretId });
    assert.deepEqual(bookingToolIndexes(services), indexes);
    assert.deepEqual(
      spec.tools.map((tool) => tool.name),
      [...indexes.map((index) => TOOLS[index][0]), "bookingos_call_completed"],
    );
    const referenced = [
      ...spec.prompt.matchAll(/tool:(bookingos_[a-z_]+)/g),
    ].map((match) => match[1]);
    assert.deepEqual(
      [...new Set(referenced)].sort(),
      indexes
        .slice(1)
        .map((index) => TOOLS[index][0])
        .sort(),
    );
  }
  assert.equal(bookingPromptForServices(), BOOKING_PROMPT);
});

test("English booking and rescheduling preserves trusted context, rupees and lifecycle mappings", () => {
  const spec = managedBookingSpecification(["booking", "rescheduling"], {
    baseUrl,
    secretId,
    language: "en-IN",
  });
  assert.equal(spec.tools.length, 6);
  assert.equal(spec.language, "en-IN");
  assert.match(spec.prompt, /conversation language is English/);
  assert.match(
    spec.prompt,
    /Only bookings originally made by call and belonging to this caller/,
  );
  assert.doesNotMatch(spec.prompt, /tool:bookingos_cancel_booking/);
  for (const { config } of spec.tools) {
    assert.deepEqual(config.auth, {
      type: "api_key",
      name: "X-API-Key",
      location: "header",
      value: { secret_id: secretId },
    });
    assert.equal(config.timeout_seconds, 12);
    for (const field of config.body)
      if (field.name === "caller_phone" || field.name === "interaction_id") {
        assert.equal(field.type, "system_variable");
        assert.equal(
          field.value.variable_name,
          field.name === "caller_phone" ? "user_identifier" : "interaction_id",
        );
      }
    if (config.lifecycle === "run")
      assert.equal(config.resp_template, "{{message}}");
  }
  const catalog = spec.tools[0].config;
  assert.equal(catalog.lifecycle, "on_start");
  assert.deepEqual(catalog.save_to_variables, [
    { response_path: "message", variable_name: "bookingos_spaces" },
  ]);
  assert.equal(catalog.resp_template, undefined);
  assert.match(
    spec.variables.bookingos_spaces.value,
    /unavailable until its live catalog has loaded/,
  );
  const book = spec.tools.find(
    (tool) => tool.name === "bookingos_book_slot",
  )!.config;
  for (const name of ["duration_minutes", "people", "expected_total"]) {
    const field = book.body.find((entry: any) => entry.name === name);
    assert.equal(field.param_type, "Number");
    assert.equal(field.required, true);
  }
  assert.match(
    book.body.find((entry: any) => entry.name === "expected_total").description,
    /numeric rupees/,
  );
  const completion = spec.tools.at(-1)!.config;
  assert.equal(completion.lifecycle, "on_end");
  assert.equal(completion.resp_template, undefined);
  assert.deepEqual(
    completion.body.slice(-2).map((field: any) => field.value.variable_name),
    ["call_duration_seconds", "interaction_transcript"],
  );
});

test("interrupted writes recover the original outcome without submitting another slot", () => {
  for (const prompt of [
    BOOKING_PROMPT,
    bookingPromptForServices(["booking", "rescheduling"], "en-IN"),
    bookingPromptForServices(["cancellation"]),
  ]) {
    assert.match(prompt, /pending, wait for that execution to finish/);
    assert.match(prompt, /interruption.*does not cancel the request/);
    assert.match(prompt, /must not trigger another write/);
    assert.match(
      prompt,
      /slot-conflict response after an earlier write attempt is an uncertain outcome/,
    );
    assert.match(prompt, /Do not say that nothing was booked or changed/);
    assert.match(
      prompt,
      /call tool:bookingos_my_bookings with trusted caller context/,
    );
    assert.match(
      prompt,
      /An absent match does not prove failure, especially after cancellation/,
    );
    assert.match(prompt, /retry the original action at most once.*unchanged/);
    assert.match(
      prompt,
      /genuinely different.*needs fresh explicit confirmation/,
    );
    assert.doesNotMatch(prompt, /A repeated request is declined/);
  }
});

test("booking-only recovery stays within its scope and mutation failures preserve uncertainty", () => {
  const spec = managedBookingSpecification(["booking"], { baseUrl, secretId });
  assert.deepEqual(bookingToolIndexes(["booking"]), [0, 1, 2]);
  assert.doesNotMatch(spec.prompt, /tool:bookingos_my_bookings/);
  assert.match(spec.prompt, /No booking-status lookup tool is available/);
  assert.match(
    spec.prompt,
    /After the pending execution finishes, retry the original action at most once/,
  );
  assert.match(
    spec.prompt,
    /If the original outcome cannot be recovered.*direct the caller to venue staff/,
  );
  const inquiryPrompt = bookingPromptForServices(["enquiry"]);
  assert.doesNotMatch(
    inquiryPrompt,
    /retry the original action|tool:bookingos_book_slot/,
  );
  for (const services of [
    ["booking"],
    ["rescheduling"],
    ["cancellation"],
  ] as CallService[][]) {
    const scoped = managedBookingSpecification(services, { baseUrl, secretId });
    const mutation = scoped.tools.find((tool) =>
      [
        "bookingos_book_slot",
        "bookingos_reschedule_booking",
        "bookingos_cancel_booking",
      ].includes(tool.name),
    )!;
    assert.match(mutation.config.on_failure, /may have completed/);
    assert.match(
      mutation.config.on_failure,
      /Recover its status before trying a different action/,
    );
    assert.doesNotMatch(
      mutation.config.on_failure,
      /nothing.*booked|did not go through|No successful/,
    );
  }
});

test("invalid scopes, ambiguous language strings and insecure API bases fail before configuration", () => {
  for (const services of [[], ["booking", "booking"], ["unsupported"]])
    assert.throws(() =>
      managedBookingSpecification(services as CallService[], {
        baseUrl,
        secretId,
      }),
    );
  assert.throws(() =>
    managedBookingSpecification(["booking"], {
      baseUrl,
      secretId,
      language: "use whatever caller says",
    }),
  );
  for (const unsafe of [
    "http://api.example.test",
    "https://user:password@api.example.test",
    "https://api.example.test?token=unsafe",
  ])
    assert.throws(() =>
      managedBookingSpecification(["booking"], { baseUrl: unsafe, secretId }),
    );
});

function providerFixture(services: CallService[] = ["booking"]) {
  const spec = managedBookingSpecification(services, { baseUrl, secretId });
  const schema = (properties: string[], operations?: string[]) => ({
    type: "object",
    properties: Object.fromEntries(
      properties.map((key) => [
        key,
        key === "operation" ? { enum: operations } : {},
      ]),
    ),
  });
  const capabilities: any[] = [
    {
      name: "agents",
      inputSchema: schema(
        ["operation", "id", "params", "fetch_all"],
        ["list", "get", "commit", "set_tools"],
      ),
    },
    {
      name: "telephony",
      inputSchema: schema(
        ["operation", "id", "params", "fetch_all"],
        [
          "list_connections",
          "list_endpoints",
          "list_deployments",
          "get_deployment",
        ],
      ),
    },
    { name: "secrets", inputSchema: schema(["operation"], ["list"]) },
    {
      name: "configure_agent",
      inputSchema: schema([
        "name",
        "clone_from",
        "clone_version",
        "agent_id",
        "config",
        "prompt",
      ]),
    },
    { name: "configure_secret", inputSchema: schema(["name", "value"]) },
    {
      name: "create_http_tool",
      inputSchema: schema([
        "agent_id",
        "name",
        "description",
        "tool_type",
        "connector_config",
      ]),
    },
    {
      name: "configure_deployment",
      inputSchema: schema(
        [
          "name",
          "app_id",
          "app_version",
          "connection_configs",
          "channel_direction",
          "operation",
        ],
        ["create"],
      ),
    },
  ];
  const agent: any = {
    config: {
      org_id: "org",
      workspace_id: "workspace",
      app_id: "agent",
      app_version: 1,
      llm_config: {
        agent_config: {
          states: {
            main: {
              instructions: spec.prompt,
              tool_names: spec.tools
                .filter((tool) => tool.config.lifecycle === "run")
                .map((tool) => tool.name),
            },
          },
        },
      },
    },
    tools: spec.tools.map((tool) => ({
      name: tool.name,
      enabled: true,
      connector_config: tool.config,
    })),
  };
  const calls: { name: string; args: any }[] = [];
  const client: SarvamProvisioningClient = {
    async capabilities() {
      return capabilities;
    },
    async call(name, args) {
      calls.push({ name, args });
      return name === "agents" && args.operation === "get" ? agent : {};
    },
  };
  return {
    capabilities,
    agent,
    calls,
    remote: new SarvamProvisioningRemote(client, { services }),
  };
}

test("preflight rejects a missing lifecycle or secret-authoring contract without issuing writes", async () => {
  for (const unsupported of ["commit", "secret", "auth"]) {
    const fixture = providerFixture();
    if (unsupported === "commit")
      fixture.capabilities[0].inputSchema.properties.operation.enum = [
        "list",
        "get",
      ];
    else if (unsupported === "secret")
      delete fixture.capabilities.find(
        (capability) => capability.name === "configure_secret",
      ).inputSchema.properties.value;
    else {
      const tool = fixture.capabilities.find(
        (capability) => capability.name === "create_http_tool",
      );
      tool.inputSchema = {
        properties: {
          agent_id: {},
          name: {},
          url: {},
          body: {},
          lifecycle: {},
        },
      };
    }
    await assert.rejects(
      fixture.remote.inspect(),
      /advertise|required|secret|authenticated/,
    );
    assert.equal(fixture.calls.length, 0);
  }
});

test("provider verification refuses extra actions and foreign secrets before commit", async () => {
  const fixture = providerFixture();
  await fixture.remote.inspect();
  await fixture.remote.verify(
    "agent",
    ["org", "workspace"],
    "main",
    baseUrl,
    secretId,
  );
  fixture.agent.tools.push({
    name: "bookingos_cancel_booking",
    enabled: false,
  });
  await assert.rejects(
    fixture.remote.verify(
      "agent",
      ["org", "workspace"],
      "main",
      baseUrl,
      secretId,
    ),
    /outside the approved/,
  );
  fixture.agent.tools.pop();
  fixture.agent.tools[0].connector_config.auth.value.secret_id =
    "foreign-client-secret";
  await assert.rejects(
    fixture.remote.verify(
      "agent",
      ["org", "workspace"],
      "main",
      baseUrl,
      secretId,
    ),
    /tool verification/,
  );
  await assert.rejects(
    fixture.remote.toolAt(5, "agent", baseUrl, secretId),
    /outside the approved/,
  );
  assert.ok(!fixture.calls.some((call) => call.args.operation === "commit"));
});
