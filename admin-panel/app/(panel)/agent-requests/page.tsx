import Link from "next/link";
import { admin } from "../../../lib/api";
import { date, label } from "../../../lib/format";
import { Badge, Tabs, PageHeader, EmptyState } from "../../../components/ui";
import { SubmitButton } from "../../../components/submit-button";
import { updateRequest } from "../../../features/call-service/actions";
import { ActionForm } from "../../../features/call-service/action-form";

const statuses = [
  "requested",
  "in_review",
  "setting_up",
  "active",
  "paused",
  "rejected",
];

export default async function AgentRequests({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const { status } = await searchParams;
  const { requests } = await admin<{ requests: any[] }>(
    `/agent-requests${status ? `?status=${status}` : ""}`,
  );
  return (
    <>
      <PageHeader
        title="Call service requests"
        description="Help every organization get their call service up and running."
      />
      <p className="info-note">
        Move a request through the stages. A connection must be verified before
        it can be marked <b>Active</b>. Clients then select spaces and enable
        their approved services. The message below is shown to the user.
      </p>
      <Tabs base="/agent-requests" current={status} items={statuses} />
      {requests.map((r) => (
        <ActionForm key={r.id} className="card" action={updateRequest}>
          <input type="hidden" name="id" value={r.id} />
          <input type="hidden" name="version" value={r.version} />
          <p>
            <b>Requested:</b> {r.requested_services.map(label).join(", ")}
            <br />
            <b>Approved:</b>{" "}
            {r.approved_services.length
              ? r.approved_services.map(label).join(", ")
              : "Pending review"}
          </p>
          <div className="row" style={{ justifyContent: "space-between" }}>
            <div>
              <h2 style={{ margin: 0 }}>
                <Link href={`/organizations/${r.organization_id}`}>
                  {r.organization_name}
                </Link>
              </h2>
              <small>
                {r.user_name} · {r.user_email} · requested {date(r.created_at)}{" "}
                · updated {date(r.updated_at)}
              </small>
            </div>
            <Badge value={r.status} />
          </div>
          {r.note && (
            <div className="msg">
              <small>Customer note</small>
              <p>{r.note}</p>
            </div>
          )}
          <div className="two">
            <label>
              Status
              <select name="status" defaultValue={r.status}>
                {statuses.map((s) => (
                  <option key={s} value={s}>
                    {label(s)}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Message shown to user
              <input
                name="user_message"
                defaultValue={r.user_message}
                maxLength={500}
                placeholder="e.g. We are setting up your number"
              />
            </label>
          </div>
          <label>
            Internal notes (admin only)
            <textarea
              name="admin_note"
              defaultValue={r.admin_note}
              maxLength={2000}
            />
          </label>
          <div className="row">
            <SubmitButton>Save changes</SubmitButton>
            <Link
              className="btn ghost"
              href={`/agent-requests/${r.organization_id}`}
            >
              Manage connection
            </Link>
          </div>
        </ActionForm>
      ))}
      {!requests.length && (
        <div className="card">
          <EmptyState
            icon="phone"
            title="Nothing waiting here"
            description="Agent call requests will appear here as organizations get started."
          />
        </div>
      )}
    </>
  );
}
