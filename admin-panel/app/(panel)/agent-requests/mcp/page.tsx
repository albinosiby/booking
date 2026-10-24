import Link from "next/link";
import { admin, ApiError } from "../../../../lib/api";
import { PageHeader } from "../../../../components/ui";
import { ActionForm } from "../../../../features/call-service/action-form";
import {
  savePlatform,
  connectPlatform,
} from "../../../../features/call-service/provisioning-actions";
export default async function McpConnection({
  searchParams,
}: {
  searchParams: Promise<{ connected?: string; error?: string }>;
}) {
  const q = await searchParams;
  const s = await admin<any>("/sarvam");
  let templates: { id: string; name: string }[] = [],
    error = "";
  if (s.connected)
    try {
      templates = (await admin<any>("/sarvam/inventory")).templates;
    } catch (e) {
      if (e instanceof ApiError) error = e.message;
      else throw e;
    }
  return (
    <>
      <p>
        <Link href="/agent-requests">← Call service requests</Link>
      </p>
      <PageHeader
        title="Sarvam connection"
        description="One platform connection manages separate agents for your client organizations."
      />
      {q.connected && (
        <p role="status" className="info-note">
          Sarvam sign-in completed. You can now resume client setup.
        </p>
      )}
      {q.error && (
        <p role="alert" className="info-note">
          Sarvam sign-in could not be completed. Reconnect and try again. If the
          problem persists, check the callback URL registration.
        </p>
      )}
      <div className="card">
        <h2>
          {s.connected
            ? "Connected"
            : s.needs_reconnect
              ? "Reconnect required"
              : "Not connected"}
        </h2>
        {s.expires_at && (
          <p>
            Authorization expires:{" "}
            {new Date(s.expires_at).toLocaleString("en-IN", {
              timeZone: "Asia/Kolkata",
            })}{" "}
            IST
          </p>
        )}
        <p>
          When authorization expires, click Reconnect Sarvam and sign in again.
          Return here, then open the client request and resume setup. Existing
          deployed agents and client call controls continue working.
        </p>
      </div>
      <ActionForm action={savePlatform}>
        <h2>Platform workspace settings</h2>
        <input type="hidden" name="version" value={s.version} />
        <p className="sub">
          Enter these once for your Sarvam workspace. Settings → Organisation →
          General and Settings → Workspace → General have copy buttons.
        </p>
        <div className="two">
          <label>
            Provider organization ID
            <input
              name="sarvam_org_id"
              defaultValue={s.sarvam_org_id}
              required
            />
          </label>
          <label>
            Workspace ID
            <input name="workspace_id" defaultValue={s.workspace_id} required />
          </label>
        </div>
        <label>
          Workspace API key{" "}
          {s.has_api_key
            ? `(saved, ending ${s.api_key_last4}; leave empty to keep)`
            : ""}
          <input
            name="api_key"
            type="password"
            autoComplete="new-password"
            required={!s.has_api_key}
          />
        </label>
        <div>
          <button>Save workspace settings</button>
        </div>
      </ActionForm>
      <ActionForm action={connectPlatform}>
        <h2>Authorize MCP access</h2>
        <p>
          Sign in to the same workspace configured above. Sarvam currently
          requires a fresh sign-in after authorization expires, normally after
          24 hours.
        </p>
        <p className="sub">
          Callback URL:{" "}
          <code style={{ overflowWrap: "anywhere" }}>
            {s.redirect_uri || "Set SARVAM_ADMIN_REDIRECT_URI on the API first"}
          </code>
        </p>
        <div>
          <button disabled={!s.has_api_key || !s.redirect_uri}>
            {s.expires_at ? "Reconnect Sarvam" : "Connect Sarvam"}
          </button>
        </div>
      </ActionForm>
      {error && (
        <p role="alert" className="info-note">
          {error}
        </p>
      )}
      {s.connected && (
        <ActionForm action={savePlatform}>
          <h2>Booking agent template</h2>
          <input type="hidden" name="version" value={s.version} />
          <input type="hidden" name="sarvam_org_id" value={s.sarvam_org_id} />
          <input type="hidden" name="workspace_id" value={s.workspace_id} />
          <p>
            Choose one single-state Sarvam agent with the voice and language
            settings you want, and no tools. Each approval copies those settings
            into a new client agent; BookingOS installs the booking instructions
            and seven tools.
          </p>
          <label>
            Template agent
            <select
              name="template_app_id"
              defaultValue={s.template_app_id || ""}
              required
            >
              <option value="" disabled>
                Select a template
              </option>
              {templates.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name} · {t.id}
                </option>
              ))}
            </select>
          </label>
          <div>
            <button disabled={!templates.length}>Save template</button>
          </div>
        </ActionForm>
      )}
    </>
  );
}
