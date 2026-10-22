export const ADMIN_BASE_PATH = "/admin";

/** Used for cookies, cache invalidation and HTTP redirects. Next Link adds it itself. */
export function adminPath(path = "/") {
  return `${ADMIN_BASE_PATH}${path === "/" ? "" : path}`;
}
