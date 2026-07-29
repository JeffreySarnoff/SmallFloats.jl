#!/usr/bin/env python3
"""validate.py — Stage 5 of docs/pdf/howto.md (the automated battery).

Usage: validate.py <build-dir> <pdf> [<previous-manifest.json>]

Renders every page once, runs the automatable checks, and prints a findings
report; exits nonzero if any hard finding survives. Mapping to howto.md's
Stage 5 checks:

  1  split paragraphs      — primary proof is Stage 4's Overfull \\vbox = 0
                             gate (buildpdf.sh); line-boundary eyeballing
                             stays manual per howto.
  2  stranded headings     — automated here two ways: bold sectioning-head
                             last lines (font-calibrated) and docstring
                             headers ("name – Kind." as a page's last line).
  3  split blocks          — code-background band touching both sides of a
                             page boundary (render pixel scan).
  4  rule-4 placement      — manual (needs heading-vs-subsection geometry
                             judgment); flagged pages surface via check 9.
  5  blank pages           — automated.
  6  margins               — automated (text ink; tolerance is the doctrine
                             ~10 pt line: 8 pt past the content edge).
  7  function              — qpdf, text extraction (no U+FFFD), bookmarks,
                             and internal /GoTo link-target resolution.
  8  TOC block integrity   — rule 9, from extracted contents-page text.
  9  page-fill rhythm      — advisory (55% single / 70% run floors).
 10  visual diff           — per-page render hashes vs the previous build's
                             manifest (advisory list of changed pages).
"""
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

DPI = 100
MARGIN_IN = 1.1        # side margins from custom.sty
TOP_IN = 1.15
BOT_IN = 1.0
MARGIN_TOL_PT = 8      # ≤ the doctrine's ~10 pt investigate line (Stage 4)
BAND_GRAY = 245        # codeblock-background gray 0.96 * 255
BAND_TOL = 4
FILL_FLOOR = 0.55      # check 9 doctrine floors
RUN_FLOOR = 0.70
# Font calibration for check 2 (howto.md: sizes as pdfplumber reports them
# under fontspec Scale=MatchLowercase — re-calibrate if fonts change).
BODY_PT = 7.9
HEADING_MIN_PT = 8.8
DOCHEAD_RE = re.compile(r"[–—-]\s*(Module|Function|Method|Type|Constant|Macro)\.\s*$")


def main():
    build = sys.argv[1]
    pdf = sys.argv[2]
    prev_manifest = sys.argv[3] if len(sys.argv) > 3 else None
    findings, advisories = [], []

    pages_dir = os.path.join(build, "pages")
    render(pdf, pages_dir)
    pngs = sorted(glob.glob(os.path.join(pages_dir, "p-*.png")))

    check_function(pdf, findings)                      # check 7
    toc_pages, fills = scan_text(pdf, findings)        # checks 2, 5, 6, 8, 9
    findings += check_toc_rule9(toc_pages)
    findings += check_band_crossings(pngs)             # check 3
    findings += check_tables_with_headings(            # check 3, kept units
        pdf, build, {p for p, _ in toc_pages})
    advisories += check_page_fill(fills)               # check 9
    advisories += check_visual_diff(pngs, build, prev_manifest)   # check 10

    for a in advisories:
        print("  advisory:", a)
    if findings:
        print(f"validate.py: {len(findings)} finding(s):")
        for f in findings:
            print("  -", f)
        sys.exit(1)
    print(f"validate.py: all checks clean over {len(pngs)} pages"
          + (f" ({len(advisories)} advisories)" if advisories else ""))


def render(pdf, pages_dir):
    """One render pass at DPI, shared by checks 3 and 10 (and archived as the
    build artifact howto.md check 10 requires)."""
    os.makedirs(pages_dir, exist_ok=True)
    for f in glob.glob(os.path.join(pages_dir, "p-*.png")):
        os.remove(f)
    subprocess.run(["pdftoppm", "-png", "-r", str(DPI), pdf,
                    os.path.join(pages_dir, "p")], check=True)


def check_function(pdf, findings):
    """Check 7: qpdf, extraction, bookmarks, internal link targets."""
    r = subprocess.run(["qpdf", "--check", pdf], capture_output=True, text=True)
    if r.returncode != 0:
        findings.append(f"qpdf --check failed:\n{r.stdout[-500:]}")
    from pypdf import PdfReader
    reader = PdfReader(pdf)
    for i, page in enumerate(reader.pages):
        if "�" in (page.extract_text() or ""):
            findings.append(f"page {i+1}: U+FFFD in extracted text")
    if not reader.outline:
        findings.append("no bookmarks/outline present")
    dests = set(reader.named_destinations)
    for i, page in enumerate(reader.pages):
        for annot in page.get("/Annots") or []:
            obj = annot.get_object()
            if obj.get("/Subtype") != "/Link":
                continue
            target = obj.get("/Dest")
            if target is None and "/A" in obj:
                act = obj["/A"].get_object()
                if act.get("/S") == "/GoTo":
                    target = act.get("/D")
            if isinstance(target, str) and target not in dests:
                findings.append(f"page {i+1}: internal link to missing "
                                f"destination {target!r}")


def scan_text(pdf, findings):
    """One pdfplumber pass: blank pages (5), margin ink (6), stranded
    headings (2), TOC capture (8), and fill fractions (9)."""
    import pdfplumber
    toc_pages, fills = [], []
    with pdfplumber.open(pdf) as doc:
        for i, page in enumerate(doc.pages):
            txt = page.extract_text() or ""
            chars = page.chars
            top, bot = TOP_IN * 72, page.height - BOT_IN * 72

            if i >= 3 and len(chars) < 8:                       # check 5
                findings.append(f"page {i+1}: nearly blank ({len(chars)} chars)")

            limit = page.width - MARGIN_IN * 72 + MARGIN_TOL_PT  # check 6
            worst = max((c["x1"] for c in chars), default=0)
            if worst > limit:
                findings.append(f"page {i+1}: text ink at {worst:.1f}pt "
                                f"exceeds margin limit {limit:.1f}pt")

            objs = chars + page.rects + page.lines                # check 9
            lowest = max((o["bottom"] for o in objs), default=top)
            fills.append(min(1.0, (min(lowest, bot) - top) / (bot - top)))

            first = txt.strip().split("\n")[0].strip() if txt.strip() else ""
            if first == "Contents" or (toc_pages and _is_toc_cont(txt)):
                toc_pages.append((i, txt))                        # check 8

            # check 2: stranded headings as a page's LAST content line —
            # (a) docstring header text, (b) bold sectioning-head fonts.
            lines = [l for l in txt.strip().split("\n") if l.strip()]
            last = lines[-1].strip() if lines else ""
            if last and DOCHEAD_RE.search(last) and i + 1 < len(doc.pages):
                findings.append(f"page {i+1}: last line is a docstring "
                                f"header ({last[:60]!r}) — body stranded")
            if chars and i + 1 < len(doc.pages):
                lowline = max(c["top"] for c in chars)
                lc = [c for c in chars if abs(c["top"] - lowline) < 2]
                bold = sum("Bold" in c.get("fontname", "") for c in lc)
                size = max(c["size"] for c in lc)
                if lc and bold > len(lc) * 0.8 and size >= HEADING_MIN_PT:
                    findings.append(
                        f"page {i+1}: last line is heading-styled "
                        f"({size:.1f}pt bold) — stranded heading (check 2); "
                        "verify against the render (calibration: body "
                        f"≈ {BODY_PT}pt)")
    return toc_pages, fills


def _is_toc_cont(txt):
    first = txt.strip().split("\n")[0] if txt.strip() else ""
    return bool(re.match(r"^\d+(\.\d+)?\s+\S", first))


CHAP_RE = re.compile(r"^\d+\s+\S")        # "3  User Guide ..... 17"
SECT_RE = re.compile(r"^\d+\.\d+\s+\S")   # "3.2  Projections ... 19"


def check_toc_rule9(toc_pages):
    """Check 8 / rule 9: a chapter TOC entry keeps its subentry block."""
    out = []
    for k, (pageno, txt) in enumerate(toc_pages):
        lines = [l.strip() for l in txt.strip().split("\n") if l.strip()]
        if not lines:
            continue
        if CHAP_RE.match(lines[-1]) and not SECT_RE.match(lines[-1]):
            out.append(f"TOC page {pageno+1}: ends with a chapter entry "
                       f"({lines[-1][:60]!r}) — subentries stranded (rule 9)")
        if k > 0 and SECT_RE.match(lines[0]):
            out.append(f"TOC page {pageno+1}: begins mid-block with a section "
                       f"entry ({lines[0][:60]!r}) — split block (rule 9)")
    return out


def check_band_crossings(pngs):
    """Check 3: no code-background band touching the bottom content edge of
    page n and the top content edge of page n+1."""
    from PIL import Image
    out, edges = [], []
    for p in pngs:
        im = Image.open(p).convert("L")
        w, h = im.size
        x0, x1 = int(MARGIN_IN * DPI), w - int(MARGIN_IN * DPI)
        top, bot = int(TOP_IN * DPI), h - int(BOT_IN * DPI)
        px = im.load()

        def band(y):
            row = [px[x, y] for x in range(x0, x1, 4)]
            n = sum(1 for v in row if abs(v - BAND_GRAY) <= BAND_TOL)
            return n > len(row) * 0.5

        edges.append((any(band(y) for y in range(top, top + 6)),
                      any(band(y) for y in range(bot - 6, bot))))
    for i in range(len(edges) - 1):
        if edges[i][1] and edges[i + 1][0]:
            out.append(f"pages {i+1}->{i+2}: code background band touches "
                       "both sides of the page boundary — check the source: "
                       "one split block is a violation; adjacent blocks are "
                       "a legal break")
    return out


def _norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def check_tables_with_headings(pdf, build, toc_pageset):
    """Check 3 extension: every heading the transform promised to keep with
    its table (survey.json kept_unit_headings) must render on the same page
    as a table (detected by wide horizontal rules below the heading line)."""
    import pdfplumber
    spath = os.path.join(build, "survey.json")
    if not os.path.exists(spath):
        return []
    titles = json.load(open(spath)).get("kept_unit_headings", [])
    if not titles:
        return []
    want = {_norm(t): t for t in titles if _norm(t)}
    satisfied, seen = set(), set()
    with pdfplumber.open(pdf) as doc:
        for i, page in enumerate(doc.pages):
            if i in toc_pageset:
                continue
            # tabulary rules are thin horizontal marks at least ~1in wide —
            # absolute floor, not a page fraction: narrow tables (few short
            # columns) have narrow rules. Header/footer rules sit above the
            # content top, so the below-the-heading test excludes them.
            rules = [o["top"] for o in list(page.rects) + list(page.lines)
                     if (o["x1"] - o["x0"]) > 72
                     and (o["bottom"] - o["top"]) < 3]
            for line in page.extract_text_lines():
                ln = _norm(line["text"])
                for key in want:
                    if key in ln and len(ln) < len(key) + 12:   # heading, not prose
                        seen.add(key)
                        if any(r > line["top"] for r in rules):
                            satisfied.add(key)
    out = []
    for key, title in want.items():
        if key not in seen:
            out.append(f"kept-unit heading {title!r} not found in the PDF "
                       "text — same-page check could not run")
        elif key not in satisfied:
            out.append(f"heading {title!r}: transform promised its table on "
                       "the same page, but no table renders below it "
                       "(rule 3 keep-together failed)")
    return out


def check_page_fill(fills):
    """Check 9 (advisory): page-fill rhythm, doctrine floors 55% / 70%."""
    out = []
    for i, f in enumerate(fills[3:], start=4):     # skip front matter
        if f < FILL_FLOOR:
            out.append(f"page {i}: {f:.0%} full — below the {FILL_FLOOR:.0%} "
                       "floor (chapter-final pages are fine; others: "
                       "remediate at source level or accept in the build note)")
    for i in range(4, len(fills)):
        if fills[i - 1] < RUN_FLOOR and fills[i] < RUN_FLOOR:
            out.append(f"pages {i}-{i+1}: consecutive pages below "
                       f"{RUN_FLOOR:.0%} ({fills[i-1]:.0%}, {fills[i]:.0%})")
    return out


def check_visual_diff(pngs, build, prev_manifest):
    """Check 10 (advisory): render-hash manifest vs the previous build —
    eyeball only the pages listed as changed."""
    manifest = {os.path.basename(p): hashlib.md5(open(p, "rb").read()).hexdigest()
                for p in pngs}
    json.dump(manifest, open(os.path.join(build, "render_manifest.json"), "w"),
              indent=0)
    if not prev_manifest or not os.path.exists(prev_manifest):
        return ["no previous render manifest — first build: do the "
                "fixed-checklist eyeball pass (chapter openings, TOC pages, "
                "densest table page, longest code page)"]
    prev = json.load(open(prev_manifest))
    changed = sorted(k for k in manifest if prev.get(k) != manifest.get(k))
    dropped = sorted(k for k in prev if k not in manifest)
    out = []
    if len(prev) != len(manifest):
        out.append(f"page count changed: {len(prev)} -> {len(manifest)}")
    if changed or dropped:
        out.append(f"visual diff: {len(changed)} changed page(s) to eyeball: "
                   + ", ".join(changed[:12])
                   + (" …" if len(changed) > 12 else ""))
    else:
        out.append("visual diff: no page changed since the previous build")
    return out


if __name__ == "__main__":
    main()
