import { recordBookingHistory } from "../bookings/booking-history";
import {
  Injectable,
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
  HttpException,
} from "@nestjs/common";
import { randomUUID, randomBytes, createHash } from "node:crypto";
import { z } from "zod";
import { Database, Queryable } from "../common/database";
import { Actor } from "../common/auth.guard";
import { WorkspaceService } from "../workspace/workspace.service";
import {
  bookingOptions,
  buildQuote,
  checkInventory,
  localStamp,
  addDate,
} from "../bookings/booking.inventory";
import { bookingAvailability } from "../bookings/booking.availability";
import { inventoryAllocations } from "../slot-blocks/inventory-blocks";
import { BookingSelection } from "../bookings/booking.validation";
import {
  ensureWebsiteDraft,
  websiteSlug,
  websiteSubdomain,
  websiteSettingsSchema,
  publicAvailabilitySchema,
  publicQuoteSchema,
  publicCreateSchema,
} from "./website.validation";
import { websiteImage, websiteImageSchema } from "./website.images";
import { paymentSettings, paymentPolicy } from "./website.payments";
type Row = Record<string, any>;
type SpaceRules = {
  visible: boolean;
  notice_minutes: number;
  advance_days: number;
  rules: string;
  payment_required: boolean;
  payment_percentages: number[];
};
const hash = (v: string) => createHash("sha256").update(v).digest("hex");

/** A public projection, never raw business configuration, memberships or finance. */
export function websiteResources(b: Row) {
  const c = b.configuration;
  return bookingOptions(b)
    .map((r: Row) => {
      const layout = c.layouts?.find((l: Row) => l.id === r.id);
      const definition = (c.courts ?? c.pools ?? c.halls ?? []).find(
        (p: Row) => p.id === r.id,
      );
      return {
        id: r.id,
        name: r.name,
        capacity: r.capacity,
        ground_id: layout?.ground_id ?? null,
        section_ids: layout?.section_ids ?? [],
        options: r.options
          .filter((o: Row) =>
            ["hourly", "session", "full_day"].includes(o.kind),
          )
          .map((o: Row) => {
            const offering = c.offerings?.find((p: Row) => p.id === o.id);
            const minimum = o.minimum_duration ?? o.durations[0];
            const hallPackage =
              b.type === "hall" && o.kind !== "hourly"
                ? [...(definition?.sessions ?? []), definition?.full_day].find(
                    (p) => p?.id === o.id,
                  )
                : undefined;
            const tariffs = hallPackage
              ? hallPackage.prices.map((p: Row) => ({
                  ...hallPackage.hours,
                  ...p,
                  rates: [
                    { duration_minutes: minimum, price_minor: p.price_minor },
                  ],
                }))
              : offering
                ? offering.pricing_rules?.length
                  ? offering.pricing_rules.map((p: Row) => ({
                      days: p.days,
                      opens_at: p.starts_at,
                      closes_at: p.ends_at,
                      rates: p.rates,
                    }))
                  : [{ rates: offering.rates }]
                : (definition?.tariffs?.map((p: Row) => ({
                    ...p.hours,
                    rates: p.rates,
                  })) ?? []);
            const prices = tariffs
              .flatMap((t: Row) => t.rates ?? [])
              .filter(
                (v: Row) =>
                  v.duration_minutes === minimum && v.price_minor != null,
              )
              .map((v: Row) => v.price_minor);
            return {
              id: o.id,
              name: o.name,
              kind: o.kind,
              sport: o.sport ?? null,
              format: o.format ?? null,
              minimum_duration: o.minimum_duration ?? null,
              duration_step: o.duration_step ?? null,
              default_duration: o.default_duration ?? o.durations[0],
              fixed_time: o.fixed_time,
              from_minor: prices.length ? Math.min(...prices) : null,
              tariffs: tariffs.map((t: Row) => ({
                days: t.days ?? [],
                opens_at: t.opens_at ?? null,
                closes_at: t.closes_at ?? null,
                date_from: t.date_from ?? null,
                date_until: t.date_until ?? null,
                price_minor:
                  t.rates?.find((v: Row) => v.duration_minutes === minimum)
                    ?.price_minor ?? null,
              })),
            };
          }),
      };
    })
    .filter((r: Row) => r.options.length);
}

@Injectable()
export class WebsiteService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  private async ownerSite(actor: Actor, db: Queryable = this.db, lock = false) {
    const m = await this.workspace.member(actor, true, db);
    const org = (
      await db.query<Row>(
        "SELECT id,name,contact_phone FROM organizations WHERE id=$1",
        [m.organization_id],
      )
    ).rows[0];
    await ensureWebsiteDraft(db, {
      id: org.id,
      name: org.name,
      contact_phone: org.contact_phone,
    });
    const site = (
      await db.query<Row>(
        `SELECT * FROM booking_websites WHERE organization_id=$1${lock ? " FOR UPDATE" : ""}`,
        [m.organization_id],
      )
    ).rows[0];
    return site;
  }
  /**
   * Each website is served from `https://<slug>.<BOOKING_WEBSITE_DOMAIN>`.
   * BOOKING_WEBSITE_URL remains a path-based fallback (`<origin>/<slug>`).
   */
  private siteUrl(slug: string) {
    const domain = process.env.BOOKING_WEBSITE_DOMAIN?.trim().toLowerCase();
    if (domain) {
      const local =
        process.env.NODE_ENV !== "production" &&
        /^localhost(:\d+)?$/.test(domain);
      if (
        !local &&
        !/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(domain)
      )
        throw new Error(
          "BOOKING_WEBSITE_DOMAIN must be a domain such as bookingos.online",
        );
      return `${local ? "http" : "https"}://${slug}.${domain}`;
    }
    const base = this.publicBase();
    return base ? `${base}/${slug}` : null;
  }
  private publicBase() {
    const value = process.env.BOOKING_WEBSITE_URL;
    if (value) {
      const u = new URL(value);
      if (
        u.protocol !== "https:" &&
        !(
          process.env.NODE_ENV !== "production" &&
          ["localhost", "127.0.0.1"].includes(u.hostname)
        )
      )
        throw new Error("BOOKING_WEBSITE_URL must use HTTPS");
      return u.origin;
    }
    return null;
  }
  /** Space rows only hold overrides; a space without one is shown with the site defaults. */
  private async spaceRows(
    db: Queryable,
    websiteId: string,
    businessId?: string,
  ) {
    return (
      await db.query<Row>(
        `SELECT business_id,resource_id,visible,notice_minutes,advance_days,rules,payment_required,payment_percentages FROM booking_website_spaces
        WHERE website_id=$1${businessId ? " AND business_id=$2" : ""}`,
        businessId ? [websiteId, businessId] : [websiteId],
      )
    ).rows;
  }
  private spaceRules(
    site: Row,
    rows: Row[],
    businessId: string,
    resourceId: string,
  ): SpaceRules {
    const row = rows.find(
      (r) => r.business_id === businessId && r.resource_id === resourceId,
    );
    return {
      visible: row?.visible ?? true,
      notice_minutes: row?.notice_minutes ?? site.notice_minutes,
      advance_days: row?.advance_days ?? site.advance_days,
      rules: row?.rules ?? "",
      payment_required: row?.payment_required ?? false,
      payment_percentages: row?.payment_percentages ?? [],
    };
  }
  private async settingsProjection(site: Row) {
    const businesses = (
      await this.db.query<Row>(
        `SELECT b.id,b.name,b.type,b.status,b.configuration,wb.business_id IS NOT NULL AS enabled,
      COALESCE(wb.card_description,'') AS card_description
      FROM businesses b LEFT JOIN booking_website_businesses wb ON wb.website_id=$1 AND wb.business_id=b.id
      WHERE b.organization_id=$2 ORDER BY b.display_order,b.id`,
        [site.id, site.organization_id],
      )
    ).rows;
    const spaces = await this.spaceRows(this.db, site.id);
    const { preview_hash, preview_expires_at, ...safe } = site;
    return {
      ...safe,
      businesses: businesses.map(({ configuration, ...b }) => ({
        ...b,
        resources: websiteResources({ ...b, configuration }).map((r: Row) => {
          const row = spaces.find(
            (v) => v.business_id === b.id && v.resource_id === r.id,
          );
          return {
            id: r.id,
            name: r.name,
            visible: row?.visible ?? true,
            notice_minutes: row?.notice_minutes ?? null,
            advance_days: row?.advance_days ?? null,
            rules: row?.rules ?? "",
            payment_required: row?.payment_required ?? false,
            payment_percentages: row?.payment_percentages ?? [],
          };
        }),
      })),
      images: (
        await this.db.query<Row>(
          "SELECT id,kind,business_id,resource_id,position FROM booking_website_images WHERE website_id=$1 ORDER BY position,created_at,id",
          [site.id],
        )
      ).rows,
      url: this.siteUrl(site.slug),
      domain: process.env.BOOKING_WEBSITE_DOMAIN?.trim().toLowerCase() || null,
    };
  }
  async settings(actor: Actor) {
    return this.settingsProjection(
      await this.db.transaction((db) => this.ownerSite(actor, db)),
    );
  }
  async save(actor: Actor, input: unknown) {
    const v = websiteSettingsSchema.parse(input);
    const site = await this.db.transaction(async (db) => {
      const old = await this.ownerSite(actor, db, true);
      if (old.version !== v.version)
        throw new ConflictException(
          "Website settings changed. Reload before saving.",
        );
      if (old.slug !== v.slug) {
        websiteSubdomain.parse(v.slug);
        const taken = await db.query(
          "SELECT 1 FROM booking_websites WHERE slug=$1 AND id<>$2",
          [v.slug, old.id],
        );
        if (taken.rows.length)
          throw new ConflictException(
            "This website address is already taken. Choose another.",
          );
      }
      const businessRows = (
        await db.query<Row>(
          "SELECT * FROM businesses WHERE organization_id=$1 AND id=ANY($2::uuid[])",
          [old.organization_id, v.business_ids],
        )
      ).rows;
      if (businessRows.length !== v.business_ids.length)
        throw new BadRequestException(
          "Choose businesses from this organisation.",
        );
      if (
        old.status === "published" &&
        !businessRows.some(
          (b) => b.status === "ready" && websiteResources(b).length,
        )
      )
        throw new BadRequestException(
          "A published website needs an active business with normal booking options.",
        );
      if (v.spaces) {
        const previousSpaces = await this.spaceRows(db, old.id);
        const payment = await paymentSettings(db, old.organization_id, true);
        const savedSpaces = v.spaces.map((space) => {
          const previous = previousSpaces.find(
            (row) =>
              row.business_id === space.business_id &&
              row.resource_id === space.resource_id,
          );
          return {
            ...space,
            payment_required:
              space.payment_required ?? previous?.payment_required ?? false,
            payment_percentages:
              space.payment_percentages ?? previous?.payment_percentages ?? [],
          };
        });
        for (const previous of previousSpaces) {
          if (
            previous.payment_required &&
            !savedSpaces.some(
              (space) =>
                space.business_id === previous.business_id &&
                space.resource_id === previous.resource_id,
            )
          )
            savedSpaces.push({
              ...previous,
              visible: true,
              notice_minutes: null,
              advance_days: null,
              rules: "",
            } as (typeof savedSpaces)[number]);
        }
        if (
          savedSpaces.some(
            (space) =>
              space.payment_required &&
              (!space.payment_percentages.length ||
                !payment.upi_id ||
                !payment.has_qr),
          )
        )
          throw new BadRequestException(
            "Add your UPI ID and QR code in Accounts & payments and choose at least one payment percentage first.",
          );
        const organization = (
          await db.query<Row>(
            "SELECT currency FROM organizations WHERE id=$1",
            [old.organization_id],
          )
        ).rows[0];
        if (
          organization.currency !== "INR" &&
          savedSpaces.some((space) => space.payment_required)
        )
          throw new BadRequestException(
            "UPI checkout is available only for INR bookings.",
          );
        const all = (
          await db.query<Row>(
            "SELECT * FROM businesses WHERE organization_id=$1",
            [old.organization_id],
          )
        ).rows;
        for (const space of savedSpaces) {
          const b = all.find((x) => x.id === space.business_id);
          if (
            !b ||
            !websiteResources(b).some((r: Row) => r.id === space.resource_id)
          )
            throw new BadRequestException(
              "Choose normal booking spaces from this organisation.",
            );
        }
        await db.query(
          "DELETE FROM booking_website_spaces WHERE website_id=$1",
          [old.id],
        );
        for (const space of savedSpaces)
          await db.query(
            `INSERT INTO booking_website_spaces(website_id,organization_id,business_id,resource_id,visible,notice_minutes,advance_days,rules,payment_required,payment_percentages)
            VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
            [
              old.id,
              old.organization_id,
              space.business_id,
              space.resource_id,
              space.visible,
              space.notice_minutes,
              space.advance_days,
              space.rules,
              space.payment_required,
              space.payment_percentages,
            ],
          );
      }
      const previous = (
        await db.query<Row>(
          "SELECT business_id,card_description FROM booking_website_businesses WHERE website_id=$1",
          [old.id],
        )
      ).rows;
      await db.query(
        "DELETE FROM booking_website_businesses WHERE website_id=$1",
        [old.id],
      );
      for (const [order, id] of v.business_ids.entries())
        await db.query(
          "INSERT INTO booking_website_businesses(website_id,organization_id,business_id,display_order,card_description) VALUES($1,$2,$3,$4,$5)",
          [
            old.id,
            old.organization_id,
            id,
            order,
            v.card_descriptions?.[id] ??
              previous.find((p) => p.business_id === id)?.card_description ??
              "",
          ],
        );
      const row = (
        await db.query<Row>(
          `UPDATE booking_websites SET slug=$1,title=$2,description=$3,contact_phone=$4,instructions=$5,cancellation_policy=$6,
        publish_logo=$7,notice_minutes=$8,advance_days=$9,hero_heading=$11,social_links=$12,version=version+1,updated_at=now(),preview_hash=NULL,preview_expires_at=NULL
        WHERE id=$10 RETURNING *`,
          [
            v.slug,
            v.title,
            v.description,
            v.contact_phone,
            v.instructions,
            v.cancellation_policy,
            v.publish_logo,
            v.notice_minutes,
            v.advance_days,
            old.id,
            v.hero_heading ?? old.hero_heading,
            JSON.stringify(
              v.social_links
                ? Object.fromEntries(
                    Object.entries(v.social_links).filter(([, url]) => url),
                  )
                : old.social_links,
            ),
          ],
        )
      ).rows[0];
      await this.workspace.audit(
        db,
        actor,
        old.organization_id,
        "website.settings_saved",
        old.id,
      );
      return row;
    });
    return this.settingsProjection(site);
  }
  async uploadImage(actor: Actor, input: unknown) {
    const v = websiteImageSchema.parse(input),
      data = websiteImage(v);
    const site = await this.db.transaction(async (db) => {
      const old = await this.ownerSite(actor, db, true);
      if (old.version !== v.version)
        throw new ConflictException(
          "Website settings changed. Reload before uploading.",
        );
      if (v.kind === "space" || v.kind === "card") {
        const b = (
          await db.query<Row>(
            "SELECT * FROM businesses WHERE id=$1 AND organization_id=$2",
            [v.business_id, old.organization_id],
          )
        ).rows[0];
        if (
          !b ||
          !websiteResources(b).some(
            (r: Row) => v.kind === "card" || r.id === v.resource_id,
          )
        )
          throw new BadRequestException(
            "Choose a normal booking space from this organisation.",
          );
      }
      // Hero, logo and card photos have a single slot and are replaced.
      const single = v.kind !== "space";
      const images = (
        await db.query<Row>(
          "SELECT id,kind,business_id,resource_id,position FROM booking_website_images WHERE website_id=$1",
          [old.id],
        )
      ).rows;
      const same = images.filter(
        (i) =>
          i.kind === v.kind &&
          (v.kind === "hero" ||
            v.kind === "logo" ||
            (i.business_id === v.business_id &&
              i.resource_id === (v.resource_id ?? null))),
      );
      if (v.kind === "space" && same.length >= 4)
        throw new BadRequestException(
          "Each space can have up to 4 photos. Remove one first.",
        );
      if (images.length - (single ? same.length : 0) >= 40)
        throw new BadRequestException(
          "A website can have up to 40 photos. Remove an unused photo first.",
        );
      for (const image of single ? same : [])
        await db.query(
          "DELETE FROM booking_website_images WHERE website_id=$1 AND id=$2",
          [old.id, image.id],
        );
      const position =
        [0, 1, 2, 3].find((n) => !same.some((i) => i.position === n)) ?? 0;
      const id = randomUUID();
      await db.query(
        `INSERT INTO booking_website_images(id,website_id,organization_id,kind,business_id,resource_id,position,content_type,data)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [
          id,
          old.id,
          old.organization_id,
          v.kind,
          v.business_id ?? null,
          v.resource_id ?? null,
          single ? 0 : position,
          v.content_type,
          data,
        ],
      );
      await this.workspace.audit(
        db,
        actor,
        old.organization_id,
        "website.image_uploaded",
        id,
      );
      return (
        await db.query<Row>(
          "UPDATE booking_websites SET version=version+1,updated_at=now(),preview_hash=NULL,preview_expires_at=NULL WHERE id=$1 RETURNING *",
          [old.id],
        )
      ).rows[0];
    });
    return this.settingsProjection(site);
  }
  async removeImage(actor: Actor, id: string, input: unknown) {
    z.uuid().parse(id);
    const { version } = z
      .object({ version: z.number().int().positive() })
      .strict()
      .parse(input);
    const site = await this.db.transaction(async (db) => {
      const old = await this.ownerSite(actor, db, true);
      if (old.version !== version)
        throw new ConflictException(
          "Website settings changed. Reload before removing a photo.",
        );
      const removed = await db.query(
        "DELETE FROM booking_website_images WHERE website_id=$1 AND id=$2 RETURNING id",
        [old.id, id],
      );
      if (!removed.rows.length) throw new NotFoundException("Photo not found.");
      await this.workspace.audit(
        db,
        actor,
        old.organization_id,
        "website.image_removed",
        id,
      );
      return (
        await db.query<Row>(
          "UPDATE booking_websites SET version=version+1,updated_at=now(),preview_hash=NULL,preview_expires_at=NULL WHERE id=$1 RETURNING *",
          [old.id],
        )
      ).rows[0];
    });
    return this.settingsProjection(site);
  }
  async ownerImage(actor: Actor, id: string) {
    z.uuid().parse(id);
    const site = await this.ownerSite(actor);
    const image = (
      await this.db.query<Row>(
        "SELECT data,content_type FROM booking_website_images WHERE website_id=$1 AND id=$2",
        [site.id, id],
      )
    ).rows[0];
    if (!image) throw new NotFoundException("Photo not found.");
    return image;
  }
  async image(slug: string, id: string, preview?: string) {
    z.uuid().parse(id);
    const site = await this.publicSite(slug, preview);
    const image = (
      await this.db.query<Row>(
        "SELECT * FROM booking_website_images WHERE website_id=$1 AND id=$2",
        [site.id, id],
      )
    ).rows[0];
    if (!image) throw new NotFoundException("Photo not found.");
    if (image.kind === "space" || image.kind === "card") {
      const b = (
        await this.db.query<Row>(
          `SELECT b.* FROM businesses b JOIN booking_website_businesses wb ON wb.business_id=b.id AND wb.organization_id=b.organization_id
        WHERE wb.website_id=$1 AND b.id=$2 AND b.status='ready'`,
          [site.id, image.business_id],
        )
      ).rows[0];
      const spaces = b ? await this.spaceRows(this.db, site.id, b.id) : [];
      if (
        !b ||
        !websiteResources(b).some(
          (r: Row) =>
            (image.kind === "card" || r.id === image.resource_id) &&
            this.spaceRules(site, spaces, b.id, r.id).visible,
        )
      )
        throw new NotFoundException("Photo not found.");
    }
    return { data: image.data, content_type: image.content_type };
  }
  async publication(
    actor: Actor,
    status: "published" | "paused" | "unpublished",
    input: unknown,
  ) {
    const { version } = z
      .object({ version: z.number().int().positive() })
      .strict()
      .parse(input);
    const site = await this.db.transaction(async (db) => {
      const old = await this.ownerSite(actor, db, true);
      if (old.version !== version)
        throw new ConflictException(
          "Website settings changed. Reload before publishing.",
        );
      if (status === "published") {
        const businesses = (
          await db.query<Row>(
            `SELECT b.* FROM businesses b JOIN booking_website_businesses wb ON wb.business_id=b.id
          WHERE wb.website_id=$1 AND b.status='ready'`,
            [old.id],
          )
        ).rows;
        if (!businesses.some((b) => websiteResources(b).length))
          throw new BadRequestException(
            "Enable at least one active business with normal booking options.",
          );
        if (!this.siteUrl(old.slug))
          throw new BadRequestException(
            "Configure BOOKING_WEBSITE_DOMAIN on the API before publishing.",
          );
      }
      const row = (
        await db.query<Row>(
          `UPDATE booking_websites SET status=$1,first_published_at=CASE WHEN $1='published' THEN COALESCE(first_published_at,now()) ELSE first_published_at END,
        version=version+1,updated_at=now(),preview_hash=NULL,preview_expires_at=NULL WHERE id=$2 RETURNING *`,
          [status, old.id],
        )
      ).rows[0];
      await this.workspace.audit(
        db,
        actor,
        old.organization_id,
        `website.${status}`,
        old.id,
      );
      return row;
    });
    return this.settingsProjection(site);
  }
  async preview(actor: Actor) {
    return this.db.transaction(async (db) => {
      const site = await this.ownerSite(actor, db, true),
        token = randomBytes(32).toString("hex");
      const url = this.siteUrl(site.slug);
      if (!url)
        throw new BadRequestException(
          "Configure BOOKING_WEBSITE_DOMAIN on the API to preview the website.",
        );
      await db.query(
        "UPDATE booking_websites SET preview_hash=$1,preview_expires_at=now()+interval '1 hour' WHERE id=$2",
        [hash(token), site.id],
      );
      const link = new URL(url);
      link.searchParams.set("preview", token);
      return {
        url: link.toString(),
        expires_in_seconds: 3600,
      };
    });
  }
  private async site(
    slug: string,
    db: Queryable = this.db,
    preview?: string,
    lock = false,
    allowHidden = false,
  ): Promise<Row> {
    websiteSlug.parse(slug);
    const site = (
      await db.query<Row>(
        `SELECT w.*,o.currency,EXISTS(SELECT 1 FROM logo_assets a WHERE a.organization_id=w.organization_id) AS logo_available,
        EXISTS(SELECT 1 FROM booking_website_images i WHERE i.website_id=w.id AND i.kind='logo') AS website_logo FROM booking_websites w JOIN organizations o ON o.id=w.organization_id WHERE w.slug=$1${lock ? " FOR SHARE OF w" : ""}`,
        [slug],
      )
    ).rows[0];
    const isPreview =
      !!site &&
      !!preview &&
      /^[a-f0-9]{64}$/.test(preview) &&
      site.preview_hash === hash(preview) &&
      Date.parse(site.preview_expires_at) > Date.now();
    if (
      !site ||
      (!allowHidden &&
        (preview ? !isPreview : !["published", "paused"].includes(site.status)))
    )
      throw new NotFoundException("This booking website is not available.");
    return { ...site, is_preview: isPreview };
  }
  private async limit(
    db: Queryable,
    site: Row,
    key: string,
    max: number,
    seconds: number,
  ) {
    const window = Math.floor(Date.now() / (seconds * 1000));
    const result = await db.query(
      `INSERT INTO booking_website_limits(website_id,bucket,used,expires_at) VALUES($1,$2,1,$3)
      ON CONFLICT(website_id,bucket) DO UPDATE SET used=booking_website_limits.used+1 WHERE booking_website_limits.used<$4 RETURNING used`,
      [
        site.id,
        `${key}:${window}`,
        new Date((window + 1) * seconds * 1000).toISOString(),
        max,
      ],
    );
    if (!result.rows.length)
      throw new HttpException(
        "Too many booking requests. Please try again later or contact the venue.",
        429,
      );
  }
  private async publicSite(slug: string, preview?: string) {
    const site = await this.site(slug, this.db, preview);
    await this.db.query(
      "DELETE FROM booking_website_limits WHERE website_id=$1 AND expires_at<now()",
      [site.id],
    );
    await this.limit(this.db, site, "read", 1200, 60);
    return site;
  }
  async catalog(slug: string, preview?: string) {
    const site = await this.publicSite(slug, preview);
    const images = (
      await this.db.query<Row>(
        "SELECT id,kind,business_id,resource_id,position FROM booking_website_images WHERE website_id=$1 ORDER BY position,created_at,id",
        [site.id],
      )
    ).rows;
    const spaces = await this.spaceRows(this.db, site.id);
    const businesses = (
      await this.db.query<Row>(
        `SELECT b.*,wb.card_description,l.name AS location_name,l.timezone,l.address_line_1,l.address_line_2,l.city,l.state_code,l.country_code,l.postal_code
      FROM booking_website_businesses wb JOIN businesses b ON b.id=wb.business_id AND b.organization_id=wb.organization_id
      JOIN locations l ON l.id=b.location_id WHERE wb.website_id=$1 AND b.status='ready' ORDER BY wb.display_order,b.display_order,b.id`,
        [site.id],
      )
    ).rows
      .map((b) => ({
        id: b.id,
        name: b.name,
        type: b.type,
        timezone: b.timezone,
        today: localStamp(Date.now(), b.timezone).slice(0, 10),
        location_name: b.location_name,
        address: [
          b.address_line_1,
          b.address_line_2,
          b.city,
          b.state_code,
          b.postal_code,
        ]
          .filter(Boolean)
          .join(", "),
        description: b.card_description,
        card_image:
          images.find((i) => i.kind === "card" && i.business_id === b.id)?.id ??
          null,
        resources: websiteResources(b)
          .map((r: Row) => ({
            r,
            rules: this.spaceRules(site, spaces, b.id, r.id),
          }))
          .filter(({ rules }: { rules: SpaceRules }) => rules.visible)
          .map(({ r, rules }: { r: Row; rules: SpaceRules }) => ({
            ...r,
            notice_minutes: rules.notice_minutes,
            advance_days: rules.advance_days,
            rules: rules.rules,
            payment_required: rules.payment_required,
            payment_percentages: rules.payment_percentages,
            images: images
              .filter(
                (i) =>
                  i.kind === "space" &&
                  i.business_id === b.id &&
                  i.resource_id === r.id,
              )
              .map((i) => i.id),
          })),
      }))
      .filter((b) => b.resources.length);
    return {
      slug: site.slug,
      title: site.title,
      description: site.description,
      contact_phone: site.contact_phone,
      instructions: site.instructions,
      cancellation_policy: site.cancellation_policy,
      currency: site.currency,
      status: site.status,
      is_preview: site.is_preview,
      has_logo: site.website_logo || (site.publish_logo && site.logo_available),
      hero_image: images.find((i) => i.kind === "hero")?.id ?? null,
      hero_heading: site.hero_heading,
      social_links: site.social_links ?? {},
      notice_minutes: site.notice_minutes,
      advance_days: site.advance_days,
      businesses,
    };
  }
  async paymentQr(slug: string, preview?: string, version?: string) {
    const site = await this.publicSite(slug, preview);
    const row = (
      await this.db.query<Row>(
        "SELECT qr_data,qr_content_type,version FROM website_payment_settings WHERE organization_id=$1",
        [site.organization_id],
      )
    ).rows[0];
    if (!row?.qr_data)
      throw new NotFoundException("Payment QR code not found.");
    if (version !== undefined && String(row.version) !== version)
      throw new ConflictException(
        "Payment details changed. Refresh checkout before paying.",
      );
    return { data: row.qr_data, content_type: row.qr_content_type };
  }
  async logo(slug: string, preview?: string) {
    const site = await this.publicSite(slug, preview);
    const own = (
      await this.db.query<Row>(
        "SELECT data,content_type FROM booking_website_images WHERE website_id=$1 AND kind='logo'",
        [site.id],
      )
    ).rows[0];
    if (own) return own;
    if (!site.publish_logo) throw new NotFoundException("Logo not published.");
    const logo = (
      await this.db.query<Row>(
        "SELECT data,content_type FROM logo_assets WHERE organization_id=$1",
        [site.organization_id],
      )
    ).rows[0];
    if (!logo) throw new NotFoundException("Logo not found.");
    return logo;
  }
  private async business(
    db: Queryable,
    site: Row,
    selection: BookingSelection,
    lock = false,
  ) {
    const b = (
      await db.query<Row>(
        `SELECT b.*,l.timezone FROM businesses b JOIN locations l ON l.id=b.location_id
      JOIN booking_website_businesses wb ON wb.business_id=b.id AND wb.organization_id=b.organization_id
      WHERE wb.website_id=$1 AND b.organization_id=$2 AND b.id=$3 AND b.status='ready'${lock ? " FOR UPDATE OF b" : ""}`,
        [site.id, site.organization_id, selection.business_id],
      )
    ).rows[0];
    if (!b)
      throw new NotFoundException(
        "This business is not available for online booking.",
      );
    const rules = this.spaceRules(
      site,
      await this.spaceRows(db, site.id, b.id),
      b.id,
      selection.resource_id,
    );
    const option = websiteResources(b)
      .find((r: Row) => r.id === selection.resource_id)
      ?.options.find((o: Row) => o.id === selection.option_id);
    if (!option || !rules.visible)
      throw new BadRequestException(
        "Only normal bookings are available on this website.",
      );
    if (b.type !== "pool" && selection.people !== 1)
      throw new BadRequestException(
        "Participant count is only required for pool bookings.",
      );
    const today = localStamp(Date.now(), b.timezone).slice(0, 10);
    if (
      selection.date < today ||
      selection.date > addDate(today, rules.advance_days)
    )
      throw new BadRequestException(
        "Choose a date within the online booking window.",
      );
    return Object.assign(b, { website_rules: rules });
  }
  private notice(b: Row, q: ReturnType<typeof buildQuote>) {
    if (
      Date.parse(q.starts_at) <
      Date.now() + b.website_rules.notice_minutes * 60000
    )
      throw new BadRequestException(
        "This time is too soon. Choose a later slot.",
      );
  }
  private quoteProjection(q: ReturnType<typeof buildQuote>, currency: string) {
    return {
      quote_token: q.quote_token,
      starts_at: q.starts_at,
      ends_at: q.ends_at,
      local_start: q.local_start,
      local_end: q.local_end,
      timezone: q.timezone,
      space_name: q.space_name,
      option_name: q.option_name,
      total_minor: q.total_minor,
      currency,
    };
  }
  private async checkoutQuote(
    db: Queryable,
    site: Row,
    business: Row,
    quote: ReturnType<typeof buildQuote>,
    lock = false,
  ) {
    const settings = await paymentSettings(db, site.organization_id, lock);
    const payment = paymentPolicy(
      business.website_rules.payment_required,
      business.website_rules.payment_percentages,
      quote.total_minor,
      site.currency,
      settings,
    );
    return {
      ...this.quoteProjection(quote, site.currency),
      payment,
      quote_token:
        settings.version || payment.required
          ? hash(JSON.stringify([quote.quote_token, payment]))
          : quote.quote_token,
    };
  }
  async availability(slug: string, input: unknown, preview?: string) {
    const v = publicAvailabilitySchema.parse(input),
      site = await this.publicSite(slug, preview);
    return this.db.transaction(async (db) => {
      const b = await this.business(db, site, v.selection);
      const result = await bookingAvailability(db, b, v.selection, v.end_times);
      const threshold = localStamp(
        Date.now() + b.website_rules.notice_minutes * 60000,
        b.timezone,
      );
      for (const slot of result.slots)
        if (
          slot.available &&
          `${v.end_times ? v.selection.date : (slot.date ?? v.selection.date)}T${v.end_times ? v.selection.time : slot.time}` <
            threshold
        )
          Object.assign(slot, { available: false, status: "past" });
      return result;
    });
  }
  async quote(slug: string, input: unknown, preview?: string) {
    const v = publicQuoteSchema.parse(input),
      site = await this.publicSite(slug, preview);
    return this.db.transaction(async (db) => {
      const b = await this.business(db, site, v.selection),
        q = buildQuote(b, v.selection, b.timezone);
      this.notice(b, q);
      checkInventory(
        q,
        await inventoryAllocations(db, b.id, q.occupied_from, q.occupied_until),
      );
      return this.checkoutQuote(db, site, b, q);
    });
  }
  async book(slug: string, input: unknown, preview?: string) {
    const v = publicCreateSchema.parse(input);
    if (preview)
      throw new ForbiddenException(
        "Preview is read-only. Publish the website before accepting bookings.",
      );
    // Count well-formed confirmation attempts, including unavailable selections, across workers.
    const initial = await this.site(slug, this.db, undefined, false, true);
    await this.limit(this.db, initial, "read", 1200, 60);
    return this.db.transaction(async (db) => {
      const site = await this.site(slug, db, undefined, true, true),
        actor = `website:${site.id}`,
        requestHash = hash(JSON.stringify(v));
      await db.query(
        `INSERT INTO booking_commands(organization_id,command_key,actor_id,kind,request_hash) VALUES($1,$2,$3,'website.create',$4) ON CONFLICT DO NOTHING`,
        [site.organization_id, v.command_key, actor, requestHash],
      );
      const command = (
        await db.query<Row>(
          "SELECT * FROM booking_commands WHERE organization_id=$1 AND command_key=$2 FOR UPDATE",
          [site.organization_id, v.command_key],
        )
      ).rows[0];
      if (
        command.actor_id !== actor ||
        command.kind !== "website.create" ||
        command.request_hash !== requestHash
      )
        throw new ConflictException(
          "This request key belongs to different booking data.",
        );
      if (command.response) return command.response;
      if (site.status !== "published")
        throw new ConflictException(
          "Online bookings are paused. Please contact the venue.",
        );
      await db.query("SELECT id FROM organizations WHERE id=$1 FOR UPDATE", [
        site.organization_id,
      ]);
      const b = await this.business(db, site, v.selection, true),
        q = buildQuote(b, v.selection, b.timezone);
      this.notice(b, q);
      const checkout = await this.checkoutQuote(db, site, b, q, true);
      if (checkout.quote_token !== v.quote_token)
        throw new ConflictException(
          "Pricing changed. Review the updated price before confirming.",
        );
      checkInventory(
        q,
        await inventoryAllocations(db, b.id, q.occupied_from, q.occupied_until),
      );
      await this.limit(db, site, "confirm", 30, 3600);
      const option = v.payment
        ? checkout.payment.options.find(
            (entry) => entry.percentage === v.payment!.percentage,
          )
        : null;
      if (checkout.payment.required && !v.payment)
        throw new BadRequestException(
          "Choose a payment amount and enter the transaction ID.",
        );
      if (v.payment && !option)
        throw new BadRequestException(
          "Choose one of the payment options offered for this space.",
        );
      if (
        v.payment &&
        (
          await db.query(
            "SELECT 1 FROM bookings WHERE organization_id=$1 AND upper(website_payment_submission->>'transaction_id')=$2 LIMIT 1",
            [site.organization_id, v.payment.transaction_id],
          )
        ).rows.length
      )
        throw new ConflictException(
          "This transaction ID was already submitted. Contact the venue if you need help.",
        );
      const submission =
        v.payment && option
          ? {
              ...v.payment,
              amount_minor: option.amount_minor,
              upi_id: checkout.payment.upi_id,
              status: "pending_verification",
            }
          : null;
      await this.limit(
        db,
        site,
        `phone:${hash(v.customer.phone.replace(/\D/g, "").replace(/^0+/, ""))}`,
        3,
        3600,
      );
      const id = randomUUID(),
        customerId = randomUUID(),
        reference = `BK-${id.replace(/-/g, "").slice(0, 12).toUpperCase()}`;
      const customer = {
        id: customerId,
        name: v.customer.name,
        phone: v.customer.phone.replace(/[^\d+]/g, ""),
        email: null,
      };
      // Guest input never rewrites a saved customer profile based on an unverified phone.
      await db.query(
        "INSERT INTO customers(id,organization_id,name,phone) VALUES($1,$2,$3,$4)",
        [customerId, site.organization_id, customer.name, customer.phone],
      );
      await db.query(
        `INSERT INTO bookings(id,organization_id,business_id,resource_id,customer_id,reference,starts_at,ends_at,total_minor,selection,price_snapshot,customer_snapshot,people,created_by,booking_source,booking_website_id,website_payment_submission)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,'website',$15,$16)`,
        [
          id,
          site.organization_id,
          b.id,
          v.selection.resource_id,
          customerId,
          reference,
          q.starts_at,
          q.ends_at,
          q.total_minor,
          JSON.stringify(v.selection),
          JSON.stringify(q),
          JSON.stringify(customer),
          v.selection.people,
          actor,
          site.id,
          submission ? JSON.stringify(submission) : null,
        ],
      );
      for (const key of q.inventory_keys)
        await db.query(
          "INSERT INTO booking_allocations(booking_id,inventory_key,starts_at,ends_at,quantity) VALUES($1,$2,$3,$4,$5)",
          [id, key, q.occupied_from, q.occupied_until, q.quantity],
        );
      await recordBookingHistory(db, id, actor, "created", {
        source: "website",
        selection: v.selection,
        total_minor: q.total_minor,
        website_payment_submission: submission,
      });
      const response = {
        reference,
        status: "confirmed",
        payment_status: q.total_minor === 0 ? "paid" : "unpaid",
        ...checkout,
        website_payment_submission: submission,
      };
      await db.query(
        "UPDATE booking_commands SET response=$1 WHERE organization_id=$2 AND command_key=$3",
        [JSON.stringify(response), site.organization_id, v.command_key],
      );
      return response;
    });
  }
}
