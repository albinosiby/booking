import Link from "next/link";
import { admin } from "../../../lib/api";
import { label } from "../../../lib/format";
import { Badge, SearchBox } from "../../../components/ui";
import { setUserActive } from "../../actions";

export default async function Users({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q } = await searchParams;
  const { users } = await admin<{ users: any[] }>(`/users?q=${encodeURIComponent(q ?? "")}`);
  return (
    <>
      <h1>Users</h1>
      <p className="sub">All accounts across every organization.</p>
      <SearchBox q={q} placeholder="Name, email or organization" />
      <div className="card scroll">
        <table>
          <thead><tr><th>Name</th><th>Email</th><th>Organization</th><th>Role</th><th>Status</th><th /></tr></thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.id}>
                <td>{u.display_name}</td><td>{u.email}</td>
                <td><Link href={`/organizations/${u.organization_id}`}>{u.organization_name}</Link></td>
                <td>{label(u.role)}</td><td><Badge value={u.active ? "active" : "paused"} /></td>
                <td>
                  {u.role !== "owner" && (
                    <form action={setUserActive}>
                      <input type="hidden" name="id" value={u.id} />
                      <input type="hidden" name="active" value={String(!u.active)} />
                      <button className={u.active ? "danger" : "ghost"}>{u.active ? "Deactivate" : "Activate"}</button>
                    </form>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!users.length && <div className="empty">No users found.</div>}
      </div>
    </>
  );
}
