import Link from "next/link";
import { admin } from "../../lib/api";

export default async function Overview() {
  const o = await admin<Record<string, number>>("/overview");
  const stats: [string, string][] = [
    ["organizations", "Organizations"], ["users", "Users"], ["active_users", "Active users"],
    ["businesses", "Businesses"], ["bookings", "Bookings"], ["customers", "Customers"],
    ["open_tickets", "Open support tickets"], ["pending_agent_requests", "Pending agent-call requests"],
  ];
  return (
    <>
      <h1>Overview</h1>
      <p className="sub">Platform-wide totals.</p>
      <div className="grid">
        {stats.map(([k, name]) => (
          <div className="stat" key={k}><b>{o[k]}</b><span>{name}</span></div>
        ))}
      </div>
      <div className="row">
        <Link className="btn" href="/support?status=open">Review open tickets</Link>
        <Link className="btn" href="/agent-requests?status=requested">Review call requests</Link>
      </div>
    </>
  );
}
