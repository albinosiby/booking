import Link from "next/link";
import { admin } from "../../../lib/api";
import { date, label } from "../../../lib/format";
import { Badge, Tabs, PageHeader, EmptyState } from "../../../components/ui";

export default async function Support({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const { status } = await searchParams;
  const { tickets } = await admin<{ tickets: any[] }>(
    `/support/tickets${status ? `?status=${status}` : ""}`,
  );
  return (
    <>
      <PageHeader
        title="Support inbox"
        description="A little help goes a long way. Keep every conversation moving."
      />
      <Tabs
        base="/support"
        current={status}
        items={["open", "in_progress", "resolved", "closed"]}
      />
      <div className="card scroll">
        <div className="table-heading">
          <h2>
            {status ? `${label(status)} tickets` : "All conversations"}{" "}
            <span>{tickets.length}</span>
          </h2>
          <small>Customer support</small>
        </div>
        <table>
          <thead>
            <tr>
              <th>Subject</th>
              <th>Organization</th>
              <th>From</th>
              <th>Category</th>
              <th>Status</th>
              <th>Updated</th>
            </tr>
          </thead>
          <tbody>
            {tickets.map((t) => (
              <tr key={t.id}>
                <td>
                  <Link href={`/support/${t.id}`}>{t.subject}</Link>
                </td>
                <td>{t.organization_name}</td>
                <td>
                  {t.user_name}
                  <br />
                  <small>{t.user_email}</small>
                </td>
                <td>{label(t.category)}</td>
                <td>
                  <Badge value={t.status} />
                </td>
                <td>{date(t.updated_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {!tickets.length && (
          <EmptyState
            icon="support"
            title="You're all caught up"
            description="No tickets in this view. New conversations will appear here."
          />
        )}
      </div>
    </>
  );
}
