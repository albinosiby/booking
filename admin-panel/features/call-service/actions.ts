"use server";
import { revalidatePath } from "next/cache";
import { admin, ApiError } from "../../lib/api";
import { adminPath } from "../../lib/paths";
export type ActionResult = { error?: string; success?: string; key?: string };
async function execute(
  path: string,
  method: string,
  body?: unknown,
): Promise<ActionResult> {
  try {
    const result = await admin<{ tool_key?: string }>(path, { method, body });
    revalidatePath(adminPath("/agent-requests"), "layout");
    return {
      success: "Saved successfully.",
      ...(result.tool_key ? { key: result.tool_key } : {}),
    };
  } catch (error) {
    if (error instanceof ApiError) return { error: error.message };
    if (
      error instanceof Error &&
      ["TimeoutError", "AbortError", "TypeError"].includes(error.name)
    )
      return {
        error: "The service did not respond. Refresh the page before retrying.",
      };
    throw error;
  }
}
export async function updateRequest(_: ActionResult, form: FormData) {
  return execute(`/agent-requests/${form.get("id")}`, "PUT", {
    version: Number(form.get("version")),
    status: String(form.get("status")),
    admin_note: String(form.get("admin_note") ?? ""),
    user_message: String(form.get("user_message") ?? ""),
  });
}
export async function saveManagedConnection(_: ActionResult, form: FormData) {
  const key = String(form.get("api_key") ?? "").trim();
  return execute(`/agent-requests/${form.get("org")}/connection`, "PUT", {
    version: Number(form.get("version")),
    ...(key ? { api_key: key } : {}),
    sarvam_org_id: String(form.get("sarvam_org_id") ?? ""),
    workspace_id: String(form.get("workspace_id") ?? ""),
    app_id: String(form.get("app_id") ?? ""),
    phone_number: String(form.get("phone_number") ?? ""),
    deployment_id: String(form.get("deployment_id") ?? ""),
    approved_services: form.getAll("approved_services").map(String),
  });
}
export async function verifyManagedConnection(_: ActionResult, form: FormData) {
  return execute(`/agent-requests/${form.get("org")}/verify`, "POST", {
    version: Number(form.get("version")),
    tools_confirmed: form.get("tools_confirmed") === "on",
  });
}
export async function generateManagedToolKey(_: ActionResult, form: FormData) {
  return execute(`/agent-requests/${form.get("org")}/tool-key`, "POST");
}
