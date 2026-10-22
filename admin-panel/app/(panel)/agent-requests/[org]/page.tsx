import { admin } from "../../../../lib/api";
import { label } from "../../../../lib/format";
import { saveConnection } from "../../../actions";
import { ToolKey } from "../../../../components/tool-key";

export default async function Connection({ params }: { params: Promise<{ org: string }> }) {
  const { org } = await params;
  const c = await admin<any>(`/agent-requests/${org}/connection`);
  return (
    <>
      <p className="sub"><a href="/agent-requests">← Agent call requests</a></p>
      <h1>Call service connection</h1>
      <p className="sub">
        Provider details for this organization. Owners never see these. After saving, generate a tool key, add it in
        the provider's agent settings with the tool base URL below, then set the request to Active.
      </p>
      <form className="card" action={saveConnection} style={{ display: "grid", gap: 12 }}>
        <input type="hidden" name="org" value={org} />
        <label>API key {c.has_api_key && <small>(saved, ending {c.api_key_last4}; leave empty to keep)</small>}
          <input name="api_key" type="password" autoComplete="off" />
        </label>
        <div className="two">
          <label>Provider organization ID<input name="sarvam_org_id" defaultValue={c.sarvam_org_id} required /></label>
          <label>Workspace ID<input name="workspace_id" defaultValue={c.workspace_id} required /></label>
        </div>
        <label>App ID<input name="app_id" defaultValue={c.app_id} required /></label>
        <fieldset style={{ border: "1px solid var(--line)", borderRadius: 8 }}>
          <legend>Businesses callers may book</legend>
          {c.businesses.map((b: any) => (
            <label key={b.id} style={{ display: "block" }}>
              <input type="checkbox" name="business_ids" value={b.id} defaultChecked={b.assigned} style={{ width: "auto", marginRight: 8 }} />
              {b.name} <small>({label(b.type)})</small>
            </label>
          ))}
        </fieldset>
        <div><button>Save connection</button></div>
      </form>
      <div className="card">
        <h2>Tool key</h2>
        <dl className="kv">
          <dt>Tool base URL</dt><dd><code>{c.tool_base_url}</code></dd>
          <dt>Current key</dt><dd>{c.has_tool_key ? `${c.tool_key_prefix}…` : "None yet"}</dd>
        </dl>
        <ToolKey org={org} has={c.has_tool_key} />
      </div>
    </>
  );
}
