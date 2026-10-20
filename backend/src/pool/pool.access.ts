import { BadRequestException } from "@nestjs/common";
import { Queryable } from "../common/database";
import { PoolConfiguration } from "./pool.validation";
export async function assertPoolCoaches(
  db: Queryable,
  organizationId: string,
  businessId: string,
  configuration: PoolConfiguration,
) {
  for (const plan of configuration.plans.filter(
    (p) => p.kind === "coaching" && p.coach_id !== null,
  )) {
    // Configuration contacts identify instructors, not authenticated members.
    // They never grant staff permissions or create a login.
    const contact = configuration.coaches?.find((c) => c.id === plan.coach_id);
    if (contact) {
      if (
        contact.pool_ids &&
        plan.pool_ids.some((id) => !contact.pool_ids!.includes(id))
      )
        throw new BadRequestException(
          "Assign this coach to every eligible pool first.",
        );
      continue;
    }
    const coach = (
      await db.query<Record<string, any>>(
        "SELECT * FROM memberships WHERE id=$1 AND organization_id=$2",
        [plan.coach_id, organizationId],
      )
    ).rows[0];
    if (!coach || (plan.enabled && !coach.active))
      throw new BadRequestException(
        "Choose an active coach in this organization.",
      );
    if (plan.enabled && coach.role !== "owner") {
      const assignment = (
        await db.query<Record<string, any>>(
          "SELECT resource_ids FROM staff_assignments WHERE membership_id=$1 AND business_id=$2",
          [coach.id, businessId],
        )
      ).rows[0];
      if (
        !assignment ||
        (assignment.resource_ids.length &&
          plan.pool_ids.some((id) => !assignment.resource_ids.includes(id)))
      )
        throw new BadRequestException(
          "The coach must have access to every eligible pool.",
        );
    }
  }
}
