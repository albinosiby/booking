"use client";
import { useId } from "react";
import type { Resource } from "../lib/types";
export function SpaceIllustration({
  type,
  sport,
  name,
  selected,
  resources = [],
  onSelect,
}: {
  type: string;
  sport?: string | null;
  name: string;
  selected?: Resource;
  resources?: Resource[];
  onSelect?: (r: Resource) => void;
}) {
  const id = useId().replace(/:/g, "");
  const turf = type === "turf",
    pool = type === "pool",
    cricket = sport === "cricket";
  const halves =
    turf && selected?.ground_id
      ? resources.filter(
          (r) =>
            r.ground_id === selected.ground_id && r.section_ids.length === 1,
        )
      : [];
  const selectedSections = new Set(selected?.section_ids ?? []);
  const labels = pool
    ? "SWIMMING POOL"
    : turf
      ? cricket
        ? "CRICKET TURF"
        : "FOOTBALL PITCH"
      : type === "hall"
        ? "EVENT HALL"
        : "COURT";
  return (
    <div
      className={`space-art ${turf ? "turf-art" : ""} ${cricket ? "cricket-art" : ""}`}
    >
      <svg
        viewBox={turf ? "0 0 600 380" : "0 0 600 280"}
        role="img"
        aria-label={`${name} ${labels.toLowerCase()} illustration`}
      >
        <defs>
          <pattern
            id={`${id}grass`}
            width="100"
            height="100"
            patternUnits="userSpaceOnUse"
          >
            <path fill="#105b2b" d="M0 0h100v100H0z" />
            <path fill="#176a32" d="M0 0h50v100H0z" />
          </pattern>
          <pattern
            id={`${id}water`}
            width="32"
            height="24"
            patternUnits="userSpaceOnUse"
          >
            <path fill="#2397b8" d="M0 0h32v24H0z" />
            <path
              d="M-8 8q8-8 16 0t16 0t16 0M-8 20q8-8 16 0t16 0t16 0"
              stroke="#7bd1df"
              strokeWidth="1.4"
              fill="none"
              opacity=".6"
            />
          </pattern>
          <pattern
            id={`${id}court`}
            width="18"
            height="18"
            patternUnits="userSpaceOnUse"
          >
            <path fill="#1b6889" d="M0 0h18v18H0z" />
            <path
              d="m0 18 18-18"
              stroke="#3385a2"
              strokeWidth=".6"
              opacity=".5"
            />
          </pattern>
        </defs>
        <rect
          x="5"
          y="5"
          width="590"
          height={turf ? 370 : 270}
          rx="20"
          fill={
            turf
              ? `url(#${id}grass)`
              : pool
                ? `url(#${id}water)`
                : `url(#${id}court)`
          }
          stroke={turf ? (cricket ? "#c3a567" : "#137d68") : "#71b7cf"}
          strokeWidth="10"
        />
        {turf && !cricket && (
          <g stroke="#e9f4df" strokeWidth="2.4" fill="none">
            <rect x="17" y="17" width="566" height="346" />
            <path d="M300 17v346M17 93h89v194H17m566-194h-89v194h89M17 139h34v102H17m566-102h-34v102h34" />
            <circle cx="300" cy="190" r="54" />
            <path d="M106 147a57 57 0 0 1 0 86m388-86a57 57 0 0 0 0 86M17 31a14 14 0 0 0 14-14m552 14a14 14 0 0 1-14-14M17 349a14 14 0 0 1 14 14m552-14a14 14 0 0 0-14 14" />
            <circle cx="300" cy="190" r="2" fill="#fff" />
            <path
              d="M106 17v56h388V17m-388 346v-56h388v56"
              strokeDasharray="5 4"
              opacity=".5"
            />
          </g>
        )}
        {turf && cricket && (
          <g stroke="#eef3df" strokeWidth="2" fill="none">
            <ellipse cx="300" cy="190" rx="267" ry="160" />
            <path d="M300 29v322" strokeDasharray="4 5" opacity=".55" />
            <rect
              x="263"
              y="56"
              width="74"
              height="268"
              rx="2"
              fill="#bfa468"
            />
            <path d="M236 80h128M236 300h128M294 70v12m6-12v12m6-12v12m-12 216v12m6-12v12m6-12v12" />
            <circle cx="300" cy="190" r="2" fill="#fff" />
            {[100, 450].map((x) => (
              <g key={x}>
                <rect x={x} y="115" width="50" height="150" fill="#bea067" />
                <rect
                  x={x - 20}
                  y="95"
                  width="90"
                  height="190"
                  strokeDasharray="5 4"
                />
                <path d={`M${x - 10} 131h70M${x - 10} 249h70`} />
              </g>
            ))}
          </g>
        )}
        {pool && (
          <g stroke="#c9eff4" fill="none">
            <rect
              x="29"
              y="28"
              width="542"
              height="224"
              rx="6"
              strokeWidth="2"
            />
            {[59, 93, 127, 161, 195, 229].map((y) => (
              <g key={y}>
                <path
                  d={`M37 ${y}H563`}
                  strokeWidth="2"
                  strokeDasharray="3 5"
                />
                <circle cx="43" cy={y} r="4" fill="#ffd36b" stroke="none" />
                <circle cx="557" cy={y} r="4" fill="#ffd36b" stroke="none" />
                <rect
                  x="21"
                  y={y - 6}
                  width="12"
                  height="12"
                  rx="2"
                  fill="#fff"
                />
                <rect
                  x="567"
                  y={y - 6}
                  width="12"
                  height="12"
                  rx="2"
                  fill="#fff"
                />
              </g>
            ))}
          </g>
        )}
        {!turf && !pool && type !== "hall" && (
          <g stroke="#eaf8fb" strokeWidth="2.5" fill="none">
            <rect x="34" y="34" width="532" height="212" />
            <path d="M34 67h532M34 213h532M110 34v212m380-212v212M300 34v212M110 140h380" />
            <path d="M300 34v212" stroke="#113e56" strokeWidth="11" />
            <path
              d="M300 34v212"
              stroke="#98c3d2"
              strokeWidth="4"
              strokeDasharray="2 3"
            />
            {type === "tennis" && <path d="M34 140h76m380 0h76" />}
            {type === "basketball" && (
              <>
                <circle cx="300" cy="140" r="42" />
                <path d="M34 90h90v100H34m532-100h-90v100h90" />
              </>
            )}
          </g>
        )}
        {type === "hall" && (
          <g fill="#e7c895" stroke="#f6e9cb" strokeWidth="2">
            <rect x="45" y="36" width="510" height="55" rx="8" />
            {[115, 280, 445].flatMap((x) =>
              [140, 210].map((y) => (
                <g key={`${x}-${y}`}>
                  <circle cx={x} cy={y} r="26" />
                  <circle cx={x} cy={y} r="17" fill="#fff8e7" />
                </g>
              )),
            )}
          </g>
        )}
        <rect
          x="25"
          y="25"
          width="300"
          height="46"
          rx="8"
          fill="#143f55"
          opacity=".82"
        />
        <text x="40" y="54" fill="#fff" fontSize="17" fontWeight="650">
          {name.length > 30 ? name.slice(0, 29) + "…" : name}
        </text>
        <rect
          x={turf ? 418 : 420}
          y={turf ? 326 : 226}
          width="155"
          height="30"
          rx="8"
          fill="#fff"
          opacity=".17"
        />
        <text
          x="559"
          y={turf ? 346 : 247}
          textAnchor="end"
          fill="#fff"
          fontSize="12"
          fontWeight="700"
          letterSpacing="2"
        >
          {labels}
        </text>
      </svg>
      {halves.length >= 2 && (
        <div className="pitch-halves">
          {halves.slice(0, 2).map((r) => (
            <button
              key={r.id}
              type="button"
              aria-label={`Select ${r.name}`}
              aria-pressed={r.section_ids.every((id) =>
                selectedSections.has(id),
              )}
              className={
                r.section_ids.every((id) => selectedSections.has(id))
                  ? "active"
                  : ""
              }
              onClick={() => onSelect?.(r)}
            >
              <span>{r.name.split(" · ").at(-1)}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
