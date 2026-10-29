#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  AdminClient,
  adminConfigFromEnv,
  loadAdminEnvironment,
} from "./admin/client.js";
import { AdminWorkflow } from "./admin/workflow.js";
import { ADMIN_INSTRUCTIONS, registerAdminTools } from "./admin/tools.js";

try {
  await loadAdminEnvironment();
  const server = new McpServer(
    { name: "bookingos-admin", version: "0.1.0" },
    { instructions: ADMIN_INSTRUCTIONS },
  );
  registerAdminTools(
    server,
    new AdminWorkflow(new AdminClient(adminConfigFromEnv())),
  );
  await server.connect(new StdioServerTransport());
} catch {
  // stdout is the protocol channel; configuration or SDK failures may contain secrets.
  process.stderr.write(
    "BookingOS admin MCP could not start. Check the private configuration and setup guide.\n",
  );
  process.exitCode = 1;
}
