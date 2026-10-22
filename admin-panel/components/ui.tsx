import Link from "next/link";
import { label } from "../lib/format";
import { Icon, type IconName } from "./icon";
const tone: Record<string, string> = {
  active: "ok",
  resolved: "ok",
  closed: "",
  published: "ok",
  confirmed: "ok",
  completed: "ok",
  requested: "warn",
  open: "warn",
  in_review: "warn",
  in_progress: "warn",
  setting_up: "warn",
  draft: "warn",
  rejected: "bad",
  cancelled: "bad",
  paused: "bad",
  no_show: "bad",
};
export function Badge({ value }: { value: string }) {
  return (
    <span className={`badge ${tone[value] ?? ""}`}>
      <span className="badge-dot" />
      {label(value)}
    </span>
  );
}
export function Tabs({
  base,
  current,
  items,
}: {
  base: string;
  current?: string;
  items: string[];
}) {
  return (
    <div className="tabs" role="navigation" aria-label="Filter by status">
      <Link
        className={!current ? "on" : ""}
        aria-current={!current ? "page" : undefined}
        href={base}
      >
        All
      </Link>
      {items.map((s) => (
        <Link
          key={s}
          className={current === s ? "on" : ""}
          aria-current={current === s ? "page" : undefined}
          href={`${base}?status=${s}`}
        >
          {label(s)}
        </Link>
      ))}
    </div>
  );
}
export function SearchBox({
  q,
  placeholder,
}: {
  q?: string;
  placeholder: string;
}) {
  return (
    <form className="search-form" role="search">
      <div className="search-input">
        <Icon name="search" size={18} />
        <input
          name="q"
          defaultValue={q}
          placeholder={placeholder}
          aria-label={placeholder}
        />
      </div>
      <button className="ghost">Search</button>
    </form>
  );
}

export function PageHeader({
  title,
  description,
  children,
}: {
  title: string;
  description: React.ReactNode;
  children?: React.ReactNode;
}) {
  return (
    <div className="page-heading">
      <div>
        <h1>{title}</h1>
        <p className="sub">{description}</p>
      </div>
      {children}
    </div>
  );
}

export function EmptyState({
  icon = "overview",
  title,
  description,
}: {
  icon?: IconName;
  title: string;
  description: string;
}) {
  return (
    <div className="empty-state">
      <span>
        <Icon name={icon} size={24} />
      </span>
      <h3>{title}</h3>
      <p>{description}</p>
    </div>
  );
}
