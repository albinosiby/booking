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
    send(Object.fromEntries(["organizations", "users", "active_users", "businesses", "bookings", "customers", "open_tickets", "pending_agent_requests"].map((key) => [key, 0])));
  } else if (path === "/public/v1/sites/railway-smoke") {
    send(website);
  } else if (path.startsWith("/public/v1/sites/railway-smoke/")) {
    send({ slots: [] });
  } else {
    send({ message: "Fixture route not found." }, 404);
  }
}).listen(3199, "127.0.0.1", () => console.info("Isolated deployment API fixture listening."));
