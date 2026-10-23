import { build } from "esbuild";
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
const root = resolve(import.meta.dirname, "..");
const output = resolve(root, "../supabase/functions/booking-api");
mkdirSync(output, { recursive: true });
const font = readFileSync(
  resolve(root, "assets/fonts/NotoSans-Regular.ttf"),
).toString("base64");
const built = await build({
  metafile: true,
  entryPoints: [resolve(root, "edge/entry.ts")],
  outfile: resolve(output, "index.ts"),
  bundle: true,
  format: "esm",
  platform: "node",
  target: "es2022",
  mainFields: ["module", "main"],
  minify: true,
  external: ["node:*", "npm:*"],
  plugins: [
    {
      name: "edge-adapters",
      setup(b) {
        b.onResolve({ filter: /^@nestjs\/common$/ }, () => ({
          path: resolve(root, "edge/http.ts"),
        }));
        b.onResolve({ filter: /^pdfkit$/ }, () => ({
          path: "npm:pdfkit@0.20.2",
          external: true,
        }));
        b.onResolve({ filter: /^exceljs$/ }, () => ({
          path: "npm:exceljs@4.4.0",
          external: true,
        }));
        b.onResolve({ filter: /\/report-font$/ }, () => ({
          path: "report-font",
          namespace: "embedded",
        }));
        b.onLoad({ filter: /.*/, namespace: "embedded" }, () => ({
          contents: `import {Buffer} from 'node:buffer'; export function reportFont(){ return Buffer.from('${font}','base64'); }`,
          loader: "ts",
        }));
      },
    },
  ],
});
// Reports must stay off the startup import graph for every normal API request.
const eagerReportImports = Object.values(built.metafile.outputs)
  .flatMap((o) => o.imports)
  .filter(
    (i) =>
      i.kind === "import-statement" && /npm:(pdfkit|exceljs)@/.test(i.path),
  );
if (eagerReportImports.length)
  throw new Error("Report engines must use dynamic imports.");
writeFileSync(
  resolve(output, "deno.json"),
  JSON.stringify(
    {
      nodeModulesDir: "auto",
      compilerOptions: { lib: ["deno.window"], strict: true },
    },
    null,
    2,
  ) + "\n",
);
console.log(
  `Built Edge API (${readFileSync(resolve(output, "index.ts")).length} bytes); no secrets embedded.`,
);

const notificationOutput = resolve(
  root,
  "../supabase/functions/booking-notifications",
);
mkdirSync(notificationOutput, { recursive: true });
await build({
  entryPoints: [resolve(root, "edge/notifications-entry.ts")],
  outfile: resolve(notificationOutput, "index.ts"),
  bundle: true,
  format: "esm",
  platform: "node",
  target: "es2022",
  minify: true,
  external: ["node:*", "npm:*"],
});
writeFileSync(
  resolve(notificationOutput, "deno.json"),
  JSON.stringify(
    { nodeModulesDir: "auto", compilerOptions: { lib: ["deno.window"] } },
    null,
    2,
  ) + "\n",
);
console.log("Built booking-notifications sender; no secrets embedded.");
