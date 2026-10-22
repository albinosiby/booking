import { admin } from "../../../lib/api";
import { date } from "../../../lib/format";
import { PageHeader, EmptyState } from "../../../components/ui";

export default async function Audit() {
  const { events } = await admin<{ events: any[] }>("/audit?limit=200");
  return (
    <>
      <PageHeader
        title="Audit log"
        description="A clear record of the changes made in your workspace."
      />
      <div className="card scroll">
        <div className="table-heading">
          <h2>
            Recent activity <span>{events.length}</span>
          </h2>
          <small>Latest 200 admin events</small>
        </div>
        <table>
          <thead>
            <tr>
              <th>When</th>
              <th>Admin</th>
              <th>Action</th>
              <th>Target</th>
              <th>Detail</th>
            </tr>
          </thead>
          <tbody>
            {events.map((e) => (
              <tr key={e.id}>
                <td>{date(e.created_at)}</td>
                <td>{e.admin_email}</td>
                <td>{e.action}</td>
                <td>
                  {e.target_type} <small>{e.target_id}</small>
                </td>
                <td>
                  <small>{JSON.stringify(e.detail)}</small>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!events.length && (
          <EmptyState
            icon="audit"
            title="A clean slate"
            description="Changes made from this workspace will be recorded here."
          />
        )}
      </div>
    </>
  );
}
