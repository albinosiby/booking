import Link from "next/link";
import { admin } from "../../../../lib/api";
import { date, money, label } from "../../../../lib/format";
import { Badge } from "../../../../components/ui";
import { setUserActive } from "../../../actions";

export default async function Organization({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const d = await admin<any>(`/organizations/${id}`);
  const o = d.organization, s = d.stats;
  return (
    <>
      <p className="sub"><Link href="/organizations">← Organizations</Link></p>
      <h1>{o.name}</h1>
      <p className="sub">Created {date(o.created_at)}</p>
      <div className="grid">
        <div className="stat"><b>{s.bookings}</b><span>Bookings ({s.cancelled} cancelled)</span></div>
        <div className="stat"><b>{money(s.booked_minor, o.currency)}</b><span>Booked value</span></div>
        <div className="stat"><b>{s.customers}</b><span>Customers</span></div>
        <div className="stat"><b>{date(s.last_booking_at)}</b><span>Last booking</span></div>
      </div>
      <div className="two">
        <div className="card">
          <h2>Profile</h2>
          <dl className="kv">
            <dt>Phone</dt><dd>{o.contact_phone}</dd><dt>Currency</dt><dd>{o.currency}</dd><dt>Organization ID</dt><dd>{o.id}</dd>
            <dt>Website</dt><dd>{d.website ? <>{d.website.title} · <Badge value={d.website.status} /> · /{d.website.slug}</> : "Not set up"}</dd>
          </dl>
        </div>
        <div className="card">
          <h2>Agent call service</h2>
          {d.agent_request ? (
            <dl className="kv">
              <dt>Status</dt><dd><Badge value={d.agent_request.status} /></dd>
              <dt>Requested</dt><dd>{date(d.agent_request.created_at)}</dd>
              <dt>Note</dt><dd>{d.agent_request.note || "—"}</dd>
              <dt></dt><dd><Link href={`/agent-requests?status=${d.agent_request.status}`}>Manage request</Link></dd>
            </dl>
          ) : <div className="empty">No request yet.</div>}
        </div>
      </div>
      <div className="card scroll">
        <h2>Team ({d.members.length})</h2>
        <table>
          <thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Status</th><th /></tr></thead>
          <tbody>
            {d.members.map((m: any) => (
              <tr key={m.id}>
                <td>{m.display_name}</td><td>{m.email}</td><td>{label(m.role)}</td>
                <td><Badge value={m.active ? "active" : "paused"} /></td>
                <td>
                  {m.role !== "owner" && (
                    <form action={setUserActive}>
                      <input type="hidden" name="id" value={m.id} />
                      <input type="hidden" name="active" value={String(!m.active)} />
                      <button className={m.active ? "danger" : "ghost"}>{m.active ? "Deactivate" : "Activate"}</button>
                    </form>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="card scroll">
        <h2>Businesses ({d.businesses.length})</h2>
        <table>
          <thead><tr><th>Name</th><th>Type</th><th>Status</th><th>Resources</th></tr></thead>
          <tbody>{d.businesses.map((b: any) => (
            <tr key={b.id}><td>{b.name}</td><td>{label(b.type)}</td><td><Badge value={b.status} /></td><td>{b.resources}</td></tr>
          ))}</tbody>
        </table>
        {!d.businesses.length && <div className="empty">No businesses.</div>}
      </div>
      <div className="card scroll">
        <h2>Locations ({d.locations.length})</h2>
        <table>
          <thead><tr><th>Name</th><th>Address</th><th>Timezone</th></tr></thead>
          <tbody>{d.locations.map((l: any) => (
            <tr key={l.id}><td>{l.name}</td><td>{[l.address_line_1, l.address_line_2, l.city, l.state_code, l.postal_code, l.country_code].filter(Boolean).join(", ")}</td><td>{l.timezone}</td></tr>
          ))}</tbody>
        </table>
      </div>
      <div className="two">
        <div className="card scroll">
          <h2>Invitations</h2>
          <table>
            <thead><tr><th>Email</th><th>Role</th><th>State</th></tr></thead>
            <tbody>{d.invitations.map((i: any) => (
              <tr key={i.id}><td>{i.email}</td><td>{label(i.role)}</td><td>{i.accepted_at ? "Accepted" : i.revoked_at ? "Revoked" : new Date(i.expires_at) < new Date() ? "Expired" : "Pending"}</td></tr>
            ))}</tbody>
          </table>
          {!d.invitations.length && <div className="empty">None.</div>}
        </div>
        <div className="card scroll">
          <h2>Support tickets</h2>
          <table>
            <tbody>{d.tickets.map((t: any) => (
              <tr key={t.id}><td><Link href={`/support/${t.id}`}>{t.subject}</Link></td><td><Badge value={t.status} /></td><td>{date(t.updated_at)}</td></tr>
            ))}</tbody>
          </table>
          {!d.tickets.length && <div className="empty">None.</div>}
        </div>
      </div>
    </>
  );
}
