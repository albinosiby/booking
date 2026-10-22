import { admin } from "../../../lib/api";
import { date } from "../../../lib/format";

export default async function Audit() {
  const { events } = await admin<{ events: any[] }>("/audit?limit=200");
  return (
    <>
      <h1>Audit log</h1>
      <p className="sub">Every change made from this panel.</p>
      <div className="card scroll">
        <table>
          <thead><tr><th>When</th><th>Admin</th><th>Action</th><th>Target</th><th>Detail</th></tr></thead>
          <tbody>
            {events.map((e) => (
              <tr key={e.id}>
                <td>{date(e.created_at)}</td><td>{e.admin_email}</td><td>{e.action}</td>
                <td>{e.target_type} <small>{e.target_id}</small></td><td><small>{JSON.stringify(e.detail)}</small></td>
              </tr>
            ))}
          </tbody>
        </table>
        {!events.length && <div className="empty">No activity yet.</div>}
      </div>
    </>
  );
}
