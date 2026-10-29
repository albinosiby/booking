import { test } from "node:test";
import assert from "node:assert/strict";
import { HttpException, type ArgumentsHost } from "@nestjs/common";
import { ErrorsFilter } from "../src/common/errors.filter";
import { AdminMcpError } from "../src/admin/admin-mcp.service";

test("Nest preserves trusted MCP domain codes without treating arbitrary HTTP payloads as trusted codes", () => {
  function render(error: unknown) {
    let status = 0,
      data: any;
    const response = {
      status(value: number) {
        status = value;
        return this;
      },
      json(value: unknown) {
        data = value;
      },
    };
    const host = {
      switchToHttp: () => ({ getResponse: () => response }),
    } as unknown as ArgumentsHost;
    new ErrorsFilter().catch(error, host);
    return { status, data };
  }
  const failure = render(
    new AdminMcpError("NUMBER_IN_USE", 409, "The selected number is assigned."),
  );
  assert.equal(failure.status, 409);
  assert.equal(failure.data.code, "NUMBER_IN_USE");
  assert.equal(failure.data.message, "The selected number is assigned.");
  assert.ok(failure.data.request_id);
  const untrusted = render(
    new HttpException(
      { code: "UNTRUSTED_PROVIDER_CODE", message: "Refused." },
      409,
    ),
  );
  assert.equal(untrusted.data.code, "CONFLICT");
});
