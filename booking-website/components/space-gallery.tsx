"use client";
import { useState } from "react";
import { imageLink } from "../lib/site-links";

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
  const [selected, setSelected] = useState(images[0]);
  if (!images.length) return null;
  const current = images.includes(selected) ? selected : images[0];
  return (
    <section className="space-gallery" aria-label={`${name} photos`}>
      <div className="gallery-main">
        <img
          src={imageLink(slug, current, preview)}
          alt={`${name} — photo ${images.indexOf(current) + 1}`}
          fetchPriority="high"
        />
        <span>{name}</span>
      </div>
      {images.length > 1 && (
        <div className="gallery-thumbnails" aria-label="Choose a photo">
          {images.map((id, i) => (
            <button
              key={id}
              aria-label={`Show ${name} photo ${i + 1}`}
              aria-pressed={current === id}
              onClick={() => setSelected(id)}
            >
              <img src={imageLink(slug, id, preview)} alt="" />
            </button>
          ))}
        </div>
      )}
    </section>
  );
}
