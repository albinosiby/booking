import Link from "next/link";
import { admin } from "../../lib/api";
import { date } from "../../lib/format";
import { Icon, type IconName } from "../../components/icon";
import { EmptyState } from "../../components/ui";
import { overviewTotals, type OverviewTotals } from "../../lib/overview";

type Organization = {
  id: string;
  name: string;
  owner_email: string | null;
  businesses: number;
  created_at: string;
};
const number = (value: number) => new Intl.NumberFormat("en-IN").format(value);

export default async function Overview() {
  const [response, { organizations }] = await Promise.all([
    admin<unknown>("/overview"),
    admin<{ organizations: Organization[] }>("/organizations?limit=5"),
  ]);
  const o = overviewTotals(response);
  const stats: {
    key: keyof OverviewTotals;
    label: string;
    icon: IconName;
    note: string;
    tone: string;
  }[] = [
    {
      key: "organizations",
      label: "Organizations",
      icon: "organizations",
      note: "Workspaces on your platform",
      tone: "green",
    },
    {
      key: "users",
      label: "Total users",
      icon: "users",
      note: `${number(o.active_users)} active users`,
      tone: "blue",
    },
    {
      key: "businesses",
      label: "Businesses",
      icon: "business",
      note: "Across all organizations",
      tone: "violet",
    },
    {
      key: "bookings",
      label: "Bookings",
      icon: "booking",
      note: "Bookings made to date",
      tone: "amber",
    },
  ];
  const activePercent =
    o.users > 0
      ? Math.min(100, Math.round((o.active_users / o.users) * 100))
      : 0;
  return (
    <>
      <div className="page-heading overview-heading">
        <div>
          <p className="eyebrow">PLATFORM OVERVIEW</p>
          <h1>Your platform, at a glance.</h1>
          <p className="sub">Platform-wide totals, all in one place.</p>
        </div>
        <span className="snapshot">
          <span /> Loaded {date(new Date().toISOString())}
        </span>
      </div>
      <div className="metric-grid">
        {stats.map((stat) => (
          <article className="metric-card" key={stat.key}>
            <div className="metric-top">
              <span>{stat.label}</span>
              <span className={`metric-icon ${stat.tone}`}>
                <Icon name={stat.icon} />
              </span>
            </div>
            <strong>{number(o[stat.key])}</strong>
            <p>
              <span className="metric-note-dot" />
              {stat.note}
            </p>
          </article>
        ))}
      </div>
      <section
        className="attention-section"
        aria-labelledby="attention-heading"
      >
        <div className="section-heading">
          <h2 id="attention-heading">Your next steps</h2>
          <span>A quick look at what needs attention</span>
        </div>
        <div className="attention-grid">
          <Link className="attention-card" href="/support?status=open">
            <span className="attention-icon green">
              <Icon name="support" size={23} />
            </span>
            <div className="attention-copy">
              <h3>
                Support inbox{" "}
                <span className="count-pill">{number(o.open_tickets)}</span>
              </h3>
              <p>
                {o.open_tickets
                  ? "Open conversations waiting for your team."
                  : "All caught up. No open support tickets."}
              </p>
            </div>
            <Icon name="arrow" className="attention-arrow" />
          </Link>
          <Link
            className="attention-card"
            href="/agent-requests?status=requested"
          >
            <span className="attention-icon blue">
              <Icon name="phone" size={23} />
            </span>
            <div className="attention-copy">
              <h3>
                Agent call requests{" "}
                <span className="count-pill">
                  {number(o.pending_agent_requests)}
                </span>
              </h3>
              <p>
                {o.pending_agent_requests
                  ? "Review requests and move setup forward."
                  : "You're up to date. No pending requests."}
              </p>
            </div>
            <Icon name="arrow" className="attention-arrow" />
          </Link>
        </div>
      </section>
      <div className="overview-bottom">
        <section className="card recent-organizations">
          <div className="card-heading">
            <div>
              <h2>Recent organizations</h2>
              <p>The latest workspaces to join your platform.</p>
            </div>
            <Link className="text-link" href="/organizations">
              View all <Icon name="arrow" size={16} />
            </Link>
          </div>
          <div className="scroll">
            <table>
              <thead>
                <tr>
                  <th>Organization</th>
                  <th>Businesses</th>
                  <th>Joined</th>
                  <th>
                    <span className="sr-only">Details</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {organizations.map((org, i) => (
                  <tr key={org.id}>
                    <td>
                      <Link
                        href={`/organizations/${org.id}`}
                        className="organization-cell"
                      >
                        <span
                          className={`organization-avatar avatar-tone-${i % 4}`}
                        >
                          {org.name.slice(0, 1).toUpperCase()}
                        </span>
                        <span>
                          <b>{org.name}</b>
                          <small>
                            {org.owner_email || "Owner email unavailable"}
                          </small>
                        </span>
                      </Link>
                    </td>
                    <td className="numeric">{number(org.businesses)}</td>
                    <td className="nowrap muted">{date(org.created_at)}</td>
                    <td>
                      <Link
                        href={`/organizations/${org.id}`}
                        className="row-link"
                        aria-label={`View ${org.name}`}
                      >
                        <Icon name="chevron" size={17} />
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {!organizations.length && (
            <EmptyState
              icon="organizations"
              title="A fresh start"
              description="Organizations will appear here when they join your platform."
            />
          )}
        </section>
        <section className="card people-card">
          <span className="people-icon">
            <Icon name="users" size={23} />
          </span>
          <h2>People & access</h2>
          <p className="sub">A closer look at your community.</p>
          <div className="people-total">
            <strong>{number(o.customers)}</strong>
            <span>Customers across the platform</span>
          </div>
          <div className="people-active">
            <div>
              <span>Active users</span>
              <b>
                {number(o.active_users)} <small>/ {number(o.users)}</small>
              </b>
            </div>
            <div
              className="progress-track"
              role="progressbar"
              aria-label="Active users"
              aria-valuenow={activePercent}
              aria-valuemin={0}
              aria-valuemax={100}
            >
              <span style={{ width: `${activePercent}%` }} />
            </div>
            <p>{activePercent}% of user memberships are active</p>
          </div>
          <Link className="people-link" href="/users">
            Manage users <Icon name="arrow" size={17} />
          </Link>
        </section>
      </div>
    </>
  );
}
