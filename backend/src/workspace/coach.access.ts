import { BadRequestException } from "@nestjs/common";
import { Queryable } from "../common/database";
type Row = Record<string, any>;

// Coaches are team members with the "coach" flag in their permissions. Owners
// opt in the same way. They teach in the spaces of their staff assignment;
// owners and unrestricted assignments cover the whole business.
export const isCoach = (m: Row) =>
  m.active !== false && (m.permissions ?? []).includes("coach");
export const planSpaces = (plan: Row): string[] =>
  plan.pool_ids ?? plan.court_ids ?? [];
export const coachingConfiguration = (config: Row | undefined) =>
  config?.kind === "pool_v1" || config?.kind === "court_v1";

export type Coaches = { members: Row[]; assignments: Row[] };
export async function loadCoaches(
  db: Queryable,
  organizationId: string,
): Promise<Coaches> {
  const [members, assignments] = await Promise.all([
    db.query<Row>(
      "SELECT id,role,permissions,active,display_name FROM memberships WHERE organization_id=$1 AND user_id NOT LIKE 'sarvam:%'",
      [organizationId],
    ),
    db.query<Row>(
      "SELECT membership_id,business_id,resource_ids FROM staff_assignments WHERE organization_id=$1",
      [organizationId],
    ),
  ]);
  return { members: members.rows, assignments: assignments.rows };
}

/** Why `coachId` cannot coach a plan on `spaceIds`, or null when they can. */
export function coachProblem(
  coaches: Coaches,
  businessId: string,
  coachId: string,
  spaceIds: string[],
): string | null {
  const m = coaches.members.find((x) => x.id === coachId);
  if (!m || !m.active) return "Choose an active coach from your team.";
  if (!isCoach(m)) return `${m.display_name} is not marked as a coach.`;
  if (m.role === "owner") return null;
  const a = coaches.assignments.find(
    (x) => x.membership_id === m.id && x.business_id === businessId,
  );
  if (!a) return `${m.display_name} is not assigned to this business.`;
  if (
    a.resource_ids.length &&
    spaceIds.some((id) => !a.resource_ids.includes(id))
  )
    return `${m.display_name} must be assigned to every space of this plan.`;
  return null;
}

export async function assertPlanCoaches(
  db: Queryable,
  organizationId: string,
  businessId: string,
  configuration: Row,
) {
  const plans = (configuration.plans ?? []).filter(
    (p: Row) => p.kind === "coaching" && p.coach_id,
  );
  if (!plans.length) return;
  const coaches = await loadCoaches(db, organizationId);
  for (const p of plans) {
    const problem = coachProblem(
      coaches,
      businessId,
      p.coach_id,
      planSpaces(p),
    );
    if (problem) throw new BadRequestException(`${p.name}: ${problem}`);
  }
}

/**
 * Unassigns plans whose coach can no longer teach them, after a team member's
 * access changed. Only the plan coach changes, so business status is kept.
 * Returns the number of plans released.
 */
export async function releaseCoachPlans(db: Queryable, organizationId: string) {
  const coaches = await loadCoaches(db, organizationId);
  const businesses = (
    await db.query<Row>(
      "SELECT id,configuration FROM businesses WHERE organization_id=$1 ORDER BY id FOR UPDATE",
      [organizationId],
    )
  ).rows;
  let released = 0;
  for (const b of businesses) {
    if (!coachingConfiguration(b.configuration)) continue;
    let changed = false;
    const plans = (b.configuration.plans ?? []).map((p: Row) => {
      if (
        !p.coach_id ||
        !coachProblem(coaches, b.id, p.coach_id, planSpaces(p))
      )
        return p;
      changed = true;
      released++;
      return { ...p, coach_id: null };
    });
    if (changed)
      await db.query(
        "UPDATE businesses SET configuration=$1,version=version+1 WHERE id=$2",
        [JSON.stringify({ ...b.configuration, plans }), b.id],
      );
  }
  return released;
}
