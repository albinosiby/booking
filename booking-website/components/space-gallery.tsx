"use client";
import { useState } from "react";
import { imageLink } from "../lib/site-links";
import { PhotoViewer } from "./photo-viewer";

export function SpaceGallery({
  slug,
  images,
  name,
  preview,
}: {
  slug: string;
  images: string[];
  name: string;
  preview?: string;
}) {
  const [selected, setSelected] = useState<number | null>(null);
  if (!images.length) return null;
  return (
    <section className="space-gallery" aria-label={`${name} photos`}>
      <div className="venue-gallery-heading">
        <p className="eyebrow">Take a look around</p>
        <h2>Venue photos</h2>
        <p>{name} · Tap a photo to view fullscreen.</p>
      </div>
      <div className="venue-gallery-grid">
        {images.map((id, i) => (
          <button
            type="button"
            key={id}
            aria-label={`View ${name} photo ${i + 1} fullscreen`}
            onClick={() => setSelected(i)}
          >
            <img
              src={imageLink(slug, id, preview)}
              alt={`${name} — venue photo ${i + 1}`}
              loading="lazy"
            />
            <span className="photo-expand-hint">View fullscreen</span>
          </button>
        ))}
      </div>
      {selected !== null && (
        <PhotoViewer
          slug={slug}
          images={images}
          name={name}
          initialIndex={selected}
          preview={preview}
          onClose={() => setSelected(null)}
        />
      )}
    </section>
  );
}
