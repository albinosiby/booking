CREATE TABLE platform_admins (
 user_id text PRIMARY KEY,
 email text NOT NULL UNIQUE CHECK(email = lower(email)),
 role text NOT NULL DEFAULT 'support' CHECK(role IN ('super_admin','support')),
 active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE support_tickets (
 id uuid PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES organizations(id),
 membership_id uuid NOT NULL,
 category text NOT NULL DEFAULT 'other' CHECK(category IN ('booking','payments','team','website','agent_calls','other')),
 subject text NOT NULL CHECK(length(subject) BETWEEN 3 AND 160),
 status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','in_progress','resolved','closed')),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(membership_id,organization_id) REFERENCES memberships(id,organization_id)
);
CREATE INDEX support_tickets_status_idx ON support_tickets(status,updated_at DESC);
CREATE INDEX support_tickets_org_idx ON support_tickets(organization_id,updated_at DESC);
CREATE TABLE support_messages (
 id uuid PRIMARY KEY,
 ticket_id uuid NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
 author text NOT NULL CHECK(author IN ('user','admin')),
 author_name text NOT NULL DEFAULT '',
 body text NOT NULL CHECK(length(body) BETWEEN 1 AND 4000),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX support_messages_ticket_idx ON support_messages(ticket_id,created_at);
CREATE TABLE agent_call_requests (
 id uuid PRIMARY KEY,
 organization_id uuid NOT NULL UNIQUE REFERENCES organizations(id),
 membership_id uuid NOT NULL,
 status text NOT NULL DEFAULT 'requested' CHECK(status IN ('requested','in_review','setting_up','active','paused','rejected')),
 note text NOT NULL DEFAULT '' CHECK(length(note)<=2000),
 admin_note text NOT NULL DEFAULT '' CHECK(length(admin_note)<=2000),
 user_message text NOT NULL DEFAULT '' CHECK(length(user_message)<=500),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(membership_id,organization_id) REFERENCES memberships(id,organization_id)
);
CREATE INDEX agent_call_requests_status_idx ON agent_call_requests(status,updated_at DESC);
CREATE TABLE admin_audit_log (
 id uuid PRIMARY KEY,
 admin_email text NOT NULL,
 action text NOT NULL,
 target_type text NOT NULL,
 target_id text NOT NULL,
 detail jsonb NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX admin_audit_log_created_idx ON admin_audit_log(created_at DESC);
