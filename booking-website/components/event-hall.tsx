export function EventHall() {
  return (
    <g>
      <rect x="10" y="10" width="580" height="340" rx="14" fill="#e5ece6" />
      <rect
        x="36"
        y="54"
        width="528"
        height="270"
        rx="10"
        fill="#f5f0e6"
        stroke="#a9bfb5"
        strokeWidth="2"
      />
      <rect x="276" y="122" width="48" height="182" rx="8" fill="#fffdf8" />
      <rect x="147" y="84" width="306" height="24" rx="3" fill="#b5c8bf" />
      <path d="M147 92h18m-18 8h18m270-8h18m-18 8h18" stroke="#f5f0e6" strokeWidth="2" />
      <rect x="165" y="66" width="270" height="54" rx="7" fill="#214f57" />
      <path d="M177 111h246" stroke="#e1c99c" strokeWidth="2" />
      <text
        x="300"
        y="98"
        textAnchor="middle"
        fill="#f8f3e5"
        fontSize="13"
        fontWeight="600"
        letterSpacing="4"
      >
        STAGE
      </text>
      {[150, 450].flatMap((x) =>
        [175, 268].map((y) => (
          <g key={`${x}-${y}`} transform={`translate(${x} ${y})`}>
            {Array.from({ length: 8 }, (_, index) => (
              <rect
                key={index}
                x="-6"
                y="-44"
                width="12"
                height="9"
                rx="3"
                transform={`rotate(${index * 45})`}
                fill="#74988c"
                stroke="#5e8278"
                strokeWidth="1"
              />
            ))}
            <circle r="30" fill="#fffdf8" stroke="#c9b99b" strokeWidth="2" />
            <circle r="24" fill="none" stroke="#e9decb" strokeWidth="1" />
            <circle r="8" fill="#cddcce" />
            <path d="M-4 2q-3-9 4-7 7-2 4 7-4 6-8 0" fill="#5c8d77" />
          </g>
        )),
      )}
      {[65, 535].flatMap((x) =>
        [82, 292].map((y) => (
          <g key={`${x}-${y}`} transform={`translate(${x} ${y})`}>
            <circle r="12" fill="#d1dbce" />
            <path d="M0 9C-19-1-8-15 0-4 8-15 19-1 0 9Z" fill="#5b8b74" />
          </g>
        )),
      )}
      <rect x="253" y="307" width="94" height="19" rx="4" fill="#e5ece6" />
      <text x="300" y="320" textAnchor="middle" fill="#47675e" fontSize="9" fontWeight="650" letterSpacing="1.5">
        ENTRANCE
      </text>
    </g>
  );
}
