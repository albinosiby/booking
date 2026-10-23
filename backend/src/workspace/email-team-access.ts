import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from "@nestjs/common";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { Actor } from "../common/auth.guard";
import type { Database, Queryable } from "../common/database";
import { invitationSchema } from "./validation";
import {
  NodemailerTeamAccessMailer,
  TeamAccessMailer,
  TeamAccessNotice,
} from "./team-access-mailer";

type Row = Record<string, any>;
type Assignments = Array<{ business_id: string; resource_ids: string[] }>;
type AccessHooks = {
  owner(actor: Actor, db: Queryable): Promise<Row>;
  validate(db: Queryable, org: string, assignments: Assignments): Promise<void>;
  audit(
    db: Queryable,
    actor: Actor,
    org: string,
    action: string,
    id: string,
  ): Promise<void>;
};

/** Pending email grants are separate from legacy token invitations. */
export class EmailTeamAccess {
  mailer: TeamAccessMailer = new NodemailerTeamAccessMailer();
  constructor(
    private readonly db: Database,
    private readonly hooks: AccessHooks,
  ) {}
  private async lockEmail(db: Queryable, email: string) {
    await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [
      `team-email:${email}`,
    ]);
  }
  async add(actor: Actor, input: unknown) {
    const v = invitationSchema.parse(input);
    const id = await this.db.transaction(async (db) => {
      const owner = await this.hooks.owner(actor, db);
      await this.lockEmail(db, v.email);
      await this.hooks.validate(db, owner.organization_id, v.assignments);
      if (
        (
          await db.query(
            "SELECT id FROM memberships WHERE lower(email)=$1 AND active=true",
            [v.email],
          )
        ).rows.length
      )
        throw new ConflictException(
          "This email already has active organization access.",
        );
      if (
        (
          await db.query(
            "SELECT id FROM memberships WHERE lower(email)=$1 AND organization_id<>$2",
            [v.email, owner.organization_id],
          )
        ).rows.length
      )
        throw new ConflictException(
          "This email belongs to another organization. Contact the previous owner before moving access.",
        );
      if (
        (
          await db.query(
            "SELECT id FROM invitations WHERE lower(email)=$1 AND organization_id<>$2 AND join_mode='email_login' AND accepted_at IS NULL AND revoked_at IS NULL",
            [v.email, owner.organization_id],
          )
        ).rows.length
      )
        throw new ConflictException(
          "This email already has pending access to another organization.",
        );
      const previous = (
        await db.query<Row>(
          "SELECT id FROM invitations WHERE organization_id=$1 AND email=$2 AND join_mode='email_login' AND accepted_at IS NULL AND revoked_at IS NULL",
          [owner.organization_id, v.email],
        )
      ).rows[0];
      if (previous)
        throw new ConflictException(
          "This person is already awaiting sign-in. Edit their access or resend their email from Team.",
        );
      await db.query(
        "UPDATE invitations SET revoked_at=now() WHERE organization_id=$1 AND email=$2 AND accepted_at IS NULL AND revoked_at IS NULL",
        [owner.organization_id, v.email],
      );
      const id = randomUUID();
      const tokenHash = createHash("sha256")
        .update(randomBytes(32))
        .digest("hex");
      await db.query(
        "INSERT INTO invitations(id,organization_id,email,display_name,role,permissions,assignments,token_hash,expires_at,join_mode,email_status) VALUES($1,$2,$3,$4,$5,$6,$7,$8,'infinity','email_login','pending')",
        [
          id,
          owner.organization_id,
          v.email,
          v.display_name,
          v.role,
          JSON.stringify(v.permissions),
          JSON.stringify(v.assignments),
          tokenHash,
        ],
      );
      await this.hooks.audit(
        db,
        actor,
        owner.organization_id,
        "staff.added_by_email",
        id,
      );
      return id;
    });
    return { id, ...(await this.deliver(actor, id)) };
  }
  async update(actor: Actor, id: string, input: unknown) {
    const v = invitationSchema.parse(input);
    await this.db.transaction(async (db) => {
      const owner = await this.hooks.owner(actor, db);
      const row = (
        await db.query<Row>(
          "SELECT * FROM invitations WHERE id=$1 AND organization_id=$2 AND join_mode='email_login' AND accepted_at IS NULL AND revoked_at IS NULL FOR UPDATE",
          [id, owner.organization_id],
        )
      ).rows[0];
      if (!row)
        throw new NotFoundException(
          "Pending team access is unavailable. Refresh Team.",
        );
      if (row.email !== v.email)
        throw new BadRequestException(
          "Cancel this entry and add the correct email instead.",
        );
      await this.hooks.validate(db, owner.organization_id, v.assignments);
      await db.query(
        "UPDATE invitations SET display_name=$1,role=$2,permissions=$3,assignments=$4,email_status='pending',email_attempt_id=NULL WHERE id=$5",
        [
          v.display_name,
          v.role,
          JSON.stringify(v.permissions),
          JSON.stringify(v.assignments),
          id,
        ],
      );
      await this.hooks.audit(
        db,
        actor,
        owner.organization_id,
        "staff.pending_access_updated",
        id,
      );
    });
    return { id, ...(await this.deliver(actor, id)) };
  }
  async deliver(actor: Actor, id: string) {
    const attempt = randomUUID();
    const notice = await this.db.transaction(
      async (db): Promise<TeamAccessNotice> => {
        const owner = await this.hooks.owner(actor, db);
        const row = (
          await db.query<Row>(
            "UPDATE invitations SET email_status='sending',email_attempt_id=$1,email_attempted_at=now() WHERE id=$2 AND organization_id=$3 AND join_mode='email_login' AND accepted_at IS NULL AND revoked_at IS NULL AND (email_status<>'sending' OR email_attempted_at<now()-interval '2 minutes') AND (email_attempted_at IS NULL OR email_attempted_at<now()-interval '30 seconds' OR email_status='pending') RETURNING *",
            [attempt, id, owner.organization_id],
          )
        ).rows[0];
        if (!row)
          throw new ConflictException(
            "Email was sent recently or this entry changed. Wait 30 seconds and refresh Team.",
          );
        const organization = (
          await db.query<Row>("SELECT name FROM organizations WHERE id=$1", [
            owner.organization_id,
          ])
        ).rows[0];
        const businesses = (
          await db.query<Row>(
            "SELECT b.id,b.name,COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'name',r.name) ORDER BY r.name) FROM resources r WHERE r.business_id=b.id),'[]'::jsonb) AS resources FROM businesses b WHERE b.organization_id=$1",
            [owner.organization_id],
          )
        ).rows;
        return {
          email: row.email,
          name: row.display_name,
          organization: organization.name,
          role: row.role,
          permissions: row.permissions,
          assignments: row.assignments.map((a: Assignments[number]) => {
            const b = businesses.find((b) => b.id === a.business_id);
            return {
              business: b?.name || "Assigned business",
              resources: a.resource_ids.length
                ? b?.resources
                    .filter((r: Row) => a.resource_ids.includes(r.id))
                    .map((r: Row) => r.name) || []
                : [],
            };
          }),
        };
      },
    );
    let delivery: "sent" | "failed" = "sent";
    try {
      await this.mailer.send(notice);
    } catch {
      delivery = "failed";
    }
    // Delivery failure never undoes the owner's access grant. A crash leaves a
    // visible sending status that the owner can retry after the lease expires.
    await this.db.query(
      "UPDATE invitations SET email_status=$1,email_sent_at=CASE WHEN $1='sent' THEN now() ELSE email_sent_at END WHERE id=$2 AND email_attempt_id=$3",
      [delivery, id, attempt],
    );
    return { delivery };
  }
  async join(actor: Actor) {
    await this.db.transaction(async (db) => {
      const email = actor.email.toLowerCase();
      await this.lockEmail(db, email);
      const previous = (
        await db.query<Row>(
          "SELECT * FROM memberships WHERE user_id=$1 FOR UPDATE",
          [actor.uid],
        )
      ).rows[0];
      if (previous?.active) return;
      if (
        (
          await db.query(
            "SELECT id FROM memberships WHERE lower(email)=$1 AND active=true AND user_id<>$2",
            [email, actor.uid],
          )
        ).rows.length
      )
        throw new ConflictException(
          "This email already belongs to an active team account. Contact the owner.",
        );
      const i = (
        await db.query<Row>(
          "SELECT * FROM invitations WHERE lower(email)=$1 AND join_mode='email_login' AND accepted_at IS NULL AND revoked_at IS NULL FOR UPDATE",
          [email],
        )
      ).rows[0];
      if (!i) return;
      if (previous && previous.organization_id !== i.organization_id)
        throw new ConflictException(
          "This account belongs to another organization. Contact the owner.",
        );
      await this.hooks.validate(db, i.organization_id, i.assignments);
      const id = previous?.id || randomUUID();
      if (previous) {
        await db.query("DELETE FROM staff_assignments WHERE membership_id=$1", [
          id,
        ]);
        await db.query(
          "UPDATE memberships SET active=true,email=$1,display_name=$2,role=$3,permissions=$4 WHERE id=$5",
          [email, i.display_name, i.role, JSON.stringify(i.permissions), id],
        );
      } else {
        await db.query(
          "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,$5,$6,$7)",
          [
            id,
            i.organization_id,
            actor.uid,
            email,
            i.display_name,
            i.role,
            JSON.stringify(i.permissions),
          ],
        );
      }
      for (const a of i.assignments)
        await db.query(
          "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,$4)",
          [
            id,
            i.organization_id,
            a.business_id,
            JSON.stringify(a.resource_ids),
          ],
        );
      await db.query("UPDATE invitations SET accepted_at=now() WHERE id=$1", [
        i.id,
      ]);
      await this.hooks.audit(
        db,
        actor,
        i.organization_id,
        "staff.activated_on_sign_in",
        id,
      );
    });
  }
}
