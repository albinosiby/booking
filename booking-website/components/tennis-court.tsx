export function TennisCourt() {
  return (
    <g>
      <rect x="10" y="10" width="580" height="340" rx="14" fill="#287b70" />
      <rect x="48" y="66" width="504" height="233" fill="#276e94" />
      <path d="M48 95h504v175H48z" fill="#347fa0" />
      <path d="M165 95h270v175H165z" fill="#3e88a6" />
      <g stroke="#f2faf6" strokeWidth="2.5" fill="none">
        <rect x="48" y="66" width="504" height="233" />
        <path d="M48 95h504M48 270h504M165 95v175m270-175v175M165 182.5h270" />
        <path d="M48 182.5h7m490 0h7" />
      </g>
      <path d="M300 61v244" stroke="#143f50" strokeWidth="9" />
      <path
        d="M300 61v244"
        stroke="#d6ece8"
        strokeWidth="3"
        strokeDasharray="2 3"
      />
      <path d="M297 61v244" stroke="#f2faf6" strokeWidth="1.5" />
      <g fill="#f2e0b5" stroke="#143f50" strokeWidth="2">
        <circle cx="300" cy="60" r="4" />
        <circle cx="300" cy="305" r="4" />
      </g>
    </g>
  );
}
