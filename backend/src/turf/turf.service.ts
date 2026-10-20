import { protectBookingInventory } from "../bookings/configuration.guard";
import {
  Injectable,
  BadRequestException,
  ConflictException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Database } from "../common/database";
import { Actor } from "../common/auth.guard";
import { WorkspaceService } from "../workspace/workspace.service";
import { turfSaveSchema, assertTurfComplete } from "./turf.validation";
type Row = Record<string, any>;
@Injectable()
export class TurfService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  async configure(actor: Actor, id: string, input: unknown) {
    const v = turfSaveSchema.parse(input);
    return this.db.transaction(async (db) => {
      const b = await this.workspace.business(actor, id, db);
      await protectBookingInventory(db, b, v.configuration);
      if (b.type !== "turf")
        throw new BadRequestException(
          "This configuration belongs to a turf business.",
        );
      if (b.version !== v.version)
        throw new ConflictException(
          "Setup changed on another device. Reload before saving.",
        );
      if (b.status === "ready") {
        try {
          assertTurfComplete(v.configuration);
        } catch (error) {
          throw new BadRequestException(
            error instanceof Error
              ? error.message
              : "Complete all enabled turf settings.",
          );
        }
      }
      if (
        b.configuration?.kind === "turf_v1" &&
        b.configuration.offerings.some((offer: Row) =>
          Array.isArray(offer.pricing_rules),
        ) &&
        v.configuration.offerings.some(
          (offer) => offer.pricing_rules === undefined,
        )
      )
        throw new BadRequestException(
          "Use the latest app to edit weekday/time pricing.",
        );
      if (
        b.configuration?.cricket_uses_football &&
        v.configuration.cricket_uses_football === undefined
      )
        throw new BadRequestException(
          "Use the latest app to edit linked Cricket pricing.",
        );
      const layouts = v.configuration.layouts;
      const current = (
        await db.query<Row>("SELECT id FROM resources WHERE business_id=$1", [
          id,
        ])
      ).rows;
      const next = new Set(layouts.map((l) => l.id));
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
          "Remove staff assignments or pending invitations for spaces being replaced first.",
        );
      const foreign = (
        await db.query<Row>(
          "SELECT id FROM resources WHERE id=ANY($1::uuid[]) AND business_id<>$2",
          [layouts.map((l) => l.id), id],
        )
      ).rows;
      if (foreign.length)
        throw new BadRequestException(
          "Space identifiers cannot belong to another business.",
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
          [`__turf_${randomUUID()}`, resource.id, id],
        );
      for (const layout of layouts) {
        const written = (
          await db.query(
            "INSERT INTO resources(id,organization_id,business_id,name,capacity) VALUES($1,$2,$3,$4,1) ON CONFLICT(id) DO UPDATE SET name=EXCLUDED.name,capacity=1 WHERE resources.business_id=EXCLUDED.business_id RETURNING id",
            [layout.id, b.organization_id, id, layout.name],
          )
        ).rows;
        if (written.length !== 1)
          throw new ConflictException(
            "A space identifier changed. Reload setup.",
          );
      }
      await db.query(
        "UPDATE businesses SET configuration=$1,version=version+1 WHERE id=$2",
        [JSON.stringify(v.configuration), id],
      );
      await this.workspace.audit(
        db,
        actor,
        b.organization_id,
        "turf.configured",
        id,
      );
      return { id, version: b.version + 1 };
    });
  }
}
