import Link from "next/link";
import { admin } from "../../../../lib/api";
import { date, label } from "../../../../lib/format";
import { PageHeader, Badge } from "../../../../components/ui";
import { ActionForm } from "../../../../features/call-service/action-form";
import {
  saveManagedConnection,
  verifyManagedConnection,
  generateManagedToolKey,
  updateRequest,
} from "../../../../features/call-service/actions";
export default async function Connection({
  params,
}: {
  params: Promise<{ org: string }>;
}) {
  const { org } = await params;
  const [c, { organization }] = await Promise.all([
    admin<any>(`/agent-requests/${org}/connection`),
    admin<{ organization: { name: string } }>(`/organizations/${org}`),
  ]);
  const r = c.request;
  return (
    <>
      <p className="sub">
        <Link href="/agent-requests">← Call service requests</Link>
      </p>
      <PageHeader
        title={organization.name}
        description="Connect the client’s phone service, verify the number, then activate access."
      />
      <section className="card request-summary" aria-label="Request details">
        <div className="request-summary-heading">
          <h2>Call service setup</h2>
          <Link href={`/organizations/${org}`}>View organization →</Link>
        </div>
        <div className="row">
          <Badge value={r.status} />
          <span>
            {c.verified_at
              ? `Verified ${date(c.verified_at)}`
              : "Verification required"}
          </span>
        </div>
        <p>
          <b>Requested services:</b>{" "}
          {r.requested_services.map(label).join(", ")}
        </p>
        <p>
          <b>Approved services:</b>{" "}
          {r.approved_services.length
            ? r.approved_services.map(label).join(", ")
            : "Pending review"}
        </p>
        {r.note && (
          <div className="msg">
            <small>Customer note</small>
            <p>{r.note}</p>
          </div>
        )}
        <p className="sub">
          Clients see their number, approved services, selected spaces and call
          history. Provider details stay in this panel.
        </p>
      </section>
      <nav
        className="request-setup-nav"
        aria-label="Call service setup sections"
      >
        <a href="#connection">
          <span>1</span> Connection
        </a>
        <a href="#tools">
          <span>2</span> Agent tools
        </a>
        <a href="#verification">
          <span>3</span> Verification
        </a>
        <a href="#client-status">
          <span>4</span> Client status
        </a>
      </nav>
      <ActionForm id="connection" action={saveManagedConnection}>
        <h2>1. Connection and services</h2>
        <input type="hidden" name="org" value={org} />
        <input type="hidden" name="version" value={c.version} />
        <div className="two">
          <label>
            Booking phone number
            <input
              name="phone_number"
              type="tel"
              defaultValue={c.phone_number}
              placeholder="+919876543210"
              pattern="\+[1-9][0-9]{7,14}"
              required
            />
          </label>
          <label>
            Inbound deployment ID
            <input
              name="deployment_id"
              defaultValue={c.deployment_id}
              required
            />
          </label>
        </div>
        <label>
          Sarvam API key{" "}
          {c.has_api_key && (
            <small>
              (saved, ending {c.api_key_last4}; leave empty to keep)
            </small>
          )}
          <input
            name="api_key"
            type="password"
            autoComplete="new-password"
            required={!c.has_api_key}
          />
        </label>
        <div className="two">
          <label>
            Provider organization ID
            <input
              name="sarvam_org_id"
              defaultValue={c.sarvam_org_id}
              required
            />
          </label>
          <label>
            Workspace ID
            <input name="workspace_id" defaultValue={c.workspace_id} required />
          </label>
        </div>
        <label>
          Agent App ID
          <input name="app_id" defaultValue={c.app_id} required />
        </label>
        <fieldset style={{ border: "1px solid var(--line)", borderRadius: 8 }}>
          <legend>Approve requested services</legend>
          {r.requested_services.map((service: string) => (
            <label key={service} style={{ display: "block", padding: 8 }}>
              <input
                type="checkbox"
                name="approved_services"
                value={service}
                defaultChecked={r.approved_services.includes(service)}
                style={{ width: "auto", marginRight: 8 }}
              />
              {label(service)}
            </label>
          ))}
        </fieldset>
        <p className="sub">
          Saving changes turns the service off and requires verification again.
          The client selects spaces after activation.
        </p>
        <div>
          <button>Save connection</button>
        </div>
      </ActionForm>
      <ActionForm id="tools" action={generateManagedToolKey}>
        <h2>2. Configure the agent tools</h2>
        <input type="hidden" name="org" value={org} />
        <p>
          Tool base URL:{" "}
          <code style={{ overflowWrap: "anywhere" }}>{c.tool_base_url}</code>
        </p>
        <p>
          Current key:{" "}
          {c.has_tool_key ? `${c.tool_key_prefix}…` : "Not generated"}
        </p>
        <p className="sub">
          Store the key in Sarvam’s secret store as the X-API-Key header on
          every tool. Regenerating it stops service access until the new key is
          configured and verified.
        </p>
        <div>
          <button className="ghost" disabled={!c.has_api_key}>
            {c.has_tool_key ? "Replace tool key" : "Generate tool key"}
          </button>
        </div>
        <details>
          <summary>Tool setup reference</summary>
          <p>
            Use POST with a JSON body. Run catalog at call start and save its
            message into bookingos_spaces. For other tools, return the message
            field to the agent. Map caller_phone and interaction_id from trusted
            call context, never from caller-supplied text.
          </p>
          {c.tools.map((tool: any) => (
            <p key={tool.name}>
              <b>{tool.name}</b>
              <br />
              <code>/{tool.path}</code>
              <br />
              <small>{tool.fields.join(", ") || "No body fields"}</small>
            </p>
          ))}
          <p>
            <b>bookingos_call_completed</b>
            <br />
            <code>/call-events</code>
          </p>
          <p>
            Add an authenticated HTTP tool that runs on call end. Map
            interaction_id to Interaction ID, caller_phone to User Identifier,
            duration_seconds to Call Length, and transcript to Call Transcript.
            Send these values as JSON; transcript must be text. This saves call
            history even while service actions are off. Optional summary,
            caller_name and disposition fields can use your captured variables.
          </p>
        </details>
        <details>
          <summary>Managed conversation instructions</summary>
          <pre
            style={{
              whiteSpace: "pre-wrap",
              overflowWrap: "anywhere",
              fontSize: 13,
            }}
          >
            {c.instructions}
          </pre>
        </details>
      </ActionForm>
      <ActionForm id="verification" action={verifyManagedConnection}>
        <h2>3. Verify the connection</h2>
        <input type="hidden" name="org" value={org} />
        <input type="hidden" name="version" value={c.version} />
        <p>
          Checks analytics access and that the active inbound deployment uses
          this agent and phone number.
        </p>
        <label>
          <input
            type="checkbox"
            name="tools_confirmed"
            required
            style={{ width: "auto", marginRight: 8 }}
          />
          I configured and reviewed the tools, trusted caller fields and
          conversation instructions in the deployed agent version.
        </label>
        <div>
          <button disabled={!c.has_tool_key || !c.has_api_key}>
            Verify connection
          </button>
        </div>
        <small>Verification does not place a call or create a booking.</small>
      </ActionForm>
      <ActionForm id="client-status" action={updateRequest}>
        <h2>4. Update client status</h2>
        <input type="hidden" name="id" value={r.id} />
        <input type="hidden" name="version" value={r.version} />
        <div className="two">
          <label>
            Status
            <select name="status" defaultValue={r.status}>
              {[
                "requested",
                "in_review",
                "setting_up",
                "active",
                "paused",
                "rejected",
              ].map((status) => (
                <option
                  key={status}
                  value={status}
                  disabled={status === "active" && !c.verified_at}
                >
                  {status === "active" ? "Connected" : label(status)}
                </option>
              ))}
            </select>
          </label>
          <label>
            Message shown to client
            <input
              name="user_message"
              defaultValue={r.user_message}
              maxLength={500}
            />
          </label>
        </div>
        <label>
          Internal notes
          <textarea
            name="admin_note"
            defaultValue={r.admin_note}
            maxLength={2000}
          />
        </label>
        <p className="sub">
          Connecting unlocks client controls. The client chooses spaces and
          turns the service on. Pausing blocks all service actions immediately.
        </p>
        <div>
          <button>Update status</button>
        </div>
      </ActionForm>
    </>
  );
}
