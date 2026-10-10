"""Builds the orthea.ai Consult / Voice logos (direction B1: inline, italic descriptor after a
hairline) as SVGs with the text converted to outlines, so they need no fonts.
Fonts: Fraunces (SIL Open Font License), from github.com/google/fonts/ofl/fraunces.
Usage: python3 brand/build_logos.py <fonts dir> <out dir>"""
import sys, io, os
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

FONTS, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)

def instance(path, **axes):
    f = TTFont(path)
    inst = instantiateVariableFont(f, {"SOFT": 0, "WONK": 0, **axes})
    buf = io.BytesIO(); inst.save(buf)
    data = buf.getvalue()
    return TTFont(io.BytesIO(data)), hb.Font(hb.Face(data))

ROMAN = instance(f"{FONTS}/Fraunces.ttf", opsz=144, wght=500)
ITAL = instance(f"{FONTS}/Fraunces-Italic.ttf", opsz=72, wght=400)

def run(font, text, size, x, baseline, tracking=0.0):
    """Shape text; return (svg path data, advance width, ink bounds)."""
    tt, hbf = font
    upm = tt["head"].unitsPerEm
    buf = hb.Buffer(); buf.add_str(text); buf.guess_segment_properties()
    hb.shape(hbf, buf, {"kern": True, "liga": True})
    gs = tt.getGlyphSet(); order = tt.getGlyphOrder()
    s = size / upm
    pen = SVGPathPen(gs); bp = BoundsPen(gs)
    pen_x = x
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        name = order[info.codepoint]
        t = (s, 0, 0, -s, pen_x + pos.x_offset * s, baseline - pos.y_offset * s)
        gs[name].draw(TransformPen(pen, t)); gs[name].draw(TransformPen(bp, t))
        pen_x += pos.x_advance * s + tracking * size
    if text and tracking: pen_x -= tracking * size
    return pen.getCommands(), pen_x - x, bp.bounds

def line_box_baseline(font, size):
    """Where CSS puts the baseline inside a line-height:1 box of this font size."""
    tt, _ = font
    upm = tt["head"].unitsPerEm
    os2 = tt["OS/2"]
    if os2.fsSelection & (1 << 7):
        asc, desc = os2.sTypoAscender, -os2.sTypoDescender
    else:
        asc, desc = tt["hhea"].ascent, -tt["hhea"].descent
    return (size - (asc + desc) * size / upm) / 2 + asc * size / upm

def logo(name, word, ink, accent, rule, rule_opacity=1.0):
    W, A, D = 84, 42, 52                     # wordmark, ".ai", descriptor sizes (px)
    base = line_box_baseline(ROMAN, W)        # wordmark baseline inside its 84 px box
    p1, w1, b1 = run(ROMAN, "orthea", W, 0, base, tracking=-0.025)
    p2, w2, b2 = run(ROMAN, ".", W, w1 - 0.025 * W, base)
    p3, w3, b3 = run(ROMAN, "ai", A, w1 - 0.025 * W + w2, base)
    x = w1 - 0.025 * W + w2 + w3 + 28
    rx = x; x += 1.5 + 28
    dbase = (W - D) / 2 + line_box_baseline(ITAL, D)   # centred like the canvas design
    p4, w4, b4 = run(ITAL, word, D, x, dbase)
    xs = [b[0] for b in (b1, b2, b3, b4)] + [b[2] for b in (b1, b2, b3, b4)]
    ys = [b[1] for b in (b1, b2, b3, b4)] + [b[3] for b in (b1, b2, b3, b4)]
    rule_top, rule_h = (W - 64) / 2, 64
    pad = 6
    x0, x1 = min(xs) - pad, max(xs) + pad
    y0, y1 = min(min(ys), rule_top) - pad, max(max(ys), rule_top + rule_h) + pad
    w, h = x1 - x0, y1 - y0
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0:.2f} {y0:.2f} {w:.2f} {h:.2f}" '
           f'width="{w:.0f}" height="{h:.0f}" role="img" aria-label="orthea.ai {word}">'
           f'<path fill="{ink}" d="{p1}"/>'
           f'<path fill="{accent}" d="{p2}{p3}"/>'
           f'<rect x="{rx:.2f}" y="{rule_top:.2f}" width="1.5" height="{rule_h}" fill="{rule}" fill-opacity="{rule_opacity}"/>'
           f'<path fill="{accent}" d="{p4}"/></svg>')
    open(f"{OUT}/{name}.svg", "w").write(svg)
    return w, h

def mark(name, tile, ink, dot, size=512, radius=0.22, with_dot=True):
    """App icon / favicon: 'o.' on a rounded tile."""
    s = size
    fs = s * 0.84
    base = s * 0.70
    po, wo, bo = run(ROMAN, "o", fs, 0, base)
    pd, wd, bd = run(ROMAN, ".", fs, wo, base) if with_dot else ("", 0, bo)
    ink_l, ink_r = bo[0], (bd[2] if with_dot else bo[2])
    shift = (s - (ink_r - ink_l)) / 2 - ink_l
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s} {s}" width="{s}" height="{s}">'
           f'<rect width="{s}" height="{s}" rx="{s*radius:.1f}" fill="{tile}"/>'
           f'<g transform="translate({shift:.2f} 0)"><path fill="{ink}" d="{po}"/>'
           + (f'<path fill="{dot}" d="{pd}"/>' if with_dot else "") + '</g></svg>')
    open(f"{OUT}/{name}.svg", "w").write(svg)

INK, CREAM, RULE = "#1F1D1B", "#F7F3EE", "#CFC6BA"
print(logo("orthea-consult", "Consult", INK, "#446B63", RULE))
print(logo("orthea-voice", "Voice", INK, "#A8603C", RULE))
logo("orthea-consult-reversed", "Consult", CREAM, "#A9C7BE", CREAM, 0.35)
logo("orthea-voice-reversed", "Voice", CREAM, "#E7B597", CREAM, 0.35)
mark("consult-icon", "#2F4A43", CREAM, "#A9C7BE")
mark("voice-icon", "#8E4E2F", CREAM, "#F2C9AE")
mark("consult-favicon", "#2F4A43", CREAM, "", with_dot=False)
mark("voice-favicon", "#8E4E2F", CREAM, "", with_dot=False)
