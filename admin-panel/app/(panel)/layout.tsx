import { admin } from "../../lib/api";
import { AdminShell } from "../../components/admin-shell";

export default async function PanelLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const me = await admin<{ email: string; role: string }>("/me");
  return <AdminShell role={me.role}>{children}</AdminShell>;
}
