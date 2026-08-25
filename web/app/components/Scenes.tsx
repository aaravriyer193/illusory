/**
 * Illustrations for each use case, drawn rather than screenshotted — they stay
 * sharp at any size, weigh nothing, and can animate the one moment that matters.
 *
 * The chrome is deliberately close to the real thing: proper traffic lights, a
 * sidebar, column headers. A vague grey rectangle reads as a placeholder; a window
 * you recognise reads as the app you actually use.
 */

const W = 460;
const H = 286;

function Chrome({
  title,
  sidebar,
  children,
}: {
  title: string;
  sidebar?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="scene" role="img" aria-label={title}>
      <defs>
        <linearGradient id="bar" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#2b2b31" />
          <stop offset="1" stopColor="#212127" />
        </linearGradient>
        <clipPath id="win">
          <rect x="0" y="0" width={W} height={H} rx="11" />
        </clipPath>
      </defs>

      <g clipPath="url(#win)">
        <rect width={W} height={H} fill="var(--panel)" />
        {sidebar ? (
          <>
            <rect x="0" y="0" width="118" height={H} fill="#141419" />
            <path d={`M118 0v${H}`} stroke="#000" strokeOpacity="0.5" />
          </>
        ) : null}
        <rect width={W} height="34" fill="url(#bar)" />
        <path d={`M0 34h${W}`} stroke="#000" strokeOpacity="0.55" />

        {/* Traffic lights, in their actual colours. */}
        {[
          ["#ff5f57", 17],
          ["#febc2e", 35],
          ["#28c840", 53],
        ].map(([fill, cx]) => (
          <circle key={cx as number} cx={cx as number} cy="17" r="5.5" fill={fill as string} />
        ))}

        <text x={W / 2} y="21" className="scene-chrome" textAnchor="middle">
          {title}
        </text>
        {sidebar}
        {children}
      </g>
      <rect
        x="0.5"
        y="0.5"
        width={W - 1}
        height={H - 1}
        rx="11"
        fill="none"
        stroke="#ffffff"
        strokeOpacity="0.09"
      />
    </svg>
  );
}

function SidebarItem({ y, label, active }: { y: number; label: string; active?: boolean }) {
  return (
    <g>
      {active ? (
        <rect x="8" y={y - 12} width="102" height="22" rx="6" fill="#ffffff" fillOpacity="0.08" />
      ) : null}
      <circle cx="22" cy={y - 1} r="3.5" fill={active ? "var(--fg)" : "var(--muted)"} opacity="0.8" />
      <text x="34" y={y + 3} className={`scene-text ${active ? "on" : "off"}`} fontSize="11.5">
        {label}
      </text>
    </g>
  );
}

/** Two files already renamed, the rest still carrying the old scheme. */
export function RenameScene() {
  const done = ["2024-06-01-beach.jpg", "2024-06-02-pier.jpg"];
  const todo = ["IMG_4473.jpg", "IMG_4474.jpg", "IMG_4475.jpg"];
  return (
    <Chrome
      title="photos"
      sidebar={
        <>
          <text x="16" y="58" className="scene-label">FAVOURITES</text>
          <SidebarItem y={82} label="Desktop" />
          <SidebarItem y={108} label="Downloads" />
          <SidebarItem y={134} label="photos" active />
          <SidebarItem y={160} label="exports" />
        </>
      }
    >
      <text x="136" y="58" className="scene-label">NAME</text>
      <text x="360" y="58" className="scene-label">DATE</text>
      <path d="M130 66h318" stroke="#ffffff" strokeOpacity="0.07" />

      {done.map((name, i) => (
        <g key={name} className="row-done" style={{ animationDelay: `${i * 0.1}s` }}>
          <rect x="128" y={76 + i * 27} width="320" height="23" rx="5" fill="#ffffff" fillOpacity="0.06" />
          <text x="138" y={92 + i * 27} className="scene-text on">{name}</text>
          <text x="360" y={92 + i * 27} className="scene-text off">just now</text>
        </g>
      ))}

      {todo.map((name, i) => (
        <g key={name} className="row-todo" style={{ animationDelay: `${0.55 + i * 0.13}s` }}>
          <text x="138" y={150 + i * 27} className="scene-text off">{name}</text>
          <text x="272" y={150 + i * 27} className="scene-text arrow">→</text>
          <text x="292" y={150 + i * 27} className="scene-text on">2024-06-0{i + 3}-…</text>
        </g>
      ))}

      <g className="repair-in">
        <rect x="128" y="238" width="196" height="26" rx="13" fill="#ffffff" fillOpacity="0.07" />
        <text x="142" y="255" className="scene-text on" fontSize="11.5">
          renamed 48 files
        </text>
      </g>
    </Chrome>
  );
}

/** A promise typed into a message, then made true. */
export function AttachScene() {
  return (
    <Chrome
      title="Acme — #design"
      sidebar={
        <>
          <text x="16" y="58" className="scene-label">CHANNELS</text>
          <SidebarItem y={82} label="# general" />
          <SidebarItem y={108} label="# design" active />
          <SidebarItem y={134} label="# eng" />
          <SidebarItem y={160} label="# random" />
        </>
      }
    >
      <circle cx="146" cy="70" r="12" fill="#ffffff" fillOpacity="0.12" />
      <text x="168" y="66" className="scene-text on" fontSize="12">you</text>
      <text x="196" y="66" className="scene-label">2:41 PM</text>
      <text x="168" y="86" className="scene-text on">Here’s the new mark — logo’s attached</text>

      <g className="attach-pop">
        <rect x="168" y="100" width="212" height="58" rx="9" fill="#ffffff" fillOpacity="0.06" />
        <rect x="180" y="112" width="34" height="34" rx="7" fill="#0b0b0e" stroke="#ffffff" strokeOpacity="0.16" />
        <path d="M188 138l7-9 5 6 4-4 6 7" fill="none" stroke="var(--fg)" strokeWidth="1.4"
              strokeLinecap="round" strokeLinejoin="round" />
        <text x="224" y="126" className="scene-text on" fontSize="12">illusory-mark.svg</text>
        <text x="224" y="143" className="scene-text off" fontSize="11">6.7 KB · attached</text>
      </g>

      <rect x="132" y="230" width="312" height="34" rx="9" fill="#ffffff" fillOpacity="0.04"
            stroke="#ffffff" strokeOpacity="0.09" />
      <text x="146" y="251" className="scene-text off" fontSize="11.5">Message #design</text>
    </Chrome>
  );
}

/** A pasted mess resolving into columns. */
export function TableScene() {
  const rows = [
    ["Q1", "148,200", "+12%"],
    ["Q2", "163,400", "+10%"],
    ["Q3", "191,050", "+17%"],
  ];
  return (
    <Chrome title="Untitled — Numbers">
      <text x="24" y="60" className="scene-text off mono">
        q1,148200,+12% q2,163400,+10% q3,191050…
      </text>

      <g className="table-in">
        {["QUARTER", "REVENUE", "GROWTH"].map((head, i) => (
          <g key={head}>
            <rect x={22 + i * 140} y="82" width="136" height="26" fill="#ffffff" fillOpacity="0.05" />
            <text x={34 + i * 140} y="99" className="scene-label">{head}</text>
          </g>
        ))}
        {rows.map((row, r) => (
          <g key={row[0]} className="table-row" style={{ animationDelay: `${0.3 + r * 0.1}s` }}>
            {row.map((cell, i) => (
              <g key={i}>
                <rect x={22 + i * 140} y={108 + r * 30} width="136" height="30"
                      fill="none" stroke="#ffffff" strokeOpacity="0.06" />
                <text x={34 + i * 140} y={128 + r * 30}
                      className={`scene-text ${i === 0 ? "on" : "off"} mono`}>{cell}</text>
              </g>
            ))}
          </g>
        ))}
      </g>
    </Chrome>
  );
}

/** It reacts when a step fails instead of stopping. */
export function RepairScene() {
  return (
    <Chrome title="zsh — illusory">
      <text x="24" y="64" className="scene-text mono"><tspan className="prompt">➜</tspan> mv IMG_*.jpg ./sorted/</text>
      <text x="24" y="88" className="scene-text fail mono">mv: ./sorted: No such file or directory</text>

      <g className="repair-in">
        <rect x="20" y="104" width="250" height="26" rx="13" fill="#ffffff" fillOpacity="0.06" />
        <text x="34" y="121" className="scene-text off" fontSize="11.5">
          that didn’t work — trying another way
        </text>
        <text x="24" y="158" className="scene-text mono"><tspan className="prompt">➜</tspan> mkdir -p ./sorted</text>
        <text x="24" y="182" className="scene-text mono"><tspan className="prompt">➜</tspan> mv IMG_*.jpg ./sorted/</text>
        <text x="24" y="212" className="scene-text ok mono">✓ moved 48 files</text>
      </g>
    </Chrome>
  );
}

export const useCases = [
  {
    title: "Finish the rename",
    body: "You renamed two files by date. Illusory spots the pattern in what just changed on disk, and the other forty-eight follow.",
    Scene: RenameScene,
  },
  {
    title: "Keep the promise",
    body: "You typed that the logo is attached. It wasn’t. Illusory treats what you wrote as a promise and makes it true.",
    Scene: AttachScene,
  },
  {
    title: "Make the mess a table",
    body: "Paste something shapeless and press the key. Columns, headers, alignment — without describing any of it.",
    Scene: TableScene,
  },
  {
    title: "It reacts when things break",
    body: "A step fails. Illusory reads the actual error, works out what was missing, and tries again instead of giving up.",
    Scene: RepairScene,
  },
];
