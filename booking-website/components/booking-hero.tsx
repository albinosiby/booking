"use client";
import { useState } from "react";
import type { Business } from "../lib/types";
import { imageLink } from "../lib/site-links";
import { PhotoViewer } from "./photo-viewer";
import { SpaceIllustration } from "./space-illustration";

export function BookingHero({
  slug,
  business,
  preview,
}: {
  slug: string;
  business: Business;
  preview?: string;
}) {
  const [open, setOpen] = useState(false);
  const image = business.card_image;
  return (
    <section className="booking-hero" aria-label={`${business.name} hero`}>
      {image ? (
        <button
          type="button"
          className="gallery-main booking-hero-photo"
          aria-label={`View ${business.name} cover photo fullscreen`}
          onClick={() => setOpen(true)}
        >
          <img
            src={imageLink(slug, image, preview)}
            alt={business.name}
            fetchPriority="high"
          />
          <span>{business.name}</span>
          <span className="photo-expand-hint">View fullscreen</span>
        </button>
      ) : (
        <div className="booking-hero-illustration">
          <SpaceIllustration type={business.type} name={business.name} />
        </div>
      )}
      {open && image && (
        <PhotoViewer
          slug={slug}
          images={[image]}
          name={business.name}
          initialIndex={0}
          preview={preview}
          onClose={() => setOpen(false)}
        />
      )}
    </section>
  );
}
