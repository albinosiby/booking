import { test } from "node:test";
import assert from "node:assert/strict";
import { readWebsiteResponse } from "../lib/website-response.ts";

test("missing and withdrawn sites remain unavailable", async () => {
  for (const status of [404, 410]) {
    assert.equal(await readWebsiteResponse(new Response(null, { status })), null);
  }
});

test("upstream failures are retryable errors, never missing websites", async () => {
  for (const status of [401, 403, 429, 500, 502, 503, 504]) {
    await assert.rejects(readWebsiteResponse(new Response(null, { status })));
  }
});

test("valid websites load and malformed JSON fails visibly", async () => {
  const site = { slug: "qa-venue", title: "QA venue", businesses: [] };
  assert.deepEqual(await readWebsiteResponse(Response.json(site)), site);
  await assert.rejects(readWebsiteResponse(new Response("invalid json")));
});
