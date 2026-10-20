// Only the runtime APIs used by the entry; implementation is supplied by Supabase.
declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (request: Request) => Promise<Response>): unknown;
};
declare module "npm:pg@8.16.3" {
  export { Pool } from "pg";
}
