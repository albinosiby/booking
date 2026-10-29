"use client";
import { useEffect, useRef, useState } from "react";
import { imageLink } from "../lib/site-links";
import { Icon } from "./icons";

/** Native modal dialog provides focus containment and Escape handling. */
export function PhotoViewer({
  slug,
  images,
  name,
  initialIndex,
  preview,
  onClose,
}: {
  slug: string;
  images: string[];
  name: string;
  initialIndex: number;
  preview?: string;
  onClose: () => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [index, setIndex] = useState(initialIndex);
  const move = (step: number) =>
    setIndex((current) => (current + step + images.length) % images.length);

  useEffect(() => {
    const element = dialog.current;
    const opener = document.activeElement;
    const overflow = document.body.style.overflow;
    element?.showModal();
    document.body.style.overflow = "hidden";
    return () => {
      element?.close();
      document.body.style.overflow = overflow;
      if (opener instanceof HTMLElement && opener.isConnected) opener.focus();
    };
  }, []);

  return (
    <dialog
      ref={dialog}
      className="photo-viewer"
      aria-label={`${name} photo viewer`}
      onClose={(event) => {
        if (!event.currentTarget.open) onClose();
      }}
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
      onKeyDown={(event) => {
        if (
          images.length > 1 &&
          ["ArrowLeft", "ArrowRight"].includes(event.key)
        ) {
          event.preventDefault();
          move(event.key === "ArrowLeft" ? -1 : 1);
        }
      }}
    >
      <header className="photo-viewer-header">
        <span>{name}</span>
        <button
          type="button"
          aria-label="Close photo viewer"
          onClick={onClose}
          autoFocus
        >
          <span aria-hidden="true">×</span>
        </button>
      </header>
      <div
        className="photo-viewer-stage"
        onClick={(event) => {
          if (event.target === event.currentTarget) onClose();
        }}
      >
        <ViewerImage
          key={images[index]}
          src={imageLink(slug, images[index], preview)}
          alt={`${name} — photo ${index + 1}`}
        />
      </div>
      <footer className="photo-viewer-controls">
        {images.length > 1 && (
          <button
            type="button"
            aria-label="Previous photo"
            onClick={() => move(-1)}
          >
            <Icon name="back" />
          </button>
        )}
        <span role="status" aria-live="polite">
          {index + 1} / {images.length}
        </span>
        {images.length > 1 && (
          <button type="button" aria-label="Next photo" onClick={() => move(1)}>
            <Icon name="arrow" />
          </button>
        )}
      </footer>
    </dialog>
  );
}

function ViewerImage({ src, alt }: { src: string; alt: string }) {
  const [failed, setFailed] = useState(false);
  return failed ? (
    <p role="alert">
      This photo could not be loaded. Try another photo or close the viewer.
    </p>
  ) : (
    <img src={src} alt={alt} onError={() => setFailed(true)} />
  );
}
