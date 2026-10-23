/** Validate settings before interpolating the custom domain into Nginx config. */
export function routingConfiguration(env = process.env) {
  const domain = (env.BOOKING_SITE_DOMAIN || "bookingos.online")
    .trim()
    .toLowerCase()
    .replace(/\.$/, "");
  if (
    domain.length > 253 ||
    !domain
      .split(".")
      .every(
        (part) =>
          part.length <= 63 && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(part),
      )
  )
    throw new Error(
      "BOOKING_SITE_DOMAIN must be a hostname without a scheme, port or path.",
    );
  const mode = env.BOOKING_ROUTING_MODE || "auto";
  if (!["auto", "path", "subdomain"].includes(mode))
    throw new Error("BOOKING_ROUTING_MODE must be auto, path or subdomain.");

  // Match the same single-label tenant names as booking-website/lib/site-host.ts.
  const reserved = "www|api|app|admin|book|login|sign-in|register";
  const pattern = `^(?!(?:${reserved})\\.)(?=[a-z0-9-]{3,63}\\.)[a-z0-9]+(?:-[a-z0-9]+)*\\.${domain.replaceAll(".", "\\.")}$`;
  return {
    domain,
    mode,
    tenantHostRule: mode === "path" ? "" : `"~${pattern}" 1;`,
  };
}
