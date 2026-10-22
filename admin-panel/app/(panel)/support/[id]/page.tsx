import Link from "next/link";
import { admin } from "../../../../lib/api";
import { date, label } from "../../../../lib/format";
import { Badge } from "../../../../components/ui";
import { replyToTicket, setTicketStatus } from "../../../actions";

export default async function Ticket({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { ticket: t, messages } = await admin<{ ticket: any; messages: any[] }>(`/support/tickets/${id}`);
  return (
    <>
      <p className="sub"><Link href="/support">← Support</Link></p>
      <h1>{t.subject}</h1>
      <p className="sub">
        <Badge value={t.status} /> · {label(t.category)} · {t.user_name} ({t.user_email}) ·{" "}
        <Link href={`/organizations/${t.organization_id}`}>{t.organization_name}</Link> · opened {date(t.created_at)}
      </p>
      <div className="card">
        {messages.map((m) => (
          <div key={m.id} className={`msg ${m.author}`}>
            <small>{m.author === "admin" ? `Support (${m.author_name})` : t.user_name} · {date(m.created_at)}</small>
            <p>{m.body}</p>
          </div>
        ))}
        {!messages.length && <div className="empty">No messages.</div>}
      </div>
      <div className="two">
        <form className="card" action={replyToTicket} style={{ display: "grid", gap: 10 }}>
          <h2>Reply</h2>
          <input type="hidden" name="id" value={id} />
          <textarea name="body" required maxLength={4000} placeholder="Write a reply the user will see in the app" />
          <div><button>Send reply</button></div>
        </form>
        <form className="card" action={setTicketStatus} style={{ display: "grid", gap: 10, alignContent: "start" }}>
          <h2>Status</h2>
          <input type="hidden" name="id" value={id} />
          <select name="status" defaultValue={t.status}>
            {["open", "in_progress", "resolved", "closed"].map((s) => <option key={s} value={s}>{label(s)}</option>)}
          </select>
          <div><button>Update status</button></div>
        </form>
      </div>
    </>
  );
}
