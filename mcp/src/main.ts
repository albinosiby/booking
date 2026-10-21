#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { BookingClient, configFromEnv } from "./client.js";
import { registerTools } from "./tools.js";

const server = new McpServer(
  { name: "eden-booking", version: "0.1.0" },
  {
    instructions:
      "Booking OS tools. Start with list_bookable_options. To book: check_availability → quote_booking → confirm price with the user → create_booking. To reschedule: get_booking → quote_booking with exclude_booking_id → confirm → reschedule_booking. To cancel: get_booking → confirm with the user → cancel_booking. Dates/times are business-local; money is in minor units.",
  },
);
registerTools(server, new BookingClient(configFromEnv()));
await server.connect(new StdioServerTransport());
