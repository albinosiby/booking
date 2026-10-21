# Booking OS MCP server

A stdio [MCP](https://modelcontextprotocol.io) server that lets an AI assistant book, reschedule and cancel reservations through the hosted `booking-api` Edge Function. It signs in as a real owner/staff account, so all server rules still apply. These include organization and staff permissions, quote tokens, price checks, inventory conflicts, version checks and idempotent command keys. It does not touch the database directly and needs no migrations.

## Tools

| Tool | Purpose |
|---|---|
| `list_bookable_options` | Businesses, spaces (`resource_id`), options (`option_id`), timezone, today, permissions |
| `check_availability` | Priced start times for a date (does not hold a slot) |
| `quote_booking` | Authoritative price + `quote_token` for an exact selection |
| `find_bookings` | Search by name/phone/reference, date range, business, space, status |
| `get_booking` | Full booking including the current `version` |
| `create_booking` | Book with a quote token, customer and optional payments received |
| `reschedule_booking` | Atomically move a confirmed booking (needs `version` + new quote) |
| `cancel_booking` | Cancel a confirmed booking (needs `version` and a reason) |

Flows:

- **Book:** `list_bookable_options` → `check_availability` → `quote_booking` → confirm the price → `create_booking`
- **Reschedule:** `get_booking` → `quote_booking` with `exclude_booking_id` → confirm → `reschedule_booking`
- **Cancel:** `get_booking` → confirm → `cancel_booking`

Dates and times are business-local (`YYYY-MM-DD`, `HH:MM`). Money is in minor units (₹500 = `50000`). Collected money on a cancelled booking becomes refund due; the owner records refunds in the app.

If a write fails with an uncertain outcome (network error or 5xx), the server first looks up the committed result by its command key. If it still can't tell, the error includes the `command_key`. Retry with that key and the same inputs, and the action never runs twice.

## Setup

```sh
cd mcp
npm ci
npm run build
```

Use a dedicated staff account with only the businesses and permissions the assistant should have. `manage_bookings` is needed to book, reschedule or cancel; `collect_payments` is needed to record payments on creation.

| Variable | Required | Default |
|---|---|---|
| `BOOKING_EMAIL` / `BOOKING_PASSWORD` | yes (or a refresh token) | — |
| `BOOKING_REFRESH_TOKEN` | alternative to a password | — |
| `BOOKING_SUPABASE_URL` | no | the `booking` project |
| `BOOKING_PUBLISHABLE_KEY` | no | the project's publishable key |
| `BOOKING_API_URL` | no | `<supabase>/functions/v1/booking-api/v1` |

### Claude Code (this repository)

The repository's `.mcp.json` registers `eden-booking` and reads credentials from `mcp/.env` (gitignored). Copy `mcp/.env.example` to `mcp/.env`, fill it in, build, and approve the server when Claude Code asks.

### Claude Code (any folder)

```sh
claude mcp add eden-booking \
  -e BOOKING_EMAIL=assistant@example.com -e BOOKING_PASSWORD='…' \
  -- node "/absolute/path/to/booking/mcp/dist/main.js"
```

### Claude Desktop / other clients (`mcpServers` JSON)

```json
{
  "mcpServers": {
    "eden-booking": {
      "command": "node",
      "args": ["/absolute/path/to/booking/mcp/dist/main.js"],
      "env": { "BOOKING_EMAIL": "assistant@example.com", "BOOKING_PASSWORD": "…" }
    }
  }
}
```

## Tests

```sh
npm test
```

The tests drive the tools through an in-memory MCP client against a fake API, so they never contact Supabase.
