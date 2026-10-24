import Link from "next/link";
import { admin } from "../../../lib/api";
import { date, label } from "../../../lib/format";
import { Badge, Tabs, PageHeader, EmptyState } from "../../../components/ui";
import { Icon } from "../../../components/icon";

const statuses = [
  "requested",
  "in_review",
  "setting_up",
  "active",
  "paused",
  "rejected",
];

type CallRequest = {
  id: string;
  organization_id: string;
  organization_name: string;
  user_name: string;
  user_email: string;
  status: string;
  requested_services: string[];
  approved_services: string[];
  note: string | null;
  created_at: string;
  updated_at: string;
};

export default async function AgentRequests({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const { status: selectedStatus } = await searchParams;
  const status = statuses.includes(selectedStatus ?? "")
    ? selectedStatus
    : undefined;
  const { requests } = await admin<{ requests: CallRequest[] }>(
    `/agent-requests${status ? `?status=${status}` : ""}`,
  );
  return (
    <>
      <PageHeader
        title="Call service requests"
        description="Choose a request to review its details and configure the call service."
      />
      <Tabs base="/agent-requests" current={status} items={statuses} />
      <div className="request-list-heading">
        <p>{status ? label(status) : "All requests"}</p>
        <span>{requests.length} shown · Latest updates first</span>
      </div>
      {requests.length > 0 ? (
        <ul className="request-grid" aria-label="Call service requests">
          {requests.map((request) => (
            <li key={request.id}>
              <Link
                className="request-tile"
                href={`/agent-requests/${request.organization_id}`}
                prefetch={false}
                aria-label={`Configure call service for ${request.organization_name}`}
              >
                <div className="request-tile-top">
                  <span className="request-icon">
                    <Icon name="phone" size={20} />
                  </span>
                  <Badge value={request.status} />
                </div>
                <div>
                  <h2>{request.organization_name}</h2>
                  <p className="request-requester">{request.user_name}</p>
                  <p className="request-email">{request.user_email}</p>
                </div>
                <div className="request-services">
                  <span className="request-caption">Requested services</span>
                  <div className="request-service-tags">
                    {request.requested_services.map((service) => (
                      <span key={service}>{label(service)}</span>
                    ))}
                    {!request.requested_services.length && (
                      <span>No services selected</span>
                    )}
                  </div>
                  <p className="request-approved">
                    Approved:{" "}
                    {request.approved_services.length
                      ? request.approved_services.map(label).join(", ")
                      : "Pending review"}
                  </p>
                </div>
                {request.note && <p className="request-note">{request.note}</p>}
                <dl className="request-dates">
                  <div>
                    <dt>Requested</dt>
                    <dd>{date(request.created_at)}</dd>
                  </div>
                  <div>
                    <dt>Updated</dt>
                    <dd>{date(request.updated_at)}</dd>
                  </div>
                </dl>
                <div className="request-tile-footer">
                  <span>View details & configure</span>
                  <Icon name="arrow" size={17} />
                </div>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <div className="card">
          <EmptyState
            icon="phone"
            title={
              status
                ? `No ${label(status).toLowerCase()} requests`
                : "No call service requests yet"
            }
            description={
              status
                ? "Choose another status or view all requests."
                : "Requests will appear here when organizations ask to enable their call service."
            }
          />
          {status && (
            <Link className="btn ghost" href="/agent-requests">
              View all requests
            </Link>
          )}
        </div>
      )}
      <p className="sub">
        Open a request to manage its connection, tools, verification and client
        status. A verified connection is required before activation.
      </p>
    </>
  );
}
