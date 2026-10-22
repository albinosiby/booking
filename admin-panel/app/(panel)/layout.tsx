import Link from "next/link";
import { admin } from "../../lib/api";
import { signOut } from "../actions";

const links: [string, string][] = [
  ["/", "Overview"],
  ["/organizations", "Organizations"],
  ["/users", "Users"],
  ["/support", "Support"],
  ["/agent-requests", "Agent calls"],
  ["/audit", "Audit log"],
];
export default async function PanelLayout({ children }: { children: React.ReactNode }) {
  const me = await admin<{ email: string; role: string }>("/me");
  return (
    <div className="shell">
      <nav className="side">
        <div className="brand">Booking Admin</div>
        {links.map(([href, name]) => (
          <Link key={href} href={href}>{name}</Link>
        ))}
        <div className="grow" />
        <div className="who">{me.email}<br />{me.role.replace("_", " ")}</div>
        <form action={signOut}><button className="ghost" style={{ width: "100%", color: "#dfe3ea", borderColor: "#ffffff30" }}>Sign out</button></form>
      </nav>
      <main>{children}</main>
    </div>
  );
}
