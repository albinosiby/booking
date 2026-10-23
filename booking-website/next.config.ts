import type { NextConfig } from "next";
const config: NextConfig = {
  output: "standalone",
  poweredByHeader: false,
  // Keep the internal request origin intact behind Railway's HTTPS gateway.
  // NextURL normalizes 127.0.0.1 to localhost, making a local rewrite external.
  skipProxyUrlNormalize: true,
  // Local subdomain testing: http://<slug>.localhost:3000 with BOOKING_SITE_DOMAIN=localhost.
  allowedDevOrigins: ["localhost", "*.localhost"],
  logging: { incomingRequests: false },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "Referrer-Policy", value: "no-referrer" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "X-Frame-Options", value: "DENY" },
          {
            key: "Permissions-Policy",
            value: "camera=(), microphone=(), geolocation=()",
          },
        ],
      },
    ];
  },
};
export default config;
