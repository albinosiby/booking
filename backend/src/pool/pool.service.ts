import { protectBookingInventory } from "../bookings/configuration.guard";
import { assertPlanCoaches } from "../workspace/coach.access";
import {
  Injectable,
  BadRequestException,
  ConflictException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Database } from "../common/database";
import { Actor } from "../common/auth.guard";
import { WorkspaceService } from "../workspace/workspace.service";
import { poolSaveSchema, assertPoolComplete } from "./pool.validation";
type Row = Record<string, any>;
@Injectable()
export class PoolService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  async configure(actor: Actor, id: string, input: unknown) {
    const v = poolSaveSchema.parse(input);
    return this.db.transaction(async (db) => {
      const b = await this.workspace.business(actor, id, db);
      await protectBookingInventory(db, b, v.configuration);
      if (b.type !== "pool")
        throw new BadRequestException(
          "This configuration belongs to a pool business.",
        );
      if (b.version !== v.version)
        throw new ConflictException(
          "Setup changed on another device. Reload before saving.",
        );
      if (b.status === "ready") {
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
        try {
          assertPoolComplete(v.configuration, today);
        } catch (error) {
          throw new BadRequestException(
            error instanceof Error
              ? error.message
              : "Complete all enabled pool settings.",
          );
        }
      }
      await assertPlanCoaches(db, b.organization_id, id, v.configuration);
      const pools = v.configuration.pools;
      const current = (
        await db.query<Row>("SELECT id FROM resources WHERE business_id=$1", [
          id,
        ])
      ).rows;
      const next = new Set(pools.map((l) => l.id));
      const removed = current.filter((r) => !next.has(r.id)).map((r) => r.id);
      const assigned = (
        await db.query<Row>(
          "SELECT resource_ids FROM staff_assignments WHERE business_id=$1",
          [id],
        )
      ).rows;
      const invitations = (
        await db.query<Row>(
          "SELECT assignments FROM invitations WHERE organization_id=$1 AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at>now()",
          [b.organization_id],
        )
      ).rows;
      if (
        assigned.some((a) =>
          a.resource_ids.some((resource: string) => removed.includes(resource)),
        ) ||
        invitations.some((i) =>
          i.assignments.some(
            (a: Row) =>
              a.business_id === id &&
              a.resource_ids.some((resource: string) =>
                removed.includes(resource),
              ),
          ),
        )
      )
        throw new ConflictException(
          "Remove staff assignments or pending invitations for pools being removed first.",
        );
      const foreign = (
        await db.query<Row>(
          "SELECT id FROM resources WHERE id=ANY($1::uuid[]) AND business_id<>$2",
          [pools.map((l) => l.id), id],
        )
      ).rows;
      if (foreign.length)
        throw new BadRequestException(
          "Pool identifiers cannot belong to another business.",
        );
      if (removed.length)
        await db.query(
          "DELETE FROM resources WHERE business_id=$1 AND id=ANY($2::uuid[])",
          [id, removed],
        );
      // Temporary unique names permit swapping two existing space names atomically.
      for (const resource of current.filter((r) => next.has(r.id)))
        await db.query(
          "UPDATE resources SET name=$1 WHERE id=$2 AND business_id=$3",
          [`__pool_${randomUUID()}`, resource.id, id],
        );
      for (const pool of pools) {
        const written = (
          await db.query(
            "INSERT INTO resources(id,organization_id,business_id,name,capacity) VALUES($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET name=EXCLUDED.name,capacity=EXCLUDED.capacity WHERE resources.business_id=EXCLUDED.business_id RETURNING id",
            [pool.id, b.organization_id, id, pool.name, pool.capacity],
          )
        ).rows;
        if (written.length !== 1)
          throw new ConflictException(
            "A pool identifier changed. Reload setup.",
          );
      }
      await db.query(
        "UPDATE businesses SET configuration=$1,status='draft',version=version+1 WHERE id=$2",
        [JSON.stringify(v.configuration), id],
      );
      await this.workspace.audit(
        db,
        actor,
        b.organization_id,
        "pool.configured",
        id,
      );
      return { id, version: b.version + 1 };
    });
  }
}
