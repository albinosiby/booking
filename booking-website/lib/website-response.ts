import type { Website } from "./types";

export async function readWebsiteResponse(response: Response): Promise<Website | null> {
  if (response.status === 404 || response.status === 410) return null;
  if (!response.ok) throw new Error("Booking service unavailable");
  return (await response.json()) as Website;
}
