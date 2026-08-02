#!/usr/bin/env python3
"""transform.py — Stages 2 (survey) + 3 (transform) of docs/pdf/howto.md.

Usage: transform.py <resolved-dir> <out-dir>

Reads the Documenter-resolved .tex from <resolved-dir> (docs/build_latex),
surveys it, applies the conditional transform pass, and writes
<out-dir>/{main.tex, custom.sty, documenter.sty, preamble.tex, survey.json}.
Every substitution asserts its match count against the survey; a pattern that
no longer matches fails loudly instead of shipping a silent no-op.

MAINTENANCE (howto.md, "Maintaining the pipeline itself"): edits to THIS file
follow the same discipline as the transforms it performs — grep the actual
occurrences before writing any batch substitution, derive patterns from what
is really there and anchor them on the semantic token (never on incidental
separators/spacing near it), pre-count matches, and assert the applied count
equals the pre-count. Expected counts must come from an independent
measurement of the pristine text, not from the substitution itself.
"""
import collections
import glob
import json
import re
import shutil
import subprocess
import sys

PAGE_BUDGET = 45          # code lines per page at the custom.sty geometry
DOCSTRING_BUDGET = 38     # estimated lines for an unbreakable docstring
PROSE_CHARS_PER_LINE = 95

# Fallbacks for characters DejaVu lacks; extend as surveys demand (howto 3.7).
UNICODE_FALLBACKS = {
    "⟺": r"\ensuremath{\Longleftrightarrow}",
    "≲": r"\ensuremath{\lesssim}",
    "≳": r"\ensuremath{\gtrsim}",
    "⟨": r"\ensuremath{\langle}",
    "⟩": r"\ensuremath{\rangle}",
    "⇒": r"\ensuremath{\Rightarrow}",
    "∘": r"\ensuremath{\circ}",
}


def heading_text(cmd):
    """The RENDERED text of a sectioning command, markup stripped.

    Two bugs in one line, both invisible until a heading contained inline code.
    The previous expression took the first non-greedy `{...}`, so
    `\\section{The \\texttt{AbstractFloat} contract}` yielded
    `The \\texttt{AbstractFloat` — truncated at the inner brace AND still
    carrying LaTeX. `validate.py` then searched the PDF for that string, never
    found it, and reported "same-page check could not run" for a heading that
    renders perfectly well.

    Balanced-brace scan for the argument, then drop command wrappers so the text
    matches what a reader sees. `survey.json` becomes legible at the same time,
    which is how the truncation would have been noticed sooner."""
    i = cmd.index("{")
    depth, j = 0, i
    while j < len(cmd):
        if cmd[j] == "{":
            depth += 1
        elif cmd[j] == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    arg = cmd[i + 1:j]
    arg = re.sub(r"\\[a-zA-Z]+\s*\{([^{}]*)\}", r"\1", arg)   # \texttt{x} -> x
    arg = re.sub(r"\\[a-zA-Z]+\s*", "", arg)                   # bare commands
    return arg.replace("{", "").replace("}", "").strip()


# ---------------------------------------------------------------------------
# Figures
# ---------------------------------------------------------------------------
def rasterless_figures(tex, src_dir, out_dir):
    r"""Make every `\includegraphics` target something xelatex can actually read.

    Documenter emits the asset path verbatim, extension included, so an SVG in
    the Markdown becomes `\includegraphics{assets/x.svg}` — which xelatex cannot
    open at all. (`graphicx` has no SVG reader; the `svg` package shells out to
    Inkscape per build.) The HTML site wants the SVG, so the fix belongs here,
    in the layer that already adapts Documenter's output for print.

    SVG is converted ONCE, to PDF rather than to a bitmap: the figure stays
    vector, so it prints at the device's resolution instead of the raster's.
    `rsvg-convert` is preferred over `inkscape` only because it is the smaller
    dependency; either produces the same page.

    Assets are copied into the build directory regardless of type, because the
    build directory is also the editable source bundle (howto.md Stage 6) and a
    bundle that cannot recompile on its own is not one.
    """
    import os, re, shutil, subprocess

    refs = re.findall(r"\\includegraphics(?:\[[^\]]*\])?\{([^}]+)\}", tex)
    if not refs:
        return tex, 0, 0

    converted = 0
    for ref in sorted(set(refs)):
        src = os.path.join(src_dir, ref)
        dst = os.path.join(out_dir, ref)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.exists(src):
            die(f"figure {ref} referenced but not found under {src_dir}")

        if ref.lower().endswith(".svg"):
            pdf_ref = ref[:-4] + ".pdf"
            pdf_dst = os.path.join(out_dir, pdf_ref)
            if shutil.which("rsvg-convert"):
                cmd = ["rsvg-convert", "-f", "pdf", "-o", pdf_dst, src]
            elif shutil.which("inkscape"):
                cmd = ["inkscape", src, "--export-type=pdf",
                       f"--export-filename={pdf_dst}"]
            else:
                die(f"{ref} is an SVG and xelatex cannot read one; install "
                    "rsvg-convert or inkscape, or reference a PDF/PNG asset")
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode != 0 or not os.path.exists(pdf_dst):
                die(f"SVG->PDF conversion failed for {ref}: "
                    f"{(r.stderr or r.stdout).strip()[:400]}")
            # Point the document at the converted file.
            tex = tex.replace("{" + ref + "}", "{" + pdf_ref + "}")
            converted += 1
        shutil.copy(src, dst)

    return tex, len(set(refs)), converted


def die(msg):
    print(f"transform.py: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


def minted_spans(tex):
    return [m.span() for m in re.finditer(
        r"\\begin\{minted\}.*?\\end\{minted\}", tex, re.S)]


def outside_minted(tex, fn):
    """Apply fn(text) -> text only to segments outside minted environments."""
    spans = minted_spans(tex)
    out, pos = [], 0
    for a, b in spans:
        out.append(fn(tex[pos:a]))
        out.append(tex[a:b])
        pos = b
    out.append(fn(tex[pos:]))
    return "".join(out)


def main():
    if len(sys.argv) != 3:
        die("usage: transform.py <resolved-dir> <out-dir>")
    src_dir, out_dir = sys.argv[1], sys.argv[2]
    texfiles = sorted(glob.glob(f"{src_dir}/*.tex"))
    texfiles = [t for t in texfiles if not t.endswith("preamble.tex")]
    if len(texfiles) != 1:
        die(f"expected exactly one resolved .tex in {src_dir}, found {texfiles}")
    tex = open(texfiles[0], encoding="utf-8").read()

    title = re.search(r"\\newcommand\{\\DocMainTitle\}\{(.*?)\}", tex)
    version = re.search(r"\\newcommand\{\\DocVersion\}\{(.*?)\}", tex)
    authors = re.search(r"\\newcommand\{\\DocAuthors\}\{(.*?)\}", tex)
    title = title.group(1).strip() if title else "Documentation"
    version = version.group(1).strip() if version else ""
    authors = authors.group(1).strip() if authors else ""

    # ---------------- Stage 2: survey -------------------------------------
    survey = {}
    blocks = re.findall(r"\\begin\{minted\}.*?\\end\{minted\}", tex, re.S)
    lens = sorted((b.count("\n") - 1 for b in blocks), reverse=True)
    survey["code_blocks"] = len(blocks)
    survey["longest_block_lines"] = lens[0] if lens else 0
    survey["longest_code_line_chars"] = max(
        (len(l) for b in blocks for l in b.split("\n")), default=0)

    parts = [m for m in re.finditer(r"^\\part\{.*\}$", tex, re.M)]
    survey["parts"] = len(parts)
    # flattenable iff every part segment contains exactly one \chapter
    flatten = len(parts) > 0
    for i, m in enumerate(parts):
        seg_end = parts[i + 1].start() if i + 1 < len(parts) else len(tex)
        nch = len(re.findall(r"^\\chapter\{", tex[m.start():seg_end], re.M))
        if nch != 1:
            flatten = False
    survey["parts_flattened"] = flatten

    labels = re.findall(r"\\label\{([^}]+)\}", tex)
    dups = sorted(l for l, c in collections.Counter(labels).items() if c > 1)
    survey["duplicate_labels"] = len(dups)

    doc_pat = re.compile(
        r"(\\hypertarget\{\d+\}\{.*?\}  -- \{[A-Za-z]+\.\}\n)"
        r"(\s*)(\\begin\{adjustwidth\}\{2em\}\{0pt\}.*?\\end\{adjustwidth\})",
        re.S)
    docstrings = doc_pat.findall(tex)
    survey["docstrings"] = len(docstrings)

    survey["tables"] = tex.count(r"\begin{tabulary}")
    survey["longtables"] = tex.count(r"\begin{longtable}")
    survey["admonitions"] = tex.count("admonition")
    survey["figures"] = tex.count(r"\includegraphics")
    # pre-count on the pristine text (outside minted): the 3.6 replacement
    # must apply exactly this many times — an independent assert, not a
    # count taken from the substitution itself. (No transform between here
    # and 3.6 inserts an escaped underscore, so the count is stable.)
    spans = minted_spans(tex)
    prose = "".join(tex[a:b] for a, b in
                    zip([0] + [s[1] for s in spans],
                        [s[0] for s in spans] + [len(tex)]))
    survey["escaped_underscores_prose"] = prose.count("\\_")
    survey["longest_texttt_token"] = max(
        (len(a) for a in re.findall(r"\\texttt\{([^{}]*)\}", tex)), default=0)
    survey["nonascii"] = "".join(sorted(set(c for c in tex if ord(c) > 127)))

    # TOC shape (rule 9 remediation room) + heading texture (regroup smell).
    # Both are surveyed and surfaced; regrouping is editorial (howto.md
    # Stage 2 note) and is never auto-applied here.
    marks = [(m.start(), m.group(1),
              re.search(r"\{(.*?)\}", m.group(0)).group(1))
             for m in re.finditer(
                 r"^\\(chapter|section|subsection|subsubsection)\{.*\}",
                 tex, re.M)]
    chap_sections = []
    for i, (pos, kind, _t) in enumerate(marks):
        if kind == "chapter":
            n = 0
            for j in range(i + 1, len(marks)):
                if marks[j][1] == "chapter":
                    break
                n += marks[j][1] == "section"
            chap_sections.append(n)
    survey["toc_max_chapter_block"] = max(chap_sections, default=0)
    regroup = []
    # (parent level, child level, levels that end the parent's scope)
    for parent, child, enders in (("chapter", "section", ("chapter",)),
                                  ("section", "subsection", ("chapter", "section"))):
        # `head_title`, not `title` — the document title lives in an enclosing
        # local of the same name, and rebinding it here silently set the PDF's
        # `pdftitle` to whatever heading this loop happened to visit last. Every
        # build produced "Internal Reference 0.1.0 — Documentation": the final
        # chapter's name, not the document's. Nothing checked the metadata, so it
        # had been wrong on every PDF the pipeline ever produced.
        for i, (pos, kind, head_title) in enumerate(marks):
            if kind != parent:
                continue
            spans = []
            for j in range(i + 1, len(marks)):
                if marks[j][1] in enders:
                    break
                if marks[j][1] == child:
                    end = marks[j + 1][0] if j + 1 < len(marks) else len(tex)
                    spans.append(sum(
                        max(1, -(-len(l.strip()) // PROSE_CHARS_PER_LINE))
                        for l in tex[marks[j][0]:end].split("\n") if l.strip()))
            titles = [marks[j][2] for j in range(i + 1, len(marks))
                      if marks[j][1] == child and
                      not any(marks[k][1] in enders
                              for k in range(i + 1, j))]
            # fragmentation signals (howto.md decision table): short spans,
            # child count beyond rule-9 TOC headroom, or variant families
            # (≥3 titles sharing a prefix, differing only by suffix)
            short = len(spans) >= 6 and sum(spans) / len(spans) < PAGE_BUDGET / 3
            crowded = len(spans) >= 12
            fams = collections.Counter(
                t.split(" — ")[0] for t in titles if " — " in t)
            family = any(c >= 3 for c in fams.values())
            if short or crowded or family:
                why = ", ".join(w for w, on in
                                (("short spans", short),
                                 (f"{len(spans)} children", crowded),
                                 ("variant families", family)) if on)
                regroup.append(f"{parent} {head_title!r} ({len(spans)} {child}s; "
                               f"avg {sum(spans)/len(spans):.0f} est lines; {why})")
    survey["regroup_candidates"] = regroup
    for r in regroup:
        print(f"transform.py: ADVISORY — section {r} is a regrouping "
              "candidate (demote-first procedure, howto.md Stage 2 note); "
              "editorial, not auto-applied", file=sys.stderr)

    # Unimplemented decision-table treatments must fail loudly, not be
    # silently skipped (asserted-edit principle applied to coverage).
    if survey["longtables"]:
        die(f"survey found longtables={survey['longtables']} — the "
            "multi-page-table treatment is not implemented here; extend "
            "transform.py first")
    if survey["longest_block_lines"] > PAGE_BUDGET:
        die(f"longest code block ({survey['longest_block_lines']} lines) "
            f"exceeds the page budget ({PAGE_BUDGET}) — the global minted "
            "keep-together hook is then unsound (howto.md 3.7): implement "
            "selective wrapping before building")

    # ---------------- Stage 3: transforms (order matters) -----------------
    # 3.1 flatten one-chapter parts
    if flatten:
        tex, n = re.subn(r"^\\part\{.*\}\n", "", tex, flags=re.M)
        if n != survey["parts"]:
            die(f"part flattening removed {n}, survey saw {survey['parts']}")

    # 3.2 uniquify duplicate labels (only when nothing references them)
    renamed = []
    for lab in dups:
        refs = len(re.findall(r"\\hyperlink(?:ref)?\{" + re.escape(lab) + r"\}", tex))
        if refs:
            die(f"duplicate label {lab} has {refs} references — needs "
                "source-position disambiguation, not a blind rename")
        pattern = re.compile(r"\\label\{" + re.escape(lab) + r"\}")
        seen = [0]

        def unique_label(m):
            k = seen[0]
            seen[0] += 1
            return m.group(0) if k == 0 else f"\\label{{{lab}-dup{k}}}"

        tex, n_lab = pattern.subn(unique_label, tex)
        expected = labels.count(lab)
        if n_lab != expected:
            die(f"duplicate label {lab}: rewrote {n_lab}, survey saw {expected}")
        renamed.append(lab)
    survey["labels_uniquified"] = len(renamed)

    # 3.3 glue colon-introduced code
    tex, n_colon = re.subn(r"(:\s*\n\n+)(\\begin\{minted\})",
                           r"\1\\nopagebreak[4]\n\2", tex)
    survey["colon_glued"] = n_colon

    # 3.4 group adjacent code chains (gap = whitespace only, total ≤ budget)
    spans = minted_spans(tex)
    chains, cur = [], [0] if spans else []
    for i in range(1, len(spans)):
        gap = tex[spans[i - 1][1]:spans[i][0]]
        if gap.strip() == "":
            cur.append(i)
        else:
            chains.append(cur)
            cur = [i]
    if cur:
        chains.append(cur)
    glue_chains = []
    for ch in chains:
        if len(ch) < 2:
            continue
        total = sum(tex[spans[i][0]:spans[i][1]].count("\n") - 1 for i in ch)
        if total <= PAGE_BUDGET:
            glue_chains.append(ch)
    out, pos = [], 0
    for ch in glue_chains:
        a, b = spans[ch[0]][0], spans[ch[-1]][1]
        out.append(tex[pos:a])
        out.append("\\begin{minipage}{\\linewidth}\n" + tex[a:b] +
                   "\n\\end{minipage}\n")          # fancyvrb: own line (howto 3.4)
        pos = b
    out.append(tex[pos:])
    tex = "".join(out)
    survey["chains_glued"] = len(glue_chains)

    # 3.5 wrap docstrings; rule 8: breakable glue between consecutive boxes
    def wrap_doc(m):
        header, gap, body = m.group(1), m.group(2), m.group(3)
        est = 0
        bpos = 0
        for a, b in [mm.span() for mm in re.finditer(
                r"\\begin\{minted\}.*?\\end\{minted\}", body, re.S)]:
            for line in body[bpos:a].split("\n"):
                s = line.strip()
                if s:
                    est += max(1, -(-len(s) // PROSE_CHARS_PER_LINE))
            est += body[a:b].count("\n") - 1
            bpos = b
        for line in body[bpos:].split("\n"):
            s = line.strip()
            if s:
                est += max(1, -(-len(s) // PROSE_CHARS_PER_LINE))
        if est <= DOCSTRING_BUDGET:
            return ("\\par\\medskip\\noindent\\begin{minipage}{\\linewidth}\n"
                    + header + "\\nopagebreak\n" + body
                    + "\n\\end{minipage}\n\\par\\medskip\n")
        return header + "\\nopagebreak\n" + body + "\n\\par\\medskip\n"

    tex, n_doc = doc_pat.subn(wrap_doc, tex)
    if n_doc != survey["docstrings"]:
        die(f"docstring wrap count {n_doc} != surveyed {survey['docstrings']}")
    survey["docstrings_wrapped"] = n_doc

    # 3.6 token + table fixes (outside minted only)
    def spec_LR(m):
        return m.group(1) + m.group(2).replace("R", "L") + "}"
    tex, n_tab = re.subn(r"(\\begin\{tabulary\}\{[^}]*\}\{)([^}]*)\}",
                         spec_LR, tex)
    if n_tab != survey["tables"]:
        die(f"tabulary spec fixes {n_tab} != surveyed {survey['tables']}")

    n_under = [0]
    n_longtok = [0]
    LONG_TOKEN = 25   # texttt args at least this long get intra-token breaks

    def breaks(seg):
        # long single-\texttt tokens (URLs, call chains): \allowbreak after
        # '/' and '(' — the unambiguous points howto.md 3.6 sanctions
        def longtok(m):
            arg = m.group(1)
            if len(arg) < LONG_TOKEN or "\\allowbreak" in arg:
                return m.group(0)
            n_longtok[0] += 1
            arg = arg.replace("/", "/\\allowbreak{}")
            arg = arg.replace("(", "(\\allowbreak{}")
            return "\\texttt{" + arg + "}"
        seg = re.sub(r"\\texttt\{([^{}]*)\}", longtok, seg)
        c = seg.count("\\_")
        n_under[0] += c
        seg = seg.replace("\\_", "\\_\\allowbreak{}")
        return re.sub(r"(\\texttt\{[^{}]*\})/(\\texttt\{)",
                      r"\1/\\allowbreak\2", seg)
    tex = outside_minted(tex, breaks)
    if n_under[0] != survey["escaped_underscores_prose"]:
        die(f"underscore \\allowbreak pass applied {n_under[0]} times, "
            f"pre-survey counted {survey['escaped_underscores_prose']}")
    survey["long_texttt_tokens_broken"] = n_longtok[0]

    # 3.6b tables keep their governing heading (howto.md rule 3): for each
    # table, estimate the extent from the nearest preceding heading (any
    # level) to the END of the table. Extent ≤ budget: \needspace before the
    # heading (chapters exempt — they open a fresh page). Extent > budget:
    # glue the table to its introducing paragraph instead. Measure the
    # extent, never the heading's whole span (the span gate shipped stacked
    # heading-without-table pages once).
    def est_lines(seg):
        return sum(max(1, -(-len(l.strip()) // PROSE_CHARS_PER_LINE))
                   for l in seg.split("\n") if l.strip())

    head_marks = [(m.start(), m.group(1), heading_text(m.group(0)))
                  for m in re.finditer(
                      r"^\\(chapter|section|subsection|subsubsection)\{.*\}",
                      tex, re.M)]
    kept_titles = []                 # for the validate.py same-page check
    needs = {}                       # heading position -> max demand
    glue_pos = []                    # table positions for the glue fallback
    for m in re.finditer(r"\\begin\{tabulary\}.*?\\end\{tabulary\}", tex, re.S):
        gov = max((h for h in head_marks if h[0] < m.start()),
                  key=lambda h: h[0], default=None)
        if gov is None:
            continue
        est = est_lines(tex[gov[0]:m.end()])
        if est <= PAGE_BUDGET and gov[1] != "chapter":
            needs[gov[0]] = max(needs.get(gov[0], 0), est + 2)
            kept_titles.append(gov[2])
        elif gov[1] != "chapter" or est > PAGE_BUDGET:
            glue_pos.append(m.start())
    insertions = [(pos, "\\nopagebreak[3]\n") for pos in glue_pos]
    insertions.extend(
        (pos, f"\\needspace{{{need}\\baselineskip}}\n")
        for pos, need in needs.items())
    for pos, insertion in sorted(insertions, key=lambda item: item[0], reverse=True):
        tex = tex[:pos] + insertion + tex[pos:]
    survey["table_units_kept_together"] = len(needs)
    survey["tables_glued_to_paragraph"] = len(glue_pos)
    survey["kept_unit_headings"] = sorted(set(kept_titles))

    # 3.7 custom.sty (+ generated unicode fallbacks)
    missing = font_misses(survey["nonascii"])
    fallbacks = []
    for c in missing:
        if c not in UNICODE_FALLBACKS:
            die(f"character {c!r} (U+{ord(c):04X}) is missing from at least one "
                "DejaVu family in use and has no fallback mapping — extend "
                "UNICODE_FALLBACKS")
        fallbacks.append(f"\\newunicodechar{{{c}}}{{{UNICODE_FALLBACKS[c]}}}")
    survey["unicode_fallbacks"] = "".join(missing)

    from datetime import datetime, timezone
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
    sty = CUSTOM_STY.replace("@FALLBACKS@", "\n".join(fallbacks)) \
                    .replace("@TITLE@", f"{title} {version} — Documentation") \
                    .replace("@AUTHORS@", authors) \
                    .replace("@BUILDDATE@", stamp)

    import os
    os.makedirs(out_dir, exist_ok=True)
    tex, nfig, nconv = rasterless_figures(tex, src_dir, out_dir)
    survey["figures_copied"] = nfig
    survey["figures_svg_converted"] = nconv
    open(f"{out_dir}/main.tex", "w", encoding="utf-8").write(tex)
    open(f"{out_dir}/custom.sty", "w", encoding="utf-8").write(sty)
    for f in ("documenter.sty", "preamble.tex"):
        target = f"{out_dir}/{f}"
        if os.path.exists(target):
            os.remove(target)          # prior copy may be read-only
        shutil.copy(f"{src_dir}/{f}", target)
    json.dump(survey, open(f"{out_dir}/survey.json", "w"), indent=1)
    print("transform.py: survey + transforms complete")
    for k, v in survey.items():
        print(f"  {k}: {v}")


def font_misses(nonascii):
    r"""Characters absent from ANY font the document sets text in.

    Not "absent from both". The predicate used to be `not any(...)` — a
    character counted as missing only when *every* font lacked it — and that let
    `⟺` (U+27FA) through: DejaVu Sans has it, DejaVu Sans Mono does not, and the
    document sets it inside `\texttt` when it appears in a docstring. Two
    "Missing character" lines, caught by the Stage 4 log gate rather than here,
    which is the wrong place to catch it.

    The survey cannot know which font a given occurrence will land in, so the
    correct test is conservative: if any font in use lacks the glyph, emit the
    fallback. That is free when the glyph *is* present in the text font, because
    every mapping in `UNICODE_FALLBACKS` is an `\ensuremath{...}` — it typesets
    from the math font regardless of the surrounding family, so the rendering is
    consistent either way rather than font-dependent."""
    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        print("transform.py: fontTools unavailable — skipping coverage check "
              "(Missing character log lines will catch any gap)", file=sys.stderr)
        return []
    paths = []
    for fam in ("DejaVu Sans", "DejaVu Sans Mono"):
        p = subprocess.run(["fc-match", "-f", "%{file}", fam],
                           capture_output=True, text=True).stdout.strip()
        if p:
            paths.append(p)
    if not paths:
        return []
    cmaps = [set(TTFont(p).getBestCmap()) for p in paths]
    return [c for c in nonascii if not all(ord(c) in cm for cm in cmaps)]


CUSTOM_STY = r"""% custom.sty — written by transform.py (docs/pdf/howto.md Stage 3.7).
% All overrides live here; the Documenter-generated files stay pristine.
\usepackage{etoolbox}
\usepackage{needspace}   % rule 3: short table-bearing subsections keep together

% Geometry: 1.1in side margins so ~100-char code lines fit at \small mono.
\setulmarginsandblock{1.15in}{1.0in}{*}
\setlrmarginsandblock{1.1in}{1.1in}{*}
\setheaderspaces{0.6in}{*}{*}
\checkandfixthelayout

% Mandatory pagination rules (howto.md rules 1-6).
\raggedbottom
\interlinepenalty=10000
\clubpenalty=10000 \widowpenalty=10000
\displaywidowpenalty=10000 \brokenpenalty=10000
\predisplaypenalty=10000   % equations stay with their introducing text
\predisplaypenalty=10000

% Code blocks: unbreakable, wrapped safely, visible continuation marker.
% The \par\medskip on each side is the rule-8 breakable glue.
\setminted{breaklines=true, breakindent=1.5em,
  breaksymbolleft={\tiny\ensuremath{\hookrightarrow}},
  fontsize=\small}
\BeforeBeginEnvironment{minted}{\par\medskip\noindent\begin{minipage}{\linewidth}}
\AfterEndEnvironment{minted}{\end{minipage}\par\medskip}

% Tables: unbreakable, footnotesize, tightened column padding.
\BeforeBeginEnvironment{tabulary}{\par\medskip\noindent
  \begin{minipage}{\linewidth}\footnotesize\setlength{\tabcolsep}{3pt}}
\AfterEndEnvironment{tabulary}{\end{minipage}\par\medskip}

% Running headers/footers; folio-only on chapter openings.
\pagestyle{ruled}
\makeevenfoot{ruled}{}{\thepage}{}  \makeoddfoot{ruled}{}{\thepage}{}
\makeevenhead{ruled}{\small\leftmark}{}{} \makeoddhead{ruled}{}{}{\small\rightmark}
\copypagestyle{plain}{ruled} \makeevenhead{plain}{}{}{} \makeoddhead{plain}{}{}{}
\copypagestyle{chapter}{ruled} \makeevenhead{chapter}{}{}{}
\makeoddhead{chapter}{}{}{} \makeheadrule{chapter}{\textwidth}{0pt}

% TOC block integrity (howto.md rule 9): contents-page breaks belong BEFORE
% chapter entries, never inside a chapter's subentry block — so discourage
% breaks before section-level TOC lines (penalty 3, not infinite: a block
% taller than a contents page may still break, per the rule's exception).
\makeatletter
% \pretocmd, not \preto: \l@section is parameterized, and \preto would strip
% its parameter text (the ".toc has an extra }" failure). Loud on failure.
\pretocmd{\l@section}{\nopagebreak[3]}{}
  {\PackageError{custom}{l@section TOC rule-9 patch failed to apply}{}}
\makeatother

% Unicode fallbacks — generated from the survey's coverage check.
\usepackage{newunicodechar}
@FALLBACKS@

\emergencystretch=3em

% Cover page date: the build's UTC timestamp (memoir's \maketitle prints \date;
% the title/author macros in preamble.tex leave it untouched).
\date{@BUILDDATE@}

\hypersetup{pdftitle={@TITLE@}, pdfauthor={@AUTHORS@},
  bookmarksnumbered=true, bookmarksopen=true}
"""

if __name__ == "__main__":
    main()
