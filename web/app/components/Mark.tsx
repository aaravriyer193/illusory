/**
 * The Illusory mark, generated from the same vesica formula as
 * assets/logo_gen.py and IllusoryMark.swift — so the site, the app and the
 * exported SVGs cannot drift apart.
 */

const DESIGN = 560;
const RIM = 250;

function spokePath(
  count: number,
  lensW: number,
  lensH: number,
  twist: number,
) {
  const c = DESIGN / 2;
  const w = lensW / 2;
  const h = lensH / 2;
  const Rl = (w + (h * h) / w) / 2;
  const d = ((h * h) / w - w) / 2;
  const tw = (twist * Math.PI) / 180;

  const lensRadius = (p: number) => {
    const disc = d * d * Math.cos(p) ** 2 - d * d + Rl * Rl;
    return -d * Math.abs(Math.cos(p)) + Math.sqrt(Math.max(disc, 0));
  };

  const lines: string[] = [];
  for (let i = 0; i < count; i++) {
    const t = (2 * Math.PI * i) / count;
    const p = t + tw;
    const rl = lensRadius(p);
    lines.push(
      `M${(c + RIM * Math.cos(t)).toFixed(1)} ${(c + RIM * Math.sin(t)).toFixed(1)}` +
        `L${(c + rl * Math.cos(p)).toFixed(1)} ${(c + rl * Math.sin(p)).toFixed(1)}`,
    );
  }
  return lines.join("");
}

export function Mark({
  size = 104,
  spokes = 130,
  strokeWidth = 1.8,
}: {
  size?: number;
  spokes?: number;
  strokeWidth?: number;
}) {
  return (
    <svg
      viewBox={`0 0 ${DESIGN} ${DESIGN}`}
      width={size}
      height={size}
      aria-hidden="true"
    >
      <path
        d={spokePath(spokes, 120, 280, 25)}
        stroke="currentColor"
        strokeWidth={strokeWidth}
        fill="none"
      />
    </svg>
  );
}
