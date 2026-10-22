import type { NextConfig } from "next";

const config: NextConfig = {
  output: "export",
  // Keep these assets separate from the public booking Next.js server.
  assetPrefix: "/_landing",
  images: { unoptimized: true },
  poweredByHeader: false,
};

export default config;
