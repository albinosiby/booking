import { test } from "node:test";
import assert from "node:assert/strict";
import { applyRedirectOrigin } from "../../admin-panel/lib/redirect-origin";

test("signed-out admin redirects discard the internal listener port", () => {
  for (const host of ["bookingos.online", "localhost:8080"]) {
    const target = new URL("http://localhost:3100/admin/login");
    applyRedirectOrigin(target, host, "https");
    assert.equal(target.toString(), `https://${host}/admin/login`);
  }
});
