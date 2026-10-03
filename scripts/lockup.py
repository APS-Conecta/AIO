#!/usr/bin/env python3
"""The wizard's banner lockup as outlines — rewrites the wordmark of php/public/img/logo.svg.

Why paths: the templates draw the lockup by <use href="img/logo.svg#wordmark">. A <use> clone does
not carry the external SVG's own @font-face, so live <text> falls back to whatever the page can
load (FINDINGS R20). Outlines need no font at all.

Authoring tool, run by hand when the lockup's words or the brand fonts change (OSS: fontTools).
The fonts are gestion's full variable brand fonts — the wizard ships only subsets:

    python3 scripts/lockup.py .aps-replay-tree/php/public/img/logo.svg \\
        --fonts /opt/aps-conecta-org/gestion/themes/apsconecta/core/fonts
"""

import argparse
import hashlib
import pathlib
import re

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

# One row per line of the wordmark: text, font file, pinned axes, size, letter-spacing, centre x,
# baseline y, fill — the same geometry the live-text lockup had (patch 070's logo.svg).
LINES = (
    (
        "APS Conecta",
        "Fraunces.woff2",
        {"wght": 600, "opsz": 21, "SOFT": 0, "WONK": 1},
        21.0,
        0.0,
        71.0,
        84.0,
        "#5315a8",
    ),
    (
        "GESTIÓN AIO",
        "NunitoSans.woff2",
        {"wght": 700, "wdth": 100, "opsz": 10.5, "YTLC": 500},
        10.5,
        1.6,
        71.0,
        96.5,
        "#485363",
    ),
)


def pair_kerning(font):
    """{(left, right): xAdvance} from the GPOS 'kern' feature (PairPos formats 1 and 2)."""
    kern = {}
    if "GPOS" not in font:
        return kern
    gpos = font["GPOS"].table
    idx = {
        i
        for fr in gpos.FeatureList.FeatureRecord
        if fr.FeatureTag == "kern"
        for i in fr.Feature.LookupListIndex
    }
    for i in sorted(idx):
        lookup = gpos.LookupList.Lookup[i]
        subs = lookup.SubTable
        if lookup.LookupType == 9:
            subs = [s.ExtSubTable for s in subs]
        for st in subs:
            if getattr(st, "LookupType", 2) != 2:
                continue
            firsts = st.Coverage.glyphs
            if st.Format == 1:
                for g1, ps in zip(firsts, st.PairSet):
                    for rec in ps.PairValueRecord:
                        v = rec.Value1
                        if v is not None and getattr(v, "XAdvance", 0):
                            kern.setdefault((g1, rec.SecondGlyph), v.XAdvance)
            elif st.Format == 2:
                c1, c2 = st.ClassDef1.classDefs, st.ClassDef2.classDefs
                for g1 in firsts:
                    row = st.Class1Record[c1.get(g1, 0)]
                    for g2, k2 in list(c2.items()):
                        v = row.Class2Record[k2].Value1
                        if v is not None and getattr(v, "XAdvance", 0):
                            kern.setdefault((g1, g2), v.XAdvance)
    return kern


def line_path(fontfile, axes, text, size, spacing, cx, baseline):
    font = instantiateVariableFont(TTFont(fontfile), axes, inplace=False)
    upem = font["head"].unitsPerEm
    cmap, hmtx, glyphs = font.getBestCmap(), font["hmtx"], font.getGlyphSet()
    kern = pair_kerning(font)
    names = [cmap[ord(c)] for c in text]
    scale = size / upem
    xs, x = [], 0.0
    for i, g in enumerate(names):
        xs.append(x)
        x += hmtx[g][0] * scale + spacing
        if i + 1 < len(names):
            x += kern.get((g, names[i + 1]), 0) * scale
    width = (
        x - spacing
    )  # letter-spacing trails the last glyph in CSS; centre without it
    left = cx - width / 2
    pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.2f}".rstrip("0").rstrip("."))
    for g, gx in zip(names, xs):
        glyphs[g].draw(TransformPen(pen, (scale, 0, 0, -scale, left + gx, baseline)))
    return pen.getCommands(), width


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("svg", type=pathlib.Path)
    ap.add_argument("--fonts", type=pathlib.Path, required=True)
    a = ap.parse_args()
    svg = a.svg.read_text(encoding="utf-8")
    paths = []
    for text, ff, axes, size, spacing, cx, base, fill in LINES:
        d, width = line_path(a.fonts / ff, axes, text, size, spacing, cx, base)
        assert width < 138, (
            f"{text!r} is {width:.1f} wide — it no longer fits the 142-unit viewBox"
        )
        paths.append(
            f'    <path aria-hidden="true" fill="{fill}" d="{d}"></path>  <!-- {text} -->'
        )
        print(f"  {text}: {width:.1f} units wide")
    word = '  <g id="wordmark">\n' + "\n".join(paths) + "\n  </g>\n"
    svg, n = re.subn(r'  <g id="wordmark">\n.*?\n  </g>\n', word, svg, flags=re.S)
    assert n == 1, "no single wordmark group in the svg"
    svg = re.sub(
        r"\s*<style>.*?</style>", "", svg, flags=re.S
    )  # the embedded fonts are dead bytes now
    svg, n = re.subn(
        r'aria-label="[^"]*"', 'aria-label="APS Conecta Gestión AIO"', svg, count=1
    )
    assert n == 1
    old = (
        "The wordmark is live text over embedded\n       OFL subsets of the same fonts the page ships (the house lockup pattern, gestion\n"
        "       logo.svg) so this file never fetches anything and never depends on page fonts."
    )
    assert svg.count(old) == 1, (
        "070's lockup comment drifted — update this tool's comment rewrite"
    )
    sums = ", ".join(
        f"{ff} sha256 {hashlib.sha256((a.fonts / ff).read_bytes()).hexdigest()[:16]}"
        for ff in sorted({line[1] for line in LINES})
    )
    svg = svg.replace(
        old,
        "The wordmark is outlines (scripts/lockup.py,\n       from gestion's brand fonts): a <use> clone cannot carry fonts embedded in this file, so live\n"
        "       text fell back to whatever the page loaded (R20). Outlines need no font at all.\n"
        f"       Drawn from {sums}.",
    )
    a.svg.write_text(svg, encoding="utf-8")


if __name__ == "__main__":
    main()
