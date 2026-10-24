import type { CSSProperties } from "react";
import { adminPath } from "../lib/paths";

export type IconName =
  | "overview"
  | "organizations"
  | "users"
  | "support"
  | "phone"
  | "audit"
  | "arrow"
  | "external"
  | "logout"
  | "menu"
  | "close"
  | "search"
  | "lock"
  | "eye"
  | "eyeOff"
  | "booking"
  | "business"
  | "check"
  | "chevron";

const paths: Record<IconName, React.ReactNode> = {
  overview: (
    <>
      <rect x="3" y="3" width="7" height="7" rx="1.5" />
      <rect x="14" y="3" width="7" height="7" rx="1.5" />
      <rect x="3" y="14" width="7" height="7" rx="1.5" />
      <rect x="14" y="14" width="7" height="7" rx="1.5" />
    </>
  ),
  organizations: (
    <>
      <path d="M4 21V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v16M16 9h3a1 1 0 0 1 1 1v11M2 21h20M8 7h4M8 11h4M8 15h4M9 21v-3h2v3" />
    </>
  ),
  users: (
    <>
      <circle cx="9" cy="8" r="3" />
      <path d="M3 21v-2a6 6 0 0 1 12 0v2M16 5a3 3 0 0 1 0 6M21 21v-2a6 6 0 0 0-4-5.65" />
    </>
  ),
  support: (
    <>
      <path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5H4l-2 2v-9.5A8.5 8.5 0 0 1 10.5 4h2A8.5 8.5 0 0 1 21 11.5Z" />
      <path d="M7 10h9M7 14h6" />
    </>
  ),
  phone: (
    <path d="m8 3 3 5-2 2a15 15 0 0 0 5 5l2-2 5 3c0 4-3 5-5 4A23 23 0 0 1 4 8C3 6 4 3 8 3Z" />
  ),
  audit: (
    <>
      <path d="M8 4H5a1 1 0 0 0-1 1v16h16V5a1 1 0 0 0-1-1h-3M8 10h8M8 14h8M8 18h5" />
      <rect x="8" y="2" width="8" height="4" rx="1" />
    </>
  ),
  arrow: <path d="M5 12h14m-5-5 5 5-5 5" />,
  external: (
    <>
      <path d="M14 3h7v7m0-7L10 14M10 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-5" />
    </>
  ),
  logout: <path d="M9 3H4v18h5M9 12h12m-5-5 5 5-5 5" />,
  menu: <path d="M4 6h16M4 12h16M4 18h16" />,
  close: <path d="m6 6 12 12M6 18 18 6" />,
  search: (
    <>
      <circle cx="10.5" cy="10.5" r="6.5" />
      <path d="m16 16 5 5" />
    </>
  ),
  lock: (
    <>
      <rect x="5" y="10" width="14" height="11" rx="2" />
      <path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3" />
    </>
  ),
  eye: (
    <>
      <path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z" />
      <circle cx="12" cy="12" r="3" />
    </>
  ),
  eyeOff: (
    <>
      <path d="m3 3 18 18M10 5c7-1 12 7 12 7a22 22 0 0 1-4 4M6 6a22 22 0 0 0-4 6s4 7 10 7a12 12 0 0 0 5-1M10 10a3 3 0 0 0 4 4" />
    </>
  ),
  booking: (
    <>
      <rect x="3" y="5" width="18" height="16" rx="2" />
      <path d="M7 3v4M17 3v4M3 11h18m-13 5 3 3 5-5" />
    </>
  ),
  business: (
    <>
      <rect x="3" y="7" width="18" height="14" rx="2" />
      <path d="M8 7V3h8v4M3 12a25 25 0 0 0 18 0M10 13h4v3h-4Z" />
    </>
  ),
  check: <path d="m5 12 4 4L19 6" />,
  chevron: <path d="m9 5 7 7-7 7" />,
};

export function Icon({
  name,
  size = 20,
  className,
  style,
}: {
  name: IconName;
  size?: number;
  className?: string;
  style?: CSSProperties;
}) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={className}
      style={style}
    >
      {paths[name]}
    </svg>
  );
}

export function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <div className="brand">
      <span className="brand-mark" aria-hidden="true">
        <img src={adminPath("/booking-os-logo.png")} width={36} height={36} alt="" />
      </span>
      {!compact && (
        <span className="brand-word">
          booking<span>os</span>
          <small>ADMIN WORKSPACE</small>
        </span>
      )}
    </div>
  );
}
