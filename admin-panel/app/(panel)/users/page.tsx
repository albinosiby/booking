import Link from "next/link";
import { admin } from "../../../lib/api";
import { label } from "../../../lib/format";
import {
  Badge,
  SearchBox,
  PageHeader,
  EmptyState,
} from "../../../components/ui";
import { SubmitButton } from "../../../components/submit-button";
import { setUserActive } from "../../actions";

export default async function Users({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q } = await searchParams;
  const { users } = await admin<{ users: any[] }>(
    `/users?q=${encodeURIComponent(q ?? "")}`,
  );
  return (
    <>
      <PageHeader
        title="Users"
        description="The people who keep your organizations moving."
      />
      <SearchBox q={q} placeholder="Name, email or organization" />
      <div className="card scroll">
        <div className="table-heading">
          <h2>
            User directory <span>{users.length}</span>
          </h2>
          <small>Memberships across organizations</small>
        </div>
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Organization</th>
              <th>Role</th>
              <th>Status</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.id}>
                <td>{u.display_name}</td>
                <td>{u.email}</td>
                <td>
                  <Link href={`/organizations/${u.organization_id}`}>
                    {u.organization_name}
                  </Link>
                </td>
                <td>{label(u.role)}</td>
                <td>
                  <Badge value={u.active ? "active" : "paused"} />
                </td>
                <td>
                  {u.role !== "owner" && (
                    <form action={setUserActive}>
                      <input type="hidden" name="id" value={u.id} />
                      <input
                        type="hidden"
                        name="active"
                        value={String(!u.active)}
                      />
                      <SubmitButton className={u.active ? "danger" : "ghost"}>
                        {u.active ? "Deactivate" : "Activate"}
                      </SubmitButton>
                    </form>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!users.length && (
          <EmptyState
            icon="users"
            title="No matching users"
            description="Try a different name, email, or organization."
          />
        )}
      </div>
    </>
  );
}
