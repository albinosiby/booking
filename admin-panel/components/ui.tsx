import Link from "next/link";
import { label } from "../lib/format";
const tone: Record<string, string> = {
  active: "ok", resolved: "ok", closed: "", published: "ok", confirmed: "ok", completed: "ok",
  requested: "warn", open: "warn", in_review: "warn", in_progress: "warn", setting_up: "warn", draft: "warn",
  rejected: "bad", cancelled: "bad", paused: "bad", no_show: "bad",
};
export function Badge({ value }: { value: string }) {
  return <span className={`badge ${tone[value] ?? ""}`}>{label(value)}</span>;
}
export function Tabs({ base, current, items }: { base: string; current?: string; items: string[] }) {
  return (
    <div className="tabs">
      <Link className={!current ? "on" : ""} href={base}>All</Link>
      {items.map((s) => (
        <Link key={s} className={current === s ? "on" : ""} href={`${base}?status=${s}`}>{label(s)}</Link>
      ))}
    </div>
  );
}
export function SearchBox({ q, placeholder }: { q?: string; placeholder: string }) {
  return (
    <form className="row" style={{ marginBottom: 14 }}>
      <input name="q" defaultValue={q} placeholder={placeholder} />
      <button className="ghost">Search</button>
    </form>
  );
}
