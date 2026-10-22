export const siteLink = (slug: string, path = "", preview?: string) =>
  `/${encodeURIComponent(slug)}${path}${preview ? `?preview=${encodeURIComponent(preview)}` : ""}`;
export const imageLink = (slug: string, id: string, preview?: string) =>
  `/api/sites/${encodeURIComponent(slug)}/images/${encodeURIComponent(id)}${preview ? `?preview=${encodeURIComponent(preview)}` : ""}`;
