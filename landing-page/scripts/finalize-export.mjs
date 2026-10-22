import { mkdir, rename } from "node:fs/promises";

// Next's assetPrefix changes URLs, but exported files still start in out/_next.
// Put them at their public URL so the export works on an ordinary static server
// and does not share /_next with the public booking application.
const destination = new URL("../out/_landing/", import.meta.url);
await mkdir(destination, { recursive: true });
await rename(
  new URL("../out/_next/", import.meta.url),
  new URL("_next/", destination),
);
