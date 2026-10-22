import Link from "next/link";
import { admin } from "../../../lib/api";
import { date } from "../../../lib/format";
import {
  Badge,
  SearchBox,
  PageHeader,
  EmptyState,
} from "../../../components/ui";

export default async function Organizations({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q } = await searchParams;
  const { organizations } = await admin<{ organizations: any[] }>(
    `/organizations?q=${encodeURIComponent(q ?? "")}`,
  );
  return (
    <>
      <PageHeader
        title="Organizations"
        description="Every workspace, and the people behind it."
      />
      <SearchBox q={q} placeholder="Name or email" />
      <div className="card scroll">
        <div className="table-heading">
          <h2>
            All organizations <span>{organizations.length}</span>
          </h2>
          <small>{q ? `Results for “${q}”` : "Your platform directory"}</small>
        </div>
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Owner</th>
              <th>Users</th>
              <th>Businesses</th>
              <th>Bookings</th>
              <th>Agent calls</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            {organizations.map((o) => (
              <tr key={o.id}>
                <td>
                  <Link href={`/organizations/${o.id}`}>{o.name}</Link>
                </td>
                <td>{o.owner_email ?? "—"}</td>
                <td>{o.users}</td>
                <td>{o.businesses}</td>
                <td>{o.bookings}</td>
                <td>
                  {o.agent_status ? <Badge value={o.agent_status} /> : "—"}
                </td>
                <td>{date(o.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {!organizations.length && (
          <EmptyState
            icon="organizations"
            title="No organizations found"
            description="Try another organization name or member email."
          />
        )}
      </div>
    </>
  );
}
