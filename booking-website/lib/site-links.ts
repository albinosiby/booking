/**
 * `base` is "" on `<slug>.<domain>` and `/<slug>` with path routing.
 * The API proxy stays under `/api/sites/<slug>` on every host.
 */
export const siteLink = (base: string, path = "", preview?: string) =>
  (`${base}${path}` || "/") +
  (preview ? `?preview=${encodeURIComponent(preview)}` : "");
export const siteBasePath = (slug: string, hostSlug: string | null) =>
  hostSlug === slug ? "" : `/${encodeURIComponent(slug)}`;
export const imageLink = (slug: string, id: string, preview?: string) =>
  `/api/sites/${encodeURIComponent(slug)}/images/${encodeURIComponent(id)}${preview ? `?preview=${encodeURIComponent(preview)}` : ""}`;
export const logoLink = (slug: string, preview?: string) =>
  `/api/sites/${encodeURIComponent(slug)}/logo${preview ? `?preview=${encodeURIComponent(preview)}` : ""}`;
