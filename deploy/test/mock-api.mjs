// Isolated HTTP fixture for container tests. No persistence or external requests.
import { createServer } from "node:http";
import { createHash, createHmac, timingSafeEqual } from "node:crypto";

const website = {
  slug: "railway-smoke", title: "Railway fixture venue", description: "Isolated deployment test.",
  contact_phone: "", instructions: "", cancellation_policy: "", currency: "INR", status: "published",
  is_preview: false, has_logo: false, hero_image: null, hero_heading: "Fixture booking website", social_links: {},
  notice_minutes: 0, advance_days: 14,
  businesses: [{
    id: "fixture-court", name: "Fixture badminton court", type: "badminton", timezone: "Asia/Kolkata",
    today: "2026-10-22", location_name: "Test location", address: "Test address", description: "",
    card_image: null, resources: [{
      id: "court-one", name: "Court one", images: [], notice_minutes: 0, advance_days: 14, rules: "",
      capacity: 4, ground_id: null, section_ids: [], options: [{
        id: "normal", name: "Badminton", kind: "normal", sport: "badminton", format: null,
        minimum_duration: 60, duration_step: 15, default_duration: 60, fixed_time: null,
        from_minor: 40000, tariffs: [],
      }],
    }],
  }],
};

const organizations = [
  { id: "00000000-0000-4000-8000-000000000001", name: "Northstar Sports", owner_email: "owner@northstar.example.invalid", users: 8, businesses: 3, bookings: 18, agent_status: "active", created_at: "2026-10-22T09:30:00Z" },
  { id: "00000000-0000-4000-8000-000000000002", name: "Riverside Arena", owner_email: "team@riverside.example.invalid", users: 4, businesses: 2, bookings: 12, agent_status: null, created_at: "2026-10-21T10:00:00Z" },
  { id: "00000000-0000-4000-8000-000000000003", name: "The Clubhouse", owner_email: "hello@clubhouse.example.invalid", users: 3, businesses: 1, bookings: 6, agent_status: null, created_at: "2026-10-20T11:00:00Z" },
];

createServer((request, response) => {
  const path = new URL(request.url, "http://localhost").pathname;
  const send = (value, status = 200) => response.writeHead(status, { "Content-Type": "application/json" }).end(JSON.stringify(value));
  if (path.startsWith("/v1/admin/")) {
    const match = /^(\d{13})\.([a-f0-9-]{36})\.([a-f0-9]{64})$/.exec(request.headers["x-bookingos-admin"] ?? "");
    const secret = process.env.ADMIN_SESSION_SECRET;
    if (!match || !secret || Math.abs(Date.now() - Number(match[1])) > 60000) {
      send({ message: "Admin signature required." }, 401);
      return;
    }
    const expected = createHmac("sha256", secret).update(["booking-admin-v1", match[1], match[2], request.method, request.url, createHash("sha256").update("").digest("hex")].join("\n")).digest();
    if (!timingSafeEqual(expected, Buffer.from(match[3], "hex"))) {
      send({ message: "Invalid admin signature." }, 401);
      return;
    }
  }
  if (request.method !== "GET") {
    send({ message: "Fixture does not accept writes." }, 405);
  } else if (path === "/v1/admin/me") {
    send({ email: "fixture@example.invalid", role: "super_admin" });
  } else if (path === "/v1/admin/overview") {
    send({ organizations: 3, users: 15, active_users: 12, businesses: 6, bookings: 36, customers: 24, open_tickets: 0, pending_agent_requests: 0 });
  } else if (path === "/v1/admin/organizations") {
    const query = new URL(request.url, "http://localhost").searchParams;
    const search = (query.get("q") || "").toLowerCase();
    send({ organizations: organizations.filter((org) => `${org.name} ${org.owner_email}`.toLowerCase().includes(search)).slice(0, Number(query.get("limit") || 100)) });
  } else if (path.startsWith("/v1/admin/organizations/")) {
    const organization = organizations.find((org) => org.id === path.split("/").at(-1));
    if (!organization) { send({ message: "Not found." }, 404); return; }
    send({ organization: { ...organization, currency: "INR", contact_phone: "0000000000" }, stats: { bookings: organization.bookings, cancelled: 0, booked_minor: 250000, customers: 8, last_booking_at: "2026-10-22T08:00:00Z" }, website: null, agent_request: null, members: [], businesses: [], locations: [], invitations: [], tickets: [] });
  } else if (path === "/v1/admin/users") {
    const query = new URL(request.url, "http://localhost").searchParams.get("q") || "";
    const users = [{ id: "00000000-0000-4000-8000-000000000010", display_name: "Alex Morgan", email: "owner@northstar.example.invalid", organization_id: organizations[0].id, organization_name: organizations[0].name, role: "owner", active: true }];
    send({ users: users.filter((user) => `${user.display_name} ${user.email} ${user.organization_name}`.toLowerCase().includes(query.toLowerCase())) });
  } else if (path === "/v1/admin/support/tickets") {
    send({ tickets: [] });
  } else if (path === "/v1/admin/agent-requests") {
    send({ requests: [] });
  } else if (path === "/v1/admin/audit") {
    send({ events: [] });
  } else if (path === "/public/v1/sites/railway-smoke") {
    send(website);
  } else if (path.startsWith("/public/v1/sites/railway-smoke/")) {
    send({ slots: [] });
  } else {
    send({ message: "Fixture route not found." }, 404);
  }
}).listen(3199, "127.0.0.1", () => console.info("Isolated deployment API fixture listening."));
