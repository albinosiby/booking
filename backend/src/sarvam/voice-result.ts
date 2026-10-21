import { HttpException } from "@nestjs/common";
import { ZodError } from "zod";

/**
 * Expected refusals (slot taken, unknown space, not the caller's booking) are
 * returned as 200 `{ok:false,message}` so the voice agent can say them.
 */
export async function voiceResult(work: () => Promise<unknown>) {
  try {
    return await work();
  } catch (error) {
    if (error instanceof ZodError)
      return {
        ok: false,
        message:
          "Some details are missing: " +
          error.issues.map((i) => i.path.join(".")).join(", ") +
          ".",
      };
    if (error instanceof HttpException && error.getStatus() < 500)
      return { ok: false, message: error.message };
    throw error;
  }
}
