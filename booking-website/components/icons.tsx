export function Icon({
  name,
  size = 20,
}: {
  name:
    | "calendar"
    | "people"
    | "clock"
    | "arrow"
    | "check"
    | "back"
    | "pin"
    | "phone"
    | "copy"
    | "print"
    | "chevron";
  size?: number;
}) {
  const paths = {
    calendar: (
      <>
        <rect x="3" y="5" width="18" height="16" rx="3" />
        <path d="M7 3v4m10-4v4M3 11h18M8 15h.01M12 15h.01M16 15h.01M8 18h.01M12 18h.01" />
      </>
    ),
    people: (
      <>
        <circle cx="10" cy="7" r="4" />
        <path d="M2 21v-3a7 7 0 0 1 14 0v3M17 4a4 4 0 0 1 0 7m2 3a7 7 0 0 1 3 5v2" />
      </>
    ),
    clock: (
      <>
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7v6h5" />
      </>
    ),
    arrow: <path d="M4 12h16m-6-6 6 6-6 6" />,
    check: <path d="m5 12 4 4L19 6" />,
    back: <path d="M20 12H4m6-6-6 6 6 6" />,
    pin: (
      <>
        <path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z" />
        <circle cx="12" cy="10" r="2.5" />
      </>
    ),
    phone: (
      <path d="m6 3 3 5-2 3c2 3 3 4 6 6l3-2 5 3c-1 4-4 5-7 3C7 18 3 13 2 7c0-3 1-4 4-4Z" />
    ),
    copy: (
      <>
        <rect x="8" y="8" width="12" height="13" rx="2" />
        <path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h3" />
      </>
    ),
    print: (
      <>
        <path d="M7 8V3h10v5M7 17H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-3" />
        <path d="M7 14h10v7H7zM18 11h.01" />
      </>
    ),
    chevron: <path d="m9 5 7 7-7 7" />,
  };
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name]}
    </svg>
  );
}
