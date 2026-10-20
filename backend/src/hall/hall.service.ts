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
import { hallSaveSchema, assertHallComplete } from "./hall.validation";
type Row = Record<string, any>;
@Injectable()
export class HallService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  async configure(actor: Actor, id: string, input: unknown) {
    const v = hallSaveSchema.parse(input);
    return this.db.transaction(async (db) => {
      const b = await this.workspace.business(actor, id, db);
      await protectBookingInventory(db, b, v.configuration);
      if (b.type !== "hall")
        throw new BadRequestException(
          "This configuration belongs to a hall business.",
        );
      if (b.version !== v.version)
        throw new ConflictException(
          "Setup changed on another device. Reload before saving.",
        );
      if (b.status === "ready") {
        try {
          assertHallComplete(v.configuration);
        } catch (error) {
          throw new BadRequestException(
            error instanceof Error
              ? error.message
              : "Complete all enabled hall settings.",
          );
        }
      }
      const halls = v.configuration.halls;
      const current = (
        await db.query<Row>("SELECT id FROM resources WHERE business_id=$1", [
          id,
        ])
      ).rows;
      const next = new Set(halls.map((l) => l.id));
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
          "Remove staff assignments or pending invitations for halls being removed first.",
        );
      const foreign = (
        await db.query<Row>(
          "SELECT id FROM resources WHERE id=ANY($1::uuid[]) AND business_id<>$2",
          [halls.map((l) => l.id), id],
        )
      ).rows;
      if (foreign.length)
        throw new BadRequestException(
          "Hall identifiers cannot belong to another business.",
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
          [`__hall_${randomUUID()}`, resource.id, id],
        );
      for (const hall of halls) {
        const written = (
          await db.query(
            "INSERT INTO resources(id,organization_id,business_id,name,capacity) VALUES($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET name=EXCLUDED.name,capacity=EXCLUDED.capacity WHERE resources.business_id=EXCLUDED.business_id RETURNING id",
            [hall.id, b.organization_id, id, hall.name, hall.capacity],
          )
        ).rows;
        if (written.length !== 1)
          throw new ConflictException(
            "A hall identifier changed. Reload setup.",
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
        "hall.configured",
        id,
      );
      return { id, version: b.version + 1 };
    });
  }
}
