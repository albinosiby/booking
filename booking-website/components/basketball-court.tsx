export function BasketballCourt({ patternId }: { patternId: string }) {
  return (
    <g>
      <defs>
        <pattern
          id={patternId}
          width="72"
          height="24"
          patternUnits="userSpaceOnUse"
        >
          <path fill="#d8b17e" d="M0 0h72v24H0z" />
          <path fill="#e2bd8c" d="M0 0h36v12H0zm36 12h36v12H36z" />
          <path
            d="M0 12h72M0 24h72M36 0v12M12 12v12M60 12v12"
            stroke="#986c3e"
            strokeWidth=".7"
            opacity=".3"
          />
          <path
            d="M5 4h23m16 3h20M20 17h29m-45 4h9m43-4h10"
            stroke="#fff0cf"
            strokeWidth=".7"
            opacity=".3"
          />
        </pattern>
      </defs>
      <rect x="10" y="10" width="580" height="340" rx="14" fill={`url(#${patternId})`} />
      <g stroke="#294e54" strokeWidth="2.3" fill="none">
        <rect x="48" y="50" width="504" height="270" />
        <path d="M300 50v270" />
        <circle cx="300" cy="185" r="32.5" fill="#205e5d" stroke="#fff5e4" />
        <circle cx="300" cy="185" r="2.5" fill="#fff5e4" stroke="none" />
        {[false, true].map((mirrored) => (
          <g key={String(mirrored)} transform={mirrored ? "translate(600 0) scale(-1 1)" : undefined}>
            <path d="M48 66h54a121.5 121.5 0 0 1 0 238H48" />
            <rect x="48" y="141" width="104" height="88" fill="#205e5d" stroke="#fff5e4" />
            <path d="M152 152.5a32.5 32.5 0 0 1 0 65" />
            <path
              d="M152 152.5a32.5 32.5 0 0 0 0 65"
              stroke="#fff5e4"
              strokeDasharray="4 5"
              opacity=".65"
            />
            <path d="M76 162.5a22.5 22.5 0 0 1 0 45" stroke="#fff5e4" />
            <path d="M83 141v-5m20 5v-5m20 5v-5m-40 93v5m20-5v5m20-5v5" />
            <path d="M68 168v34" stroke="#fff5e4" strokeWidth="4" />
            <path d="M68 185h4" stroke="#fff5e4" />
            <circle cx="77" cy="185" r="5" stroke="#ffc17d" strokeWidth="2.5" />
          </g>
        ))}
      </g>
    </g>
  );
}
