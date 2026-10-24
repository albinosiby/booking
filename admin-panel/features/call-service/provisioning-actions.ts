"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { admin, ApiError } from "../../lib/api";
import { adminPath } from "../../lib/paths";
export type ProvisioningJob = {
  automatic: boolean;
  step: string;
  error: string;
  done: boolean;
  app_id: string;
  phone_number: string;
  deployment_id: string;
};
export type ProvisioningResult = {
  error?: string;
  success?: string;
  job?: ProvisioningJob;
};
async function safely<T>(
  work: () => Promise<T>,
): Promise<{ value?: T; error?: string }> {
  try {
    return { value: await work() };
  } catch (e) {
    if (e instanceof ApiError) return { error: e.message };
    if (
      e instanceof Error &&
      ["TimeoutError", "AbortError", "TypeError"].includes(e.name)
    )
      return {
        error:
          "The service did not respond. Refresh, then resume setup; completed steps are saved.",
      };
    throw e;
  }
}
function refresh() {
  revalidatePath(adminPath("/agent-requests"), "layout");
}
export async function savePlatform(
  _: ProvisioningResult,
  form: FormData,
): Promise<ProvisioningResult> {
  const key = String(form.get("api_key") ?? "").trim();
  const result = await safely(() =>
    admin("/sarvam", {
      method: "PUT",
      body: {
        version: Number(form.get("version")),
        sarvam_org_id: String(form.get("sarvam_org_id")),
        workspace_id: String(form.get("workspace_id")),
        ...(key ? { api_key: key } : {}),
        ...(form.has("template_app_id")
          ? { template_app_id: String(form.get("template_app_id")) }
          : {}),
      },
    }),
  );
  if (result.error) return { error: result.error };
  refresh();
  return { success: "Sarvam settings saved." };
}
export async function connectPlatform(
  _: ProvisioningResult,
): Promise<ProvisioningResult> {
  const result = await safely(() =>
    admin<{ authorization_url: string }>("/sarvam/connect", { method: "POST" }),
  );
  if (result.error) return { error: result.error };
  redirect(result.value!.authorization_url);
}
export async function approveProvisioning(
  _: ProvisioningResult,
  form: FormData,
): Promise<ProvisioningResult> {
  const org = String(form.get("org"));
  let selection: { connection_id: string; phone_number: string };
  try {
    selection = JSON.parse(String(form.get("number")));
  } catch {
    return { error: "Select an available phone number." };
  }
  const result = await safely(() =>
    admin<ProvisioningJob>(`/sarvam/jobs/${org}/approve`, {
      method: "POST",
      body: {
        version: Number(form.get("version")),
        approved_services: form.getAll("approved_services").map(String),
        connection_id: selection.connection_id,
        phone_number: selection.phone_number,
      },
    }),
  );
  if (result.error) return { error: result.error };
  refresh();
  return {
    job: result.value,
    success: "Request approved. Creating the client’s agent.",
  };
}
export async function continueProvisioning(
  org: string,
): Promise<ProvisioningResult> {
  const result = await safely(() =>
    admin<ProvisioningJob>(`/sarvam/jobs/${org}/resume`, {
      method: "POST",
      timeoutMs: 35000,
    }),
  );
  if (result.error) return { error: result.error };
  refresh();
  return { job: result.value };
}
