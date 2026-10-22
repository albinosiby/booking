import type { SocialNetwork, Website } from "../lib/types";

const networks: { key: SocialNetwork; label: string; path: string }[] = [
  {
    key: "instagram",
    label: "Instagram",
    path: "M7 3h10a4 4 0 0 1 4 4v10a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V7a4 4 0 0 1 4-4Zm5 5a4 4 0 1 0 0 8 4 4 0 0 0 0-8Zm5.5-1.5h.01",
  },
  {
    key: "facebook",
    label: "Facebook",
    path: "M14 8h3V4h-3a4 4 0 0 0-4 4v3H7v4h3v6h4v-6h3l1-4h-4V8Z",
  },
  { key: "x", label: "X", path: "M4 4l16 16M20 4 4 20" },
  {
    key: "youtube",
    label: "YouTube",
    path: "M3 8a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V8Zm7 1v6l5-3-5-3Z",
  },
  {
    key: "linkedin",
    label: "LinkedIn",
    path: "M4 9h4v11H4V9Zm2-5a2 2 0 1 1 0 4 2 2 0 0 1 0-4Zm5 5h4v2a4 4 0 0 1 7 3v6h-4v-5a2 2 0 0 0-4 0v5h-3V9Z",
  },
  {
    key: "whatsapp",
    label: "WhatsApp",
    path: "M4 20l1.5-4.2A8 8 0 1 1 8.4 18.6L4 20Zm5-11c0 3.5 2.5 6 6 6l1-1.5-2-1-1 1c-1-.5-2-1.5-2.5-2.5l1-1-1-2L9 9Z",
  },
];

/** Owner-provided https links only; the API rejects other schemes. */
export function SocialLinks({
  links,
  compact = false,
}: {
  links: Website["social_links"];
  compact?: boolean;
}) {
  const shown = networks.filter((n) => links?.[n.key]?.startsWith("https://"));
  if (!shown.length) return null;
  return (
    <nav
      className={`social-links ${compact ? "compact" : ""}`}
      aria-label="Social media"
    >
      {shown.map((n) => (
        <a
          key={n.key}
          href={links[n.key]}
          target="_blank"
          rel="noopener noreferrer nofollow"
          aria-label={n.label}
        >
          <svg
            width={compact ? 17 : 19}
            height={compact ? 17 : 19}
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.8"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
            <path d={n.path} />
          </svg>
          {!compact && <span>{n.label}</span>}
        </a>
      ))}
    </nav>
  );
}
