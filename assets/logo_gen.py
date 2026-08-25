"""Illusory mark: spokes running inward from a rim, stopping at a vesica aperture.

The aperture is the intersection of two circles of radius `Rl` centred at (+/-d, 0),
so a smaller half-width (Rl - d) carves a narrower lens and thickens the side bands.
`twist` offsets each spoke's inner endpoint, producing the two bright flares.
"""
import math

def mark(N=150, lens_w=100, lens_h=264, twist=25, R=250, sw=3.2, size=560,
         stroke="#fff", bg="#000"):
    """lens_w / lens_h are the full width and height of the aperture, in viewBox units."""
    c, tw = size / 2, math.radians(twist)
    w, h = lens_w / 2, lens_h / 2
    Rl = (w + h * h / w) / 2      # circle radius giving that vesica
    d = (h * h / w - w) / 2       # and its centre offset

    def r_lens(p):
        disc = d * d * math.cos(p) ** 2 - d * d + Rl * Rl
        return -d * abs(math.cos(p)) + math.sqrt(max(disc, 0))

    lines = []
    for i in range(N):
        t = 2 * math.pi * i / N
        p = t + tw
        rl = r_lens(p)
        lines.append(
            f'<line x1="{c + R * math.cos(t):.1f}" y1="{c + R * math.sin(t):.1f}"'
            f' x2="{c + rl * math.cos(p):.1f}" y2="{c + rl * math.sin(p):.1f}"/>'
        )
    rect = f'<rect width="{size}" height="{size}" fill="{bg}"/>' if bg else ""
    return (f'<svg viewBox="0 0 {size} {size}" xmlns="http://www.w3.org/2000/svg">'
            f'{rect}<g stroke="{stroke}" stroke-width="{sw}">' + "".join(lines) + "</g></svg>")


# Locked parameters for the Illusory mark.
PRIMARY = dict(N=130, lens_w=120, lens_h=280, sw=1.8, twist=25)
# Menu-bar / favicon constants. The target is 18pt at @2x (~36px), not 16px:
# above ~28 spokes the mark collapses into a grey blob at that size.
SMALL = dict(N=28, lens_w=120, lens_h=280, sw=12, twist=25)

if __name__ == "__main__":
    import pathlib
    out = pathlib.Path(__file__).parent
    for name, kw in [
        ("illusory-mark.svg", PRIMARY),
        ("illusory-mark-small.svg", SMALL),
        ("illusory-mark-mono.svg", dict(PRIMARY, stroke="currentColor", bg=None)),
        ("favicon.svg", dict(SMALL, bg=None, stroke="currentColor")),
    ]:
        (out / name).write_text(mark(**kw))
        print("wrote", name)
