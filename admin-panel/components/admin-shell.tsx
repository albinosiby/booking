"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useRef, useState } from "react";
import { signOut } from "../app/actions";
import { Brand, Icon, type IconName } from "./icon";

const links: { href: string; label: string; icon: IconName; group: string }[] =
  [
    { href: "/", label: "Overview", icon: "overview", group: "Workspace" },
    {
      href: "/organizations",
      label: "Organizations",
      icon: "organizations",
      group: "Workspace",
    },
    { href: "/users", label: "Users", icon: "users", group: "Workspace" },
    {
      href: "/support",
      label: "Support inbox",
      icon: "support",
      group: "Operations",
    },
    {
      href: "/agent-requests",
      label: "Agent calls",
      icon: "phone",
      group: "Operations",
    },
    { href: "/audit", label: "Audit log", icon: "audit", group: "Operations" },
  ];

export function AdminShell({
  children,
  role,
}: {
  children: React.ReactNode;
  role: string;
}) {
  const path = usePathname().replace(/^\/admin(?=\/|$)/, "") || "/";
  const active =
    links.find((link) =>
      link.href === "/" ? path === "/" : path.startsWith(link.href),
    ) ?? links[0];
  const dialog = useRef<HTMLDialogElement>(null);
  const [open, setOpen] = useState(false);
  function close() {
    dialog.current?.close();
    setOpen(false);
  }
  function navigation(mobile = false) {
    return (
      <>
        <div className="sidebar-brand">
          <Brand />
          {mobile && (
            <button
              className="icon-button"
              aria-label="Close navigation"
              onClick={close}
            >
              <Icon name="close" />
            </button>
          )}
        </div>
        <nav aria-label={mobile ? "Mobile navigation" : "Main navigation"}>
          {["Workspace", "Operations"].map((group) => (
            <div className="nav-group" key={group}>
              <p className="nav-label">{group}</p>
              {links
                .filter((link) => link.group === group)
                .map((link) => (
                  <Link
                    key={link.href}
                    href={link.href}
                    className={`nav-link ${active.href === link.href ? "is-active" : ""}`}
                    aria-current={
                      active.href === link.href ? "page" : undefined
                    }
                    onClick={mobile ? close : undefined}
                  >
                    <Icon name={link.icon} />
                    <span>{link.label}</span>
                    {active.href === link.href && (
                      <span className="nav-active-dot" />
                    )}
                  </Link>
                ))}
            </div>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="workspace-note">
            <span className="small-icon">
              <Icon name="lock" size={17} />
            </span>
            <div>
              <b>Your admin workspace</b>
              <p>One place. Everything in view.</p>
            </div>
          </div>
          <div className="profile">
            <span className="avatar">TA</span>
            <div>
              <b>Platform admin</b>
              <small>{role.replaceAll("_", " ")}</small>
            </div>
          </div>
          <form action={signOut}>
            <button className="sign-out">
              <Icon name="logout" size={17} /> Sign out
            </button>
          </form>
        </div>
      </>
    );
  }
  return (
    <div className="shell">
      <a href="#main-content" className="skip-link">
        Skip to content
      </a>
      <aside className="sidebar">{navigation()}</aside>
      <dialog
        ref={dialog}
        className="mobile-nav"
        aria-label="Navigation"
        onClose={() => setOpen(false)}
        onClick={(event) => {
          if (event.target === event.currentTarget) close();
        }}
      >
        <div className="mobile-nav-body">{navigation(true)}</div>
      </dialog>
      <div className="workspace">
        <header className="topbar">
          <div className="topbar-left">
            <button
              className="icon-button menu-toggle"
              aria-label="Open navigation"
              aria-expanded={open}
              onClick={() => {
                dialog.current?.showModal();
                setOpen(true);
              }}
            >
              <Icon name="menu" />
            </button>
            <span className="breadcrumb-root">Workspace</span>
            <Icon name="chevron" size={13} />
            <span className="breadcrumb-current">{active.label}</span>
          </div>
          <div className="topbar-right">
            <a href="/" target="_blank" rel="noreferrer" className="site-link">
              Public website <Icon name="external" size={15} />
            </a>
            <span className="topbar-divider" />
            <span className="topbar-avatar" title="Platform admin">
              TA
            </span>
          </div>
        </header>
        <main id="main-content" tabIndex={-1}>
          {children}
          <footer className="workspace-footer">
            <span>
              BookingOS <span className="footer-dot">·</span> Admin workspace
            </span>
            <span>Built for a clearer overview.</span>
          </footer>
        </main>
      </div>
    </div>
  );
}
