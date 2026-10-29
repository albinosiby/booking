import { ensureWebsiteDraft } from "../website/website.validation";
import { EmailTeamAccess } from "./email-team-access";
import { z } from "zod";
import {
  organizationEditSchema,
  organizationSnapshot,
  organizationRevision,
  validateOrganizationLocations,
} from "./organization-edit";
import { assertHallComplete } from "../hall/hall.validation";
import { assertCourtComplete } from "../court/court.validation";
import {
  assertPlanCoaches,
  coachingConfiguration,
  releaseCoachPlans,
} from "./coach.access";
import { assertPoolComplete } from "../pool/pool.validation";
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { randomBytes, randomUUID, createHash } from "node:crypto";
import { Database, Queryable } from "../common/database";
import { Actor } from "../common/auth.guard";
import {
  businessSchema,
  businessOrderSchema,
  configSchema,
  invitationSchema,
  orgSchema,
  resourceSchema,
  logoSchema,
} from "./validation";
import { assertTurfComplete } from "../turf/turf.validation";
type Row = Record<string, any>;
const hash = (token: string) =>
  createHash("sha256").update(token).digest("hex");
@Injectable()
export class WorkspaceService {
  publicAppUrl?: string;
  readonly emailTeamAccess: EmailTeamAccess;
  constructor(private readonly db: Database) {
    this.emailTeamAccess = new EmailTeamAccess(db, {
      owner: (actor, db) => this.member(actor, true, db),
      validate: (db, org, assignments) =>
        this.validateAssignments(db, org, assignments),
      audit: (db, actor, org, action, id) =>
        this.audit(db, actor, org, action, id),
    });
  }
  /** Explicit authenticated bootstrap; ordinary GET reads never grant access. */
  async session(actor: Actor) {
    await this.emailTeamAccess.join(actor);
    return this.workspace(actor);
  }
  async member(
    actor: Actor,
    owner = false,
    db: Queryable = this.db,
    lock = false,
  ) {
    const m = (
      await db.query<Row>(
        `SELECT * FROM memberships WHERE user_id=$1 AND active=true${lock ? " FOR SHARE" : ""}`,
        [actor.uid],
      )
    ).rows[0];
    if (!m) throw new ForbiddenException("No active organization membership.");
    if (owner && m.role !== "owner")
      throw new ForbiddenException(
        "Only the owner can manage organization setup.",
      );
    return m;
  }
  async audit(
    db: Queryable,
    actor: Actor,
    org: string,
    action: string,
    id: string,
  ) {
    await db.query(
      "INSERT INTO audit_events(id,organization_id,actor_id,action,entity_id) VALUES($1,$2,$3,$4,$5)",
      [randomUUID(), org, actor.uid, action, id],
    );
  }
  async workspace(actor: Actor, includeArchived = false) {
    const member = (
      await this.db.query<Row>("SELECT * FROM memberships WHERE user_id=$1", [
        actor.uid,
      ])
    ).rows[0];
    if (member && !member.active)
      throw new ForbiddenException(
        "Your organization access has been removed. Contact the owner.",
      );
    if (!member)
      return {
        organization: null,
        businesses: [],
        locations: [],
        membership: null,
      };
    // One snapshot round trip after membership verification. Keep staff scope
    // inside SQL and retain the existing resource/configuration redaction below.
    const snapshot = (
      await this.db.query<Row>(
        `
      WITH visible AS (
        SELECT b.* FROM businesses b WHERE b.organization_id=$1
        AND ($4::boolean OR b.status<>'archived')
        AND ($3::boolean OR EXISTS (SELECT 1 FROM staff_assignments a WHERE a.membership_id=$2 AND a.business_id=b.id))
      )
      SELECT (SELECT to_jsonb(o) FROM organizations o WHERE o.id=$1) AS organization,
        COALESCE((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.display_order,b.id) FROM visible b),'[]'::jsonb) AS businesses,
        COALESCE((SELECT jsonb_agg(to_jsonb(a)) FROM staff_assignments a WHERE a.membership_id=$2),'[]'::jsonb) AS assignments,
        COALESCE((SELECT jsonb_agg(to_jsonb(l)) FROM locations l WHERE l.organization_id=$1),'[]'::jsonb) AS locations,
        COALESCE((SELECT jsonb_agg(jsonb_build_object('business_id',r.business_id,'id',r.id,'name',r.name,'capacity',r.capacity) ORDER BY r.business_id,r.name,r.id) FROM resources r JOIN visible b ON b.id=r.business_id WHERE r.organization_id=$1),'[]'::jsonb) AS resources
    `,
        [
          member.organization_id,
          member.id,
          member.role === "owner",
          includeArchived,
        ],
      )
    ).rows[0];
    const org = snapshot.organization;
    const businesses: Row[] = snapshot.businesses,
      assignments: Row[] = snapshot.assignments,
      resourceRows: Row[] = snapshot.resources;
    const resourcesByBusiness = new Map<string, Row[]>();
    for (const resource of resourceRows) {
      const items = resourcesByBusiness.get(resource.business_id) ?? [];
      items.push({
        id: resource.id,
        name: resource.name,
        capacity: resource.capacity,
      });
      resourcesByBusiness.set(resource.business_id, items);
    }
    for (const business of businesses) {
      let resources = resourcesByBusiness.get(business.id) ?? [];
      const assignment = assignments.find((a) => a.business_id === business.id);
      if (member.role !== "owner" && assignment?.resource_ids.length)
        resources = resources.filter((r) =>
          assignment.resource_ids.includes(r.id),
        );
      if (
        member.role !== "owner" &&
        assignment?.resource_ids.length &&
        business.configuration?.kind === "turf_v1"
      ) {
        const config = business.configuration;
        const ids = new Set(resources.map((r) => r.id));
        const layouts = config.layouts.filter((l: Row) => ids.has(l.id));
        const sectionIds = new Set(layouts.flatMap((l: Row) => l.section_ids));
        business.configuration = {
          ...config,
          layouts,
          offerings: config.offerings.filter((o: Row) => ids.has(o.layout_id)),
          grounds: config.grounds
            .filter((g: Row) => layouts.some((l: Row) => l.ground_id === g.id))
            .map((g: Row) => ({
              ...g,
              sections: g.sections.filter((section: Row) =>
                sectionIds.has(section.id),
              ),
            })),
        };
      }
      if (
        member.role !== "owner" &&
        business.configuration?.kind === "hall_v1" &&
        assignment?.resource_ids.length
      ) {
        const ids = new Set(resources.map((r) => r.id));
        business.configuration = {
          ...business.configuration,
          halls: business.configuration.halls.filter((p: Row) => ids.has(p.id)),
        };
      }
      if (
        member.role !== "owner" &&
        business.configuration?.kind === "court_v1" &&
        assignment?.resource_ids.length
      ) {
        const ids = new Set(resources.map((r) => r.id));
        const config = business.configuration;
        business.configuration = {
          ...config,
          courts: config.courts.filter((p: Row) => ids.has(p.id)),
          ...(config.plans
            ? {
                plans: config.plans
                  .filter((p: Row) =>
                    p.court_ids.some((id: string) => ids.has(id)),
                  )
                  .map((p: Row) => ({
                    ...p,
                    court_ids: p.court_ids.filter((id: string) => ids.has(id)),
                  })),
              }
            : {}),
        };
      }
      if (
        member.role !== "owner" &&
        assignment?.resource_ids.length &&
        business.configuration?.kind === "pool_v1"
      ) {
        const config = business.configuration,
          ids = new Set(resources.map((r) => r.id));
        business.configuration = {
          ...config,
          pools: config.pools.filter((p: Row) => ids.has(p.id)),
          group_offers: config.group_offers
            .filter((o: Row) => o.pool_ids.some((id: string) => ids.has(id)))
            .map((o: Row) => ({
              ...o,
              pool_ids: o.pool_ids.filter((id: string) => ids.has(id)),
            })),
          plans: config.plans
            .filter((p: Row) => p.pool_ids.some((id: string) => ids.has(id)))
            .map((p: Row) => ({
              ...p,
              pool_ids: p.pool_ids.filter((id: string) => ids.has(id)),
            })),
        };
      }
      business.resources = resources;
    }
    return {
      organization: org,
      locations: snapshot.locations,
      businesses,
      membership: member,
    };
  }
  private async editableOrganization(
    actor: Actor,
    db: Queryable,
    lock = false,
  ) {
    const m = await this.member(actor, true, db);
    const org = (
      await db.query<Row>(
        `SELECT id,name,contact_phone,currency FROM organizations WHERE id=$1${lock ? " FOR UPDATE" : ""}`,
        [m.organization_id],
      )
    ).rows[0];
    const locations = (
      await db.query<Row>(
        `SELECT * FROM locations WHERE organization_id=$1 ORDER BY id${lock ? " FOR UPDATE" : ""}`,
        [m.organization_id],
      )
    ).rows;
    return { m, snapshot: organizationSnapshot(org, locations) };
  }
  async organizationDetails(actor: Actor) {
    return this.db.transaction(async (db) => {
      await db.query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ");
      const { snapshot } = await this.editableOrganization(actor, db);
      return { ...snapshot, revision: organizationRevision(snapshot) };
    });
  }
  async updateOrganization(actor: Actor, input: unknown) {
    const v = organizationEditSchema.parse(input);
    return this.db.transaction(async (db) => {
      const { m, snapshot } = await this.editableOrganization(actor, db, true);
      const ids = snapshot.locations.map((l) => l.id);
      if (
        v.locations.length !== ids.length ||
        v.locations.some((l) => !ids.includes(l.id))
      )
        throw new ConflictException(
          "The organization locations changed. Reload the latest details.",
        );
      validateOrganizationLocations(v, snapshot.locations);
      const desired = organizationSnapshot(
        { ...snapshot, name: v.name, contact_phone: v.contact_phone },
        v.locations.map((l) => ({
          ...l,
          timezone: snapshot.locations.find((x) => x.id === l.id)!.timezone,
        })),
      );
      // Identical retries also succeed after a response was lost.
      if (organizationRevision(desired) === organizationRevision(snapshot))
        return { ...snapshot, revision: organizationRevision(snapshot) };
      if (v.revision !== organizationRevision(snapshot))
        throw new ConflictException(
          "Organization details were changed elsewhere. Reload the latest details before saving.",
        );
      await db.query(
        "UPDATE organizations SET name=$1,contact_phone=$2 WHERE id=$3",
        [v.name, v.contact_phone, m.organization_id],
      );
      for (const l of v.locations)
        await db.query(
          "UPDATE locations SET name=$1,address_line_1=$2,address_line_2=$3,city=$4,state_code=$5,country_code=$6,postal_code=$7 WHERE id=$8 AND organization_id=$9",
          [
            l.name,
            l.address_line_1,
            l.address_line_2,
            l.city,
            l.state_code,
            l.country_code,
            l.postal_code,
            l.id,
            m.organization_id,
          ],
        );
      await this.audit(
        db,
        actor,
        m.organization_id,
        "organization.updated",
        m.organization_id,
      );
      return { ...desired, revision: organizationRevision(desired) };
    });
  }
  async createOrganization(actor: Actor, input: unknown) {
    const v = orgSchema.parse(input);
    return this.db.transaction(async (db) => {
      const existing = (
        await db.query("SELECT id FROM memberships WHERE user_id=$1", [
          actor.uid,
        ])
      ).rows;
      if (existing.length)
        throw new ConflictException(
          "This account already belongs to an organization.",
        );
      const id = randomUUID(),
        location = randomUUID();
      await db.query(
        "INSERT INTO organizations(id,name,contact_phone,currency,created_by) VALUES($1,$2,$3,$4,$5)",
        [id, v.name, v.contact_phone, v.currency, actor.uid],
      );
      const l = v.location;
      await db.query(
        "INSERT INTO locations(id,organization_id,name,address_line_1,address_line_2,city,state_code,country_code,postal_code,timezone) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",
        [
          location,
          id,
          l.name,
          l.address_line_1,
          l.address_line_2,
          l.city,
          l.state_code,
          l.country_code,
          l.postal_code,
          l.timezone,
        ],
      );
      await db.query(
        "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,$5,$6,$7)",
        [
          randomUUID(),
          id,
          actor.uid,
          actor.email,
          actor.name,
          "owner",
          JSON.stringify([
            "view_bookings",
            "manage_bookings",
            "collect_payments",
            "manage_attendance",
            "record_expenses",
            "view_finance",
          ]),
        ],
      );
      await ensureWebsiteDraft(db, {
        id,
        name: v.name,
        contact_phone: v.contact_phone,
      });
      await this.audit(db, actor, id, "organization.created", id);
      return { id };
    });
  }
  async createBusiness(actor: Actor, input: unknown) {
    const v = businessSchema.parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, true, db);
      if (
        !(
          await db.query(
            "SELECT id FROM locations WHERE id=$1 AND organization_id=$2",
            [v.location_id, m.organization_id],
          )
        ).rows.length
      )
        throw new BadRequestException("Select an organization location.");
      // Serialize additions and reorders on the organization, so new businesses
      // append once and stale editors cannot omit a newly-created business.
      await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
        m.organization_id,
      ]);
      const next = (
        await db.query<Row>(
          "SELECT COALESCE(max(display_order),-1)+1 AS position FROM businesses WHERE organization_id=$1",
          [m.organization_id],
        )
      ).rows[0].position;
      const id = randomUUID();
      await db.query(
        "INSERT INTO businesses(id,organization_id,location_id,name,type,display_order) VALUES($1,$2,$3,$4,$5,$6)",
        [id, m.organization_id, v.location_id, v.name, v.type, next],
      );
      await db.query(
        "UPDATE organizations SET business_order_revision=business_order_revision+1 WHERE id=$1",
        [m.organization_id],
      );
      await this.audit(db, actor, m.organization_id, "business.created", id);
      return { id };
    });
  }
  async reorderBusinesses(actor: Actor, input: unknown) {
    const v = businessOrderSchema.parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, true, db);
      const org = (
        await db.query<Row>(
          "SELECT business_order_revision FROM organizations WHERE id=$1 FOR UPDATE",
          [m.organization_id],
        )
      ).rows[0];
      if (org.business_order_revision !== v.revision)
        throw new ConflictException(
          "The business list changed. Review the latest order and try again.",
        );
      const businesses = (
        await db.query<Row>(
          "SELECT id FROM businesses WHERE organization_id=$1 AND status<>'archived'",
          [m.organization_id],
        )
      ).rows;
      const ids = new Set(businesses.map((b) => b.id));
      if (
        ids.size !== v.business_ids.length ||
        v.business_ids.some((id) => !ids.has(id))
      )
        throw new BadRequestException(
          "Include each organization business exactly once.",
        );
      await db.query(
        "UPDATE businesses b SET display_order=(ordering.position-1)::integer FROM unnest($1::uuid[]) WITH ORDINALITY AS ordering(id,position) WHERE b.id=ordering.id AND b.organization_id=$2",
        [v.business_ids, m.organization_id],
      );
      const revision = v.revision + 1;
      await db.query(
        "UPDATE organizations SET business_order_revision=$2 WHERE id=$1",
        [m.organization_id, revision],
      );
      await this.audit(
        db,
        actor,
        m.organization_id,
        "businesses.reordered",
        m.organization_id,
      );
      return { business_ids: v.business_ids, revision };
    });
  }
  async business(actor: Actor, id: string, db: Queryable = this.db) {
    const m = await this.member(actor, true, db);
    const b = (
      await db.query<Row>(
        "SELECT * FROM businesses WHERE id=$1 AND organization_id=$2 AND status<>'archived' FOR UPDATE",
        [id, m.organization_id],
      )
    ).rows[0];
    if (!b) throw new NotFoundException("Business not found.");
    return b;
  }
  async renameBusiness(actor: Actor, id: string, input: unknown) {
    const v = (input as { name?: unknown })?.name;
    if (typeof v !== "string" || v.trim().length < 2 || v.trim().length > 120)
      throw new BadRequestException(
        "Enter a business name between 2 and 120 characters.",
      );
    return this.db.transaction(async (db) => {
      const b = await this.business(actor, id, db);
      await db.query(
        "UPDATE businesses SET name=$1,version=version+1 WHERE id=$2",
        [v.trim(), id],
      );
      await this.audit(db, actor, b.organization_id, "business.renamed", id);
      return { id };
    });
  }
  async addResource(actor: Actor, id: string, input: unknown) {
    const v = resourceSchema.parse(input);
    return this.db.transaction(async (db) => {
      const b = await this.business(actor, id, db);
      if (
        ["turf_v1", "pool_v1", "court_v1", "hall_v1"].includes(
          b.configuration?.kind,
        )
      )
        throw new BadRequestException(
          "Use the dedicated business configuration screens to edit these resources.",
        );
      const resource = randomUUID();
      await db.query(
        "INSERT INTO resources(id,organization_id,business_id,name,capacity) VALUES($1,$2,$3,$4,$5)",
        [resource, b.organization_id, id, v.name, v.capacity],
      );
      await db.query(
        "UPDATE businesses SET status='draft',version=version+1 WHERE id=$1",
        [id],
      );
      await this.audit(
        db,
        actor,
        b.organization_id,
        "resource.created",
        resource,
      );
      return { id: resource };
    });
  }
  async deleteResource(actor: Actor, businessId: string, resourceId: string) {
    return this.db.transaction(async (db) => {
      const b = await this.business(actor, businessId, db);
      if (
        ["turf_v1", "pool_v1", "court_v1", "hall_v1"].includes(
          b.configuration?.kind,
        )
      )
        throw new BadRequestException(
          "Use the dedicated business configuration screens to edit these resources.",
        );
      const assigned = (
        await db.query<Row>(
          "SELECT resource_ids FROM staff_assignments WHERE business_id=$1",
          [businessId],
        )
      ).rows;
      if (assigned.some((a) => a.resource_ids.includes(resourceId)))
        throw new ConflictException(
          "Remove this resource from staff assignments first.",
        );
      const pending = (
        await db.query<Row>(
          "SELECT assignments FROM invitations WHERE organization_id=$1 AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at>now()",
          [b.organization_id],
        )
      ).rows;
      if (
        pending.some((i) =>
          i.assignments.some((a: Row) => a.resource_ids.includes(resourceId)),
        )
      )
        throw new ConflictException(
          "Cancel pending invitations assigning this resource first.",
        );
      if (
        !(
          await db.query(
            "DELETE FROM resources WHERE id=$1 AND business_id=$2 RETURNING id",
            [resourceId, businessId],
          )
        ).rows.length
      )
        throw new NotFoundException("Resource not found.");
      await db.query(
        "UPDATE businesses SET status='draft',version=version+1 WHERE id=$1",
        [businessId],
      );
      await this.audit(
        db,
        actor,
        b.organization_id,
        "resource.removed",
        resourceId,
      );
      return { id: resourceId };
    });
  }
  async configure(actor: Actor, id: string, input: unknown) {
    const v = configSchema.parse(input);
    return this.db.transaction(async (db) => {
      const b = await this.business(actor, id, db);
      if (
        ["turf_v1", "pool_v1", "court_v1", "hall_v1"].includes(
          b.configuration?.kind,
        )
      )
        throw new BadRequestException(
          "Use the dedicated business configuration screens to edit these resources.",
        );
      if (b.version !== v.version)
        throw new ConflictException(
          "Setup changed on another device. Reload and try again.",
        );
      if (b.type === "pool") {
        if (!v.plan_name?.trim() || !v.validity_days || !v.entitlement)
          throw new BadRequestException(
            "Pool plans require a name, validity and entitlement.",
          );
        if (v.entitlement !== "unlimited" && !v.visit_limit)
          throw new BadRequestException(
            "Enter the visit or attendance-day limit.",
          );
      } else if (
        v.entitlement ||
        v.validity_days ||
        v.plan_name ||
        v.visit_limit
      )
        throw new BadRequestException(
          "Subscription fields belong to swimming pools only.",
        );
      const { version, ...configuration } = v;
      await db.query(
        "UPDATE businesses SET configuration=$1,status='draft',version=version+1 WHERE id=$2",
        [JSON.stringify(configuration), id],
      );
      await this.audit(db, actor, b.organization_id, "business.configured", id);
      return { id };
    });
  }
  async archiveBusiness(actor: Actor, id: string, input: unknown) {
    z.uuid().parse(id);
    const v = z
      .object({ version: z.number().int().positive() })
      .strict()
      .parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, true, db, true);
      // Same ordering lock as additions/reorders, then the inventory lock used
      // by booking, admission and public-website commits. A non-key lock lets
      // concurrent inventory writers finish their organization FK checks before
      // we acquire their business lock, avoiding an organization/business cycle.
      await db.query(
        "SELECT id FROM organizations WHERE id=$1 FOR NO KEY UPDATE",
        [m.organization_id],
      );
      const b = (
        await db.query<Row>(
          "SELECT * FROM businesses WHERE id=$1 AND organization_id=$2 FOR UPDATE",
          [id, m.organization_id],
        )
      ).rows[0];
      if (!b) throw new NotFoundException("Business not found.");
      if (b.status === "archived") return { id };
      if (b.version !== v.version)
        throw new ConflictException(
          "Business changed. Refresh before removing it.",
        );
      const pending = (
        await db.query<Row>(
          `SELECT EXISTS(SELECT 1 FROM bookings WHERE organization_id=$1 AND business_id=$2 AND status<>'cancelled' AND ends_at>now()) AS bookings,
          EXISTS(SELECT 1 FROM admission_balances WHERE organization_id=$1 AND business_id=$2 AND status IN ('active','upcoming')) AS admissions`,
          [m.organization_id, id],
        )
      ).rows[0];
      if (pending.bookings || pending.admissions)
        throw new ConflictException(
          "This business has upcoming or ongoing bookings, or active or upcoming admissions. Resolve them before removing it.",
        );
      await db.query(
        "UPDATE businesses SET status='archived',archived_at=now(),archived_by=$2,version=version+1 WHERE id=$1",
        [id, actor.uid],
      );
      await db.query(
        "UPDATE organizations SET business_order_revision=business_order_revision+1 WHERE id=$1",
        [m.organization_id],
      );
      await this.audit(db, actor, m.organization_id, "business.archived", id);
      return { id };
    });
  }
  async setBookingEnabled(actor: Actor, id: string, input: unknown) {
    const v = z
      .object({ enabled: z.boolean(), version: z.number().int().positive() })
      .strict()
      .parse(input);
    if (v.enabled) return this.activate(actor, id, v.version);
    return this.db.transaction(async (db) => {
      const b = await this.business(actor, id, db);
      if (b.version !== v.version || b.status !== "ready")
        throw new ConflictException(
          "Business changed. Refresh before turning it off.",
        );
      await db.query(
        "UPDATE businesses SET status='paused',version=version+1 WHERE id=$1",
        [id],
      );
      await this.audit(db, actor, b.organization_id, "business.turned_off", id);
      return { id };
    });
  }
  async activate(actor: Actor, id: string, expectedVersion?: number) {
    return this.db.transaction(async (db) => {
      const b = await this.business(actor, id, db);
      if (
        expectedVersion !== undefined &&
        (b.version !== expectedVersion || b.status !== "paused")
      )
        throw new ConflictException(
          "Business changed. Refresh before turning it on.",
        );
      if (!b.configuration)
        throw new BadRequestException("Save operating rules and prices first.");
      if (
        !(await db.query("SELECT id FROM resources WHERE business_id=$1", [id]))
          .rows.length
      )
        throw new BadRequestException("Add at least one resource first.");
      if (b.configuration.kind === "turf_v1") {
        try {
          const config = assertTurfComplete(b.configuration);
          const resources = (
            await db.query<Row>(
              "SELECT id FROM resources WHERE business_id=$1",
              [id],
            )
          ).rows;
          if (
            resources.length !== config.layouts.length ||
            config.layouts.some((l) => !resources.some((r) => r.id === l.id))
          )
            throw new Error("Save the turf spaces again before activation.");
        } catch (error) {
          throw new BadRequestException(
            error instanceof Error
              ? error.message
              : "Complete turf setup first.",
          );
        }
      } else if (b.configuration.kind === "hall_v1") {
        try {
          const config = assertHallComplete(b.configuration);
          const resources = (
            await db.query<Row>(
              "SELECT id,capacity FROM resources WHERE business_id=$1",
              [id],
            )
          ).rows;
          if (
            resources.length !== config.halls.length ||
            config.halls.some(
              (p) =>
                !resources.some(
                  (r) => r.id === p.id && r.capacity === p.capacity,
                ),
            )
          )
            throw Error("Save hall resources again before activation.");
        } catch (error) {
          throw new BadRequestException(
            error instanceof Error
              ? error.message
              : "Complete hall configuration first.",
          );
        }
      } else if (b.configuration.kind === "court_v1") {
        try {
          const location = (
            await db.query<Row>("SELECT timezone FROM locations WHERE id=$1", [
              b.location_id,
            ])
          ).rows[0];
          const config = assertCourtComplete(
            b.configuration,
            new Intl.DateTimeFormat("en-CA", {
              timeZone: location.timezone,
              year: "numeric",
              month: "2-digit",
              day: "2-digit",
            }).format(new Date()),
          );
          const resources = (
            await db.query<Row>(
              "SELECT id,capacity FROM resources WHERE business_id=$1",
              [id],
            )
          ).rows;
          if (
            resources.length !== config.courts.length ||
            config.courts.some(
              (p) => !resources.some((r) => r.id === p.id && r.capacity === 1),
            )
          )
            throw Error("Save court resources again before activation.");
          await assertPlanCoaches(db, b.organization_id, id, config);
        } catch (error) {
          throw new BadRequestException(
            error instanceof Error
              ? error.message
              : "Complete court configuration first.",
          );
        }
      } else if (b.configuration.kind === "pool_v1") {
        try {
          const location = (
            await db.query<Row>("SELECT timezone FROM locations WHERE id=$1", [
              b.location_id,
            ])
          ).rows[0];
          const today = new Intl.DateTimeFormat("en-CA", {
            timeZone: location.timezone,
            year: "numeric",
            month: "2-digit",
            day: "2-digit",
          }).format(new Date());
          const config = assertPoolComplete(b.configuration, today);
          await assertPlanCoaches(db, b.organization_id, id, config);
          const resources = (
            await db.query<Row>(
              "SELECT id,capacity FROM resources WHERE business_id=$1",
              [id],
            )
          ).rows;
          if (
            resources.length !== config.pools.length ||
            config.pools.some(
              (p) =>
                !resources.some(
                  (r) => r.id === p.id && r.capacity === p.capacity,
                ),
            )
          )
            throw new Error("Save pool resources again before activation.");
        } catch (error) {
          throw new BadRequestException(
            error instanceof Error
              ? error.message
              : "Complete pool configuration first.",
          );
        }
      } else {
        configSchema.parse({ ...b.configuration, version: b.version });
      }
      await db.query(
        "UPDATE businesses SET status='ready',version=version+1 WHERE id=$1",
        [id],
      );
      await this.audit(db, actor, b.organization_id, "business.activated", id);
      return { id };
    });
  }
  async validateAssignments(
    db: Queryable,
    org: string,
    assignments: Array<{ business_id: string; resource_ids: string[] }>,
  ) {
    if (
      new Set(assignments.map((a) => a.business_id)).size !== assignments.length
    )
      throw new BadRequestException("Duplicate business assignment.");
    for (const a of assignments) {
      if (
        !(
          await db.query(
            "SELECT id FROM businesses WHERE id=$1 AND organization_id=$2 FOR SHARE",
            [a.business_id, org],
          )
        ).rows.length
      )
        throw new BadRequestException(
          "Business assignment is outside this organization.",
        );
      const ids = (
        await db.query<Row>("SELECT id FROM resources WHERE business_id=$1", [
          a.business_id,
        ])
      ).rows.map((r) => r.id);
      if (
        new Set(a.resource_ids).size !== a.resource_ids.length ||
        a.resource_ids.some((id) => !ids.includes(id))
      )
        throw new BadRequestException("Invalid resource assignment.");
    }
  }
  async invite(actor: Actor, input: unknown) {
    const v = invitationSchema.parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, true, db);
      await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [
        `team-email:${v.email.toLowerCase()}`,
      ]);
      await this.validateAssignments(db, m.organization_id, v.assignments);
      if (
        (
          await db.query(
            "SELECT id FROM memberships WHERE email=$1 AND active=true",
            [v.email],
          )
        ).rows.length
      )
        throw new ConflictException(
          "This staff email already has active organization access.",
        );
      await db.query(
        "UPDATE invitations SET revoked_at=now() WHERE organization_id=$1 AND email=$2 AND accepted_at IS NULL AND revoked_at IS NULL",
        [m.organization_id, v.email],
      );
      const token = randomBytes(32).toString("hex"),
        id = randomUUID();
      await db.query(
        "INSERT INTO invitations(id,organization_id,email,display_name,role,permissions,assignments,token_hash,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,now()+interval '7 days')",
        [
          id,
          m.organization_id,
          v.email,
          v.display_name,
          v.role,
          JSON.stringify(v.permissions),
          JSON.stringify(v.assignments),
          hash(token),
        ],
      );
      await this.audit(db, actor, m.organization_id, "staff.invited", id);
      return {
        id,
        invitation_url: `${this.publicAppUrl || process.env.PUBLIC_APP_URL || "http://localhost:8080"}/invite?token=${token}`,
        delivery: "share_link",
      };
    });
  }
  async accept(actor: Actor, token: string) {
    if (!/^[a-f0-9]{64}$/.test(token))
      throw new BadRequestException("Invalid invitation.");
    return this.db.transaction(async (db) => {
      await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [
        `team-email:${actor.email.toLowerCase()}`,
      ]);
      const i = (
        await db.query<Row>(
          "SELECT * FROM invitations WHERE token_hash=$1 AND revoked_at IS NULL AND accepted_at IS NULL AND expires_at>now() FOR UPDATE",
          [hash(token)],
        )
      ).rows[0];
      if (!i) throw new NotFoundException("Invitation expired or unavailable.");
      if (i.email !== actor.email)
        throw new ForbiddenException("Sign in with the invited email address.");
      const previous = (
        await db.query<Row>(
          "SELECT * FROM memberships WHERE user_id=$1 FOR UPDATE",
          [actor.uid],
        )
      ).rows[0];
      if (
        previous?.active ||
        (previous && previous.organization_id !== i.organization_id)
      )
        throw new ConflictException(
          "This account already belongs to an organization.",
        );
      await this.validateAssignments(db, i.organization_id, i.assignments);
      const membershipId = previous?.id || randomUUID();
      if (previous) {
        await db.query("DELETE FROM staff_assignments WHERE membership_id=$1", [
          membershipId,
        ]);
        await db.query(
          "UPDATE memberships SET active=true,email=$1,display_name=$2,role=$3,permissions=$4 WHERE id=$5",
          [
            i.email,
            i.display_name,
            i.role,
            JSON.stringify(i.permissions),
            membershipId,
          ],
        );
      } else
        await db.query(
          "INSERT INTO memberships(id,organization_id,user_id,email,display_name,role,permissions) VALUES($1,$2,$3,$4,$5,$6,$7)",
          [
            membershipId,
            i.organization_id,
            actor.uid,
            i.email,
            i.display_name,
            i.role,
            JSON.stringify(i.permissions),
          ],
        );
      for (const a of i.assignments)
        await db.query(
          "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,$4)",
          [
            membershipId,
            i.organization_id,
            a.business_id,
            JSON.stringify(a.resource_ids),
          ],
        );
      await db.query("UPDATE invitations SET accepted_at=now() WHERE id=$1", [
        i.id,
      ]);
      await this.audit(
        db,
        actor,
        i.organization_id,
        "staff.accepted",
        membershipId,
      );
      return { id: membershipId };
    });
  }
  async team(actor: Actor) {
    const m = await this.member(actor, true);
    const members = (
      await this.db.query<Row>(
        "SELECT * FROM memberships WHERE organization_id=$1 AND user_id NOT LIKE 'sarvam:%' ORDER BY display_name",
        [m.organization_id],
      )
    ).rows;
    for (const member of members)
      member.assignments = (
        await this.db.query(
          "SELECT business_id,resource_ids FROM staff_assignments WHERE membership_id=$1",
          [member.id],
        )
      ).rows;
    const invites = (
      await this.db.query<Row>(
        "SELECT id,email,display_name,role,permissions,assignments,expires_at,accepted_at,revoked_at,join_mode,email_status,email_attempted_at,email_sent_at FROM invitations WHERE organization_id=$1 ORDER BY created_at DESC",
        [m.organization_id],
      )
    ).rows;
    return { members, invitations: invites };
  }
  async revoke(actor: Actor, id: string, invitation: boolean) {
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, true, db);
      if (!invitation) {
        if (id === m.id)
          throw new ConflictException(
            "You cannot remove your own owner access. Ask another owner to do it.",
          );
        // Serialize owner removals so two owners cannot remove each other.
        await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [
          `team-owners:${m.organization_id}`,
        ]);
      }
      const result = await db.query(
        invitation
          ? "UPDATE invitations SET revoked_at=now() WHERE id=$1 AND organization_id=$2 AND accepted_at IS NULL RETURNING id"
          : "UPDATE memberships SET active=false WHERE id=$1 AND organization_id=$2 AND user_id NOT LIKE 'sarvam:%' RETURNING id",
        [id, m.organization_id],
      );
      if (!result.rows.length)
        throw new NotFoundException("Staff access or invitation not found.");
      if (
        !invitation &&
        !(
          await db.query(
            "SELECT 1 FROM memberships WHERE organization_id=$1 AND role='owner' AND active=true AND user_id NOT LIKE 'sarvam:%'",
            [m.organization_id],
          )
        ).rows.length
      )
        throw new ConflictException(
          "An organization needs at least one owner.",
        );
      if (!invitation) {
        // Revoke pending grants too, so the next sign-in cannot restore access.
        await db.query(
          "UPDATE invitations SET revoked_at=now() WHERE organization_id=$1 AND lower(email)=(SELECT lower(email) FROM memberships WHERE id=$2) AND accepted_at IS NULL AND revoked_at IS NULL",
          [m.organization_id, id],
        );
        await db.query(
          "DELETE FROM staff_assignments WHERE membership_id=$1 AND organization_id=$2",
          [id, m.organization_id],
        );
      }
      await this.audit(db, actor, m.organization_id, "staff.revoked", id);
      return { id, released: await releaseCoachPlans(db, m.organization_id) };
    });
  }
  /** Delete only inactive team identities/cancelled invitations, never Auth or history. */
  async deleteTeamRecord(actor: Actor, id: string, invitation: boolean) {
    z.uuid().parse(id);
    try {
      return await this.db.transaction(async (db) => {
        const owner = await this.member(actor, true, db);
        const table = invitation ? "invitations" : "memberships";
        const identity = (
          await db.query<Row>(
            `SELECT email FROM ${table} WHERE id=$1 AND organization_id=$2`,
            [id, owner.organization_id],
          )
        ).rows[0];
        if (!identity)
          throw new NotFoundException(
            "Team record not found. Refresh your team.",
          );
        // Match email-grant/claim lock order before locking a membership row.
        await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [
          `team-email:${identity.email.toLowerCase()}`,
        ]);
        const record = (
          await db.query<Row>(
            `SELECT * FROM ${table} WHERE id=$1 AND organization_id=$2 FOR UPDATE`,
            [id, owner.organization_id],
          )
        ).rows[0];
        if (!record)
          throw new NotFoundException(
            "Team record not found. Refresh your team.",
          );
        if (invitation) {
          if (!record.revoked_at || record.accepted_at)
            throw new ConflictException(
              "Only cancelled, unaccepted invitations can be deleted permanently.",
            );
          await db.query(
            "DELETE FROM invitations WHERE id=$1 AND organization_id=$2",
            [id, owner.organization_id],
          );
        } else {
          if (
            record.active ||
            !["staff", "manager", "owner"].includes(record.role) ||
            record.user_id.startsWith("sarvam:") ||
            record.id === owner.id
          )
            throw new ConflictException(
              "Only removed team members can be deleted permanently.",
            );
          const pending = await db.query(
            "SELECT id FROM invitations WHERE organization_id=$1 AND lower(email)=$2 AND revoked_at IS NULL AND accepted_at IS NULL",
            [owner.organization_id, record.email.toLowerCase()],
          );
          if (pending.rows.length)
            throw new ConflictException(
              "Cancel this person's pending access before deleting their team record.",
            );
          await releaseCoachPlans(db, owner.organization_id);
          await db.query(
            "DELETE FROM staff_assignments WHERE membership_id=$1 AND organization_id=$2",
            [id, owner.organization_id],
          );
          await db.query(
            "DELETE FROM invitations WHERE organization_id=$1 AND lower(email)=$2",
            [owner.organization_id, record.email.toLowerCase()],
          );
          await db.query(
            "DELETE FROM memberships WHERE id=$1 AND organization_id=$2 AND active=false",
            [id, owner.organization_id],
          );
        }
        await this.audit(
          db,
          actor,
          owner.organization_id,
          invitation
            ? "invitation.permanently_deleted"
            : "staff.permanently_deleted",
          id,
        );
        return { id, deleted: true };
      });
    } catch (error) {
      if ((error as { code?: string })?.code === "23503")
        throw new ConflictException(
          "Other protected records still reference this member. No records were deleted. Contact support.",
        );
      throw error;
    }
  }

  async updateMember(actor: Actor, id: string, input: unknown) {
    const v = invitationSchema.parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, true, db);
      const member = (
        await db.query<Row>(
          "SELECT * FROM memberships WHERE id=$1 AND organization_id=$2 AND active=true AND role!='owner' AND user_id NOT LIKE 'sarvam:%' FOR UPDATE",
          [id, m.organization_id],
        )
      ).rows[0];
      if (!member) throw new NotFoundException("Staff member not found.");
      if (v.email !== member.email)
        throw new BadRequestException("Staff email cannot be changed here.");
      await this.validateAssignments(db, m.organization_id, v.assignments);
      await db.query(
        "UPDATE memberships SET display_name=$1,role=$2,permissions=$3 WHERE id=$4",
        [v.display_name, v.role, JSON.stringify(v.permissions), id],
      );
      await db.query("DELETE FROM staff_assignments WHERE membership_id=$1", [
        id,
      ]);
      for (const a of v.assignments)
        await db.query(
          "INSERT INTO staff_assignments(membership_id,organization_id,business_id,resource_ids) VALUES($1,$2,$3,$4)",
          [
            id,
            m.organization_id,
            a.business_id,
            JSON.stringify(a.resource_ids),
          ],
        );
      await this.audit(db, actor, m.organization_id, "staff.updated", id);
      return { id, released: await releaseCoachPlans(db, m.organization_id) };
    });
  }
  /** The owner opts in or out of coaching; their plans are released when out. */
  async ownerCoach(actor: Actor, input: unknown) {
    const v = z.object({ coach: z.boolean() }).strict().parse(input);
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, true, db);
      const permissions = (m.permissions as string[]).filter(
        (p) => p !== "coach",
      );
      if (v.coach) permissions.push("coach");
      await db.query("UPDATE memberships SET permissions=$1 WHERE id=$2", [
        JSON.stringify(permissions),
        m.id,
      ]);
      await this.audit(db, actor, m.organization_id, "staff.updated", m.id);
      return {
        id: m.id,
        released: await releaseCoachPlans(db, m.organization_id),
      };
    });
  }
  /**
   * Assigns coaches to coaching plans without touching the rest of the
   * configuration, so a ready business stays ready.
   */
  async planCoaches(actor: Actor, id: string, input: unknown) {
    const v = z
      .object({
        version: z.number().int().positive(),
        coaches: z.record(z.string().min(1).max(100), z.uuid().nullable()),
      })
      .strict()
      .parse(input);
    return this.db.transaction(async (db) => {
      const b = await this.business(actor, id, db);
      if (!coachingConfiguration(b.configuration))
        throw new BadRequestException(
          "Save the pool or court configuration before assigning coaches.",
        );
      if (b.version !== v.version)
        throw new ConflictException(
          "Settings changed. Refresh coaches and try again.",
        );
      const plans: Row[] = b.configuration.plans ?? [];
      for (const planId of Object.keys(v.coaches))
        if (!plans.some((p) => p.id === planId && p.kind === "coaching"))
          throw new BadRequestException(
            "Choose coaching plans in this business.",
          );
      const configuration = {
        ...b.configuration,
        plans: plans.map((p) =>
          p.id in v.coaches ? { ...p, coach_id: v.coaches[p.id] } : p,
        ),
      };
      await assertPlanCoaches(db, b.organization_id, id, configuration);
      await db.query(
        "UPDATE businesses SET configuration=$1,version=version+1 WHERE id=$2",
        [JSON.stringify(configuration), id],
      );
      await this.audit(db, actor, b.organization_id, "coaches.assigned", id);
      return { id, version: b.version + 1 };
    });
  }
  async logo(actor: Actor) {
    const m = await this.member(actor);
    const row = (
      await this.db.query<Row>(
        "SELECT content_type,data FROM logo_assets WHERE organization_id=$1",
        [m.organization_id],
      )
    ).rows[0];
    if (!row) throw new NotFoundException("No logo uploaded.");
    return row;
  }
  async uploadLogo(actor: Actor, input: unknown) {
    const body = logoSchema.parse(input);
    if (!body.base64 || body.base64.length > 2800000)
      throw new BadRequestException("Choose an image up to 2 MB.");
    const bytes = Buffer.from(body.base64, "base64");
    const mime = body.content_type;
    const signature =
      mime === "image/png"
        ? bytes
            .subarray(0, 8)
            .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
        : mime === "image/jpeg"
          ? bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255
          : mime === "image/webp"
            ? bytes.subarray(0, 4).toString() === "RIFF" &&
              bytes.subarray(8, 12).toString() === "WEBP"
            : false;
    if (!signature || bytes.length > 2097152 || bytes.length < 12)
      throw new BadRequestException(
        "Choose a valid PNG, JPEG or WebP image up to 2 MB.",
      );
    return this.db.transaction(async (db) => {
      const m = await this.member(actor, true, db);
      const id = randomUUID();
      await db.query(
        "INSERT INTO logo_assets(id,organization_id,content_type,data) VALUES($1,$2,$3,$4) ON CONFLICT(organization_id) DO UPDATE SET id=EXCLUDED.id,content_type=EXCLUDED.content_type,data=EXCLUDED.data",
        [id, m.organization_id, mime, bytes],
      );
      await db.query(
        "UPDATE organizations SET logo_storage_key=$1 WHERE id=$2",
        [id, m.organization_id],
      );
      await this.audit(
        db,
        actor,
        m.organization_id,
        "organization.logo_updated",
        id,
      );
      return { id };
    });
  }
}
