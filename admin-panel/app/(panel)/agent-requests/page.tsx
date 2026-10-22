import Link from "next/link";
import { admin } from "../../../lib/api";
import { date, label } from "../../../lib/format";
import { Badge, Tabs } from "../../../components/ui";
import { updateAgentRequest } from "../../actions";

const statuses = ["requested", "in_review", "setting_up", "active", "paused", "rejected"];

export default async function AgentRequests({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { status } = await searchParams;
  const { requests } = await admin<{ requests: any[] }>(`/agent-requests${status ? `?status=${status}` : ""}`);
  return (
    <>
      <h1>Agent call requests</h1>
      <p className="sub">
        Move a request through the stages. Setting it to <b>Active</b> tells the user their call service is ready;
        they can then turn it on or off and view call logs. The message below is shown to the user.
      </p>
      <Tabs base="/agent-requests" current={status} items={statuses} />
      {requests.map((r) => (
        <form key={r.id} className="card" action={updateAgentRequest} style={{ display: "grid", gap: 10 }}>
          <input type="hidden" name="id" value={r.id} />
          <div className="row" style={{ justifyContent: "space-between" }}>
            <div>
              <h2 style={{ margin: 0 }}><Link href={`/organizations/${r.organization_id}`}>{r.organization_name}</Link></h2>
              <small>{r.user_name} · {r.user_email} · requested {date(r.created_at)} · updated {date(r.updated_at)}</small>
            </div>
            <Badge value={r.status} />
          </div>
          {r.note && <div className="msg"><small>Customer note</small><p>{r.note}</p></div>}
          <div className="two">
            <label>Status
              <select name="status" defaultValue={r.status}>
                {statuses.map((s) => <option key={s} value={s}>{label(s)}</option>)}
              </select>
            </label>
            <label>Message shown to user
              <input name="user_message" defaultValue={r.user_message} maxLength={500} placeholder="e.g. We are setting up your number" />
            </label>
          </div>
          <label>Internal notes (admin only)
            <textarea name="admin_note" defaultValue={r.admin_note} maxLength={2000} />
          </label>
          <div><button>Save</button></div>
        </form>
      ))}
      {!requests.length && <div className="card empty">No requests.</div>}
    </>
  );
}
