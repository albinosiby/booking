import Link from "next/link";
import { admin } from "../../../lib/api";
import { date } from "../../../lib/format";
import { Badge, SearchBox } from "../../../components/ui";

export default async function Organizations({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q } = await searchParams;
  const { organizations } = await admin<{ organizations: any[] }>(`/organizations?q=${encodeURIComponent(q ?? "")}`);
  return (
    <>
      <h1>Organizations</h1>
      <p className="sub">Search by organization name or any member's email.</p>
      <SearchBox q={q} placeholder="Name or email" />
      <div className="card scroll">
        <table>
          <thead><tr><th>Name</th><th>Owner</th><th>Users</th><th>Businesses</th><th>Bookings</th><th>Agent calls</th><th>Created</th></tr></thead>
          <tbody>
            {organizations.map((o) => (
              <tr key={o.id}>
                <td><Link href={`/organizations/${o.id}`}>{o.name}</Link></td>
                <td>{o.owner_email ?? "—"}</td><td>{o.users}</td><td>{o.businesses}</td><td>{o.bookings}</td>
                <td>{o.agent_status ? <Badge value={o.agent_status} /> : "—"}</td><td>{date(o.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {!organizations.length && <div className="empty">No organizations found.</div>}
      </div>
    </>
  );
}
