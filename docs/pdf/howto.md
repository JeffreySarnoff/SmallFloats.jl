# howto.md — Publication-quality PDF from a Documenter.jl docs tree

A package-agnostic pipeline for turning a Documenter.jl documentation tree
into one coherent, strictly paginated PDF: title page, table of contents,
numbered sections, bookmarks, working cross-references, syntax-highlighted
code, and no split paragraphs, stranded headings, or broken elements.

This document is the pipeline's specification (it absorbed and replaced the
earlier `generate_pdf.md` and the manual builds' notes). The implementation
lives beside it: `buildpdf.sh` orchestrates, `transform.py` implements
Stages 2–3, `validate.py` the automated part of Stage 5, and each run
autogenerates `buildnote.md`. `builddocs.jl` invokes the pipeline after the
HTML build (`DOCS_PDF=skip` to omit).

Nothing is hardcoded to a particular package: a survey of the resolved LaTeX
decides which transforms apply, every transform is conditional on what the
survey found, and a render-and-inspect loop asserts the result page by page.
The appendices hold per-package knobs (A), paid-for failure modes (B), and a
worked example from a real build (C).

```
0. Preflight        environment + package compatibility checks (fail fast)
1. Resolve          Documenter → fully expanded LaTeX source
2. Survey           measure the source; fill in the decision table
3. Transform        one idempotent, conditional pass over the .tex
4. Compile          clean latexmk build + log triage
5. Validate         render every page → inspect → remediate → fixpoint
6. Package          PDF + editable source + build note
```

## The pagination rules

Every rule below is enforced somewhere in Stages 3–5; a build that cannot
satisfy one must record the deliberate exception in the build note.

1. Paragraphs never split across pages.
2. Page breaks fall only between complete elements (a sentence-ended
   paragraph, a whole code line, a whole list item).
3. Headings and captions stay with the content they introduce. Two explicit
   consequences:
   - A heading followed by text never lets that first paragraph split over
     the break — the *heading moves to the next page* and the current page
     runs short (the composed effect of rules 1 and 6 with the class's
     after-heading `\nobreak`; the intended resolution, not an accident).
   - A table stays on the same page as its governing heading — at *any*
     sectioning level — whenever the heading-to-end-of-table extent fits the
     page budget: the heading defers to the next page (`\needspace`) rather
     than sitting on one page with its table on the next. When even that
     extent exceeds a page, the table instead glues to its introducing
     paragraph (the colon-glue analog), so it never strands at a page top.
     The extent is measured heading → end of table, **not** the heading's
     whole span — a long section whose table sits just below the heading
     still qualifies.
4. A section does not open without room for its heading, its intro, and its
   first subsection's first element.
5. No widows, orphans, stranded headings, or blank pages from faulty
   pagination.
6. Short pages are always preferred to bad breaks (`\raggedbottom`).
7. Code, tables, figures, equations, admonitions, and definition blocks split
   only when they cannot fit on one page — and then only deliberately:
   readable size reduction, landscape, or labeled logical parts with repeated
   headers. Never scale below comfortable readability.
8. Consecutive unbreakable units must be separated by *breakable* glue: a run
   of keep-together boxes with nothing breakable between them is one giant
   unbreakable unit, and it will overflow (a real build measured a 4016 pt
   `Overfull \vbox` from stacked docstring boxes before this rule existed).
9. **Table of contents integrity:** in the rendered TOC, a chapter-level
   entry and its subentries form one block, breakable only *before* the
   entry. A block taller than a contents page may break, but never right
   after the chapter entry, and the continuation must resume with a
   subentry.

---

## Stage 0 — Preflight

Check everything the pipeline will need before spending time on any of it.

```bash
# 0.1  Julia version: the package's compat decides which Julia to install.
grep -A20 '^\[compat\]' Project.toml | grep '^julia'
# Install a matching release from julialang-s3 and put it on PATH.

# 0.2  Docs environment: read docs/Project.toml for Documenter's major version
#      and for plugins that change the build (DocumenterCitations, Literate,
#      DemoCards, DocumenterMermaid, ...). Plugins must be replicated in the
#      LaTeX build or their content will be missing or broken.
cat docs/Project.toml

# 0.3  TeX toolchain: XeLaTeX or LuaLaTeX (fontspec is mandatory for
#      Documenter's LaTeX style), latexmk, and Pygments for minted.
which xelatex latexmk pygmentize

# 0.4  Fonts: documenter.sty hardcodes DejaVu Sans / DejaVu Sans Mono.
fc-list | grep -qi "DejaVu Sans Mono"

# 0.5  Validation tooling.
which pdftoppm pdfinfo qpdf
pip install pdfplumber pypdf pillow fonttools -q
```

Then read `docs/make.jl` and record, without changing anything yet:

- the `pages = [...]` tree — the PDF must preserve this ordering and nesting;
- `modules`, `sitename`, `authors` — reused verbatim;
- `checkdocs` / `warnonly` — the set of warnings that are *expected*;
- whether the build runs doctests or `@example` blocks — these execute the
  package, so it must load with all binary/system dependencies present (test
  with `julia --project=docs -e 'using <Package>'` after Stage 1.1);
- any pre-`makedocs` generation steps (a report copied into `docs/src`, pages
  written by a script) — the LaTeX build script must run the same steps or
  those pages will be stale or missing;
- any HTML-only machinery (`assets`, `analytics`, custom writers,
  `size_threshold` tuning) — irrelevant to LaTeX, drop it;
- `remotes` / repo detection — building from a local or shallow clone needs
  `remotes = nothing` (Documenter ≥ 1) or the build errors.

---

## Stage 1 — Resolve the documentation with Documenter

Never hand-convert the Markdown. `@docs`, `@autodocs`, `@ref`, `@example`,
`@index`, and the navigation tree must be resolved by Documenter with the
package loaded, or generated API material and cross-references will be wrong
or missing. The LaTeX writer with `platform = "none"` emits the resolved
`.tex` without trying to compile it; that file is the source of truth for
every later stage.

```bash
# 1.1  Instantiate the docs environment against the local package.
julia --project=docs -e '
  import Pkg
  Pkg.develop(Pkg.PackageSpec(path = pwd()))
  Pkg.instantiate()'
```

```julia
# 1.2  docs/make_latex.jl — a copy of docs/make.jl with only these changes:
#      format → Documenter.LaTeX(platform = "none", version = v"<pkg version>"),
#      build  → "build_latex",
#      remotes = nothing        (if building from a local/shallow clone),
#      drop deploydocs and HTML-only options; KEEP pages, modules, plugins,
#      pre-build generation steps, checkdocs, and warnonly exactly as the
#      package defines them. If pages evolve in make.jl, make_latex.jl must
#      follow — copy verbatim, never paraphrase from memory.
```

```bash
julia --project=docs docs/make_latex.jl
# → docs/build_latex/{<SiteName>.tex, documenter.sty, preamble.tex, custom.sty}
```

**Gate 1.** The log ends at `LaTeXWriter: creating the LaTeX file` with only
the warnings that `warnonly` predicted; doctests (if enabled) passed; and the
emitted `.tex` contains zero literal `@docs`/`@autodocs`/`@ref`/`@example`
strings. If Documenter errors on a construct the LaTeX writer cannot handle
(rare: raw HTML blocks, some plugin output), fix it at the source level
(`@raw html` → static alternative) rather than in the `.tex`, and record it
for the build note.

---

## Stage 2 — Survey the resolved source

One script, run once. Its output fills the decision table that drives every
transform in Stage 3. Measure at least:

```python
import re, collections
tex = open('SITE.tex').read()

# Code blocks: count, per-block line counts, longest raw line.
blocks = re.findall(r'\\begin\{minted\}.*?\\end\{minted\}', tex, re.S)
lens   = sorted((b.count('\n') for b in blocks), reverse=True)

# Structure: parts/chapters, tables, figures, math, admonitions, verbatim.
counts = {k: tex.count(k) for k in (
    '\\part{', '\\chapter{', '\\begin{tabulary}', '\\begin{longtable}',
    '\\includegraphics', '\\[', '\\begin{equation', '\\begin{align',
    'admonition', '\\begin{verbatim}')}

# Labels: duplicates collide (identical section titles on different pages).
labels = re.findall(r'\\label\{([^}]+)\}', tex)
dups   = [l for l,c in collections.Counter(labels).items() if c > 1]

# Docstring entries (Documenter's API-reference shape).
docstrings = re.findall(
    r'\\hypertarget\{[^}]*\}\{[^\n]*?\}  -- \{[A-Za-z]+\.\}', tex)

# Long unbreakable mono tokens — measure ALL of them, not just code blocks:
# escaped underscores, slash-joined names, and the single-\texttt width
# distribution (URLs and call chains hide here; the longest prose-embedded
# token is as pagination-relevant as the longest minted line).
esc_underscores = tex.count('\\_')
slash_pairs = len(re.findall(r'\\texttt\{[^}]*\}/\\texttt\{', tex))
tok_lens = sorted((len(a) for a in re.findall(r'\\texttt\{([^{}]*)\}', tex)),
                  reverse=True)

# TOC shape: subentries per chapter (drives the rule-9 check in Stage 5).
# Counted from the .tex sectioning commands, chapter by chapter.

# Heading texture: subsections per section and each subsection's span length
# (heading to next sectioning command) — many short subsections in one
# section is a structure smell the pipeline surfaces but does not auto-fix.

# Unicode inventory, to be checked against actual font coverage (Stage 3.7).
nonascii = sorted(set(c for c in tex if ord(c) > 127))
```

Derive the **page budget** from the geometry you will set in `custom.sty`
(Letter/A4, ~1.1 in side margins, `\small` mono ⇒ roughly 45 code lines or
50 body lines per page; recompute if you change geometry or fonts). Then fill
the decision table:

| Measurement | Decision |
|---|---|
| every `\part` contains exactly one chapter with the same title | flatten parts to chapters (kills near-blank divider pages); otherwise **keep parts** — the package's grouping is real structure |
| duplicate labels exist | uniquify; if any duplicate is the target of `\hyperlinkref`, disambiguate references by source position too |
| longest code block ≤ page budget | all code blocks become unbreakable |
| some code blocks > page budget | those blocks stay breakable (splitting an oversized element is permitted); optionally split them at the *source* level into logically complete, labeled parts |
| adjacent code blocks separated only by whitespace (input/output pairs) | glue chains whose combined length fits the budget; leave longer chains breakable *between* blocks |
| tables present | wrap unbreakable if the whole table fits a page at a readable size (≥ footnotesize); a taller table gets the deliberate treatment: landscape, or logical parts with the header row repeated and continuations labeled |
| figures present | keep each `\includegraphics` and its caption as one unbreakable unit; oversized figures scale to `\linewidth`/page height, not split |
| display math present | keep `\predisplaypenalty`/`\postdisplaypenalty` high so equations stay with their introducing text |
| docstrings present | wrap each header+body as one unbreakable unit if its estimated height fits the budget; otherwise glue only the header to the body's first element. **Always separate consecutive wrapped units with breakable glue** (rule 8) |
| non-ASCII characters present | fallback-map exactly those absent from the document fonts (Stage 3.7) |
| longest raw code line at chosen geometry | if wider than the text block: widen margins first, then rely on `breaklines` with a visible continuation marker; landscape only for pathological cases |
| longest inline `\texttt` token vs the measure | tokens longer than ~25 chars (URLs, qualified names, call chains) get intra-token `\allowbreak` at unambiguous points (`/`, `(`, after `\_`) as a Stage 3.6 transform — `breaklines` only helps *minted*, never inline mono, and `\emergencystretch` cannot absorb a 90 pt token |
| chapters with many TOC subentries | note the largest block; the rule-9 TOC check in Stage 5 will need remediation room if any block approaches a contents-page height |
| a table whose heading→end-of-table extent fits the page budget (any heading level) | keep-together (rule 3): `\needspace{⌈est⌉\baselineskip}` before the governing heading (Stage 3.6); larger extents get the glue fallback — `\nopagebreak` between the table and its introducing paragraph |
| a fragmented heading, any of: ≳ 6 children with spans under a third of a page; more children than a contents block comfortably holds (≳ 12, rule 9 headroom); or ≥ 3 children whose titles share a prefix and differ only by a variant suffix | **editorial regrouping, at the source level**: demote-first, then cluster under concise group headings — the note below the table gives the procedure; it applies identically at every level. Variant families are the strongest natural-cluster signal: the shared prefix names the group, the suffixes become the demoted headings |

---

**On regrouping many short children.** A heading that fragments into many
short children — a chapter into sections, or a section into subsections —
typesets badly no matter what the pipeline does: pages dominated by headings
(check 9 flags the rhythm), an oversized rule-9 TOC block, and keep-together
treatments that fight each other. The fix is structural, so it belongs in
`docs/src`, not in the `.tex` (and when the offending page is *generated* —
a report, a changelog — in its generator). Proceed **demote-first**, in two
mechanical-then-editorial steps, at whichever level fragmented:

1. Demote every short child one level (`## Subsection` → `### Subsubsection`
   in the Markdown; sections → subsections one level up) — a pure heading
   edit, no content moves.
2. Read the resulting run of demoted headings, form the natural clusters,
   and insert a new heading at the vacated level above each cluster — a
   *concise* noun phrase naming what unites the members, not a list of them.

Demote-first beats inventing group headings first: with every member at the
same lower level, cluster boundaries get chosen on content alone, and the
document never passes through a state of mixed heading levels.

Consequences to check afterward: the HTML site changes too (source edits are
shared — make them deliberately, with the maintainer, never silently for the
PDF alone); the TOC shrinks (subsubsections sit below the usual `tocdepth`),
which also eases rule 9; cross-references to demoted headings must still
resolve (re-run Gate 1). Record the regrouping in the build note's
Reorganizations section. `.tex`-level demotion of the same shape is a last
resort only — the PDF's structure then silently diverges from the site's.

## Stage 3 — Transform: one idempotent, conditional pass

Apply the decision table in a single script against a pristine copy of the
resolved `.tex`. Order matters (later steps match text produced by earlier
ones): **3.1 flatten parts → 3.2 uniquify labels → 3.3 glue colon-introduced
code → 3.4 group code chains → 3.5 wrap docstrings → 3.6 token and
table/figure fixes → 3.7 write `custom.sty` → 3.8 probe the preamble.**
Every regex substitution
asserts its match count against the survey (`assert n == expected`) so a
silently failing edit stops the build instead of shipping.

**3.1 Flatten `\part` wrappers** — only under the survey condition. Report it
as a reorganization in the build note.

**3.2 Uniquify duplicate labels** — rename second and later occurrences with
a deterministic suffix; patch references only if the survey found any.

**3.3 Glue colon-introduced code** — a paragraph ending `:` followed by a
code block must not separate from it:

```python
tex = re.sub(r'(:\s*\n\n+)(\\begin\{minted\})', r'\1\\nopagebreak[4]\n\2', tex)
```

**3.4 Group adjacent code blocks** — for each whitespace-separated chain
whose total lines fit the page budget, wrap the chain in one outer
`\begin{minipage}{\linewidth} ... \end{minipage}`.

> ⚠ **fancyvrb constraint:** nothing may follow `\end{minted}` on its line —
> not even `%`. Put the closing `\end{minipage}` on the next line.

**3.5 Wrap docstrings** — estimate height (code lines counted directly; prose
at ≈ chars-per-line for your geometry); wrap fitting docstrings whole, with
`\nopagebreak` between the `\hypertarget` header and the body; for oversized
ones glue only the header. The estimate is deliberately conservative and
backstopped by Stage 4's hard `Overfull \vbox = 0` gate.

> ⚠ **Rule 8 applies here concretely:** consecutive wrapped docstrings must
> be separated by breakable glue (`\par\medskip` *outside* the minipages, or
> an explicit `\vspace` + `\penalty0`). Without it the boxes stack into one
> unbreakable column — the 4016 pt `Overfull \vbox` failure mode.

**3.6 Token, table, and figure fixes** — per the decision table:

- `\allowbreak` after escaped underscores (`\_`) and other unambiguous break
  points inside long mono tokens (after `/` joining two `\texttt` names,
  after `(`). Counts come from the survey and are asserted.
- Column-spec changes: right-aligned `R` prose columns defeat hyphenation and
  inflate minimum widths — prefer `L`.
- Figure + caption keep-together wrappers; the multi-page-table treatment
  where the survey demanded it.
- A paragraph that still overfills after `\allowbreak` insertion (e.g. two
  long camelCase tokens) gets a *local* `\emergencystretch` bump, not a
  global one beyond the preamble default.
- **Tables keep their governing heading (rule 3).** For each table, find the
  nearest preceding sectioning command at any level and estimate the extent
  from that heading to the *end of the table*. Extent ≤ page budget: insert
  `\needspace{⌈est⌉\baselineskip}` immediately before the heading
  (`\usepackage{needspace}` in `custom.sty`); chapters are exempt — they
  already open a fresh page. Extent > budget: glue the table to its
  introducing paragraph with `\nopagebreak` instead, so the table never
  strands at a page top. Measure the extent, never the heading's whole span
  — gating on the span silently exempts long sections whose table sits
  right under the heading (a real build shipped three stacked
  heading-without-table pages that way). A too-large estimate just turns
  the page early, which rule 6 prefers anyway.

**3.7 Write `custom.sty`.** All overrides live here so the Documenter-
generated files stay pristine. The pagination core is package-independent:

```latex
\usepackage{etoolbox}

% Geometry — pick to fit the measured longest code line, then recompute
% the page budget used by Stages 2/3.
\setulmarginsandblock{1.15in}{1.0in}{*}
\setlrmarginsandblock{1.1in}{1.1in}{*}
\setheaderspaces{0.6in}{*}{*}
\checkandfixthelayout

% Mandatory pagination rules.
\raggedbottom                       % rule 6: short pages beat bad breaks
\interlinepenalty=10000             % rule 1: paragraphs are unbreakable units
\clubpenalty=10000 \widowpenalty=10000
\displaywidowpenalty=10000 \brokenpenalty=10000
\predisplaypenalty=10000            % equations stay with their intro text
% memoir emits \nobreak after headings; with unbreakable paragraphs this
% makes heading + first element an indivisible unit (rules 3 and 4).

% Code blocks: unbreakable, safe wrapping, visible continuation marker.
\setminted{breaklines=true, breakindent=1.5em,
  breaksymbolleft={\tiny\ensuremath{\hookrightarrow}},
  fontsize=\small, bgcolor=codeblock-background}
\BeforeBeginEnvironment{minted}{\par\medskip\noindent\begin{minipage}{\linewidth}}
\AfterEndEnvironment{minted}{\end{minipage}\par\medskip}
% The \par\medskip on each side is the rule-8 breakable glue between
% consecutive boxes. If the survey found code blocks taller than a page, do
% NOT install this hook globally; wrap only the fitting blocks explicitly.

% Tables (adjust size per survey; never below comfortable readability).
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

% TOC block integrity (rule 9): contents-page breaks belong BEFORE chapter
% entries, never inside a chapter's subentry block — discourage breaks before
% section-level TOC lines. Penalty 3, not infinite: a block taller than a
% contents page may still break (the rule's tall-block exception).
\makeatletter
% \pretocmd, not \preto or \patchcmd-on-\l@chapter: \l@section is
% parameterized and \preto would strip its parameter text; patching the
% chapter entry does not protect the run of subentries. Failure branch
% errors loudly — the same asserted-edit principle as the Stage 3 regexes.
\pretocmd{\l@section}{\nopagebreak[3]}{}
  {\PackageError{custom}{l@section TOC rule-9 patch failed to apply}{}}
\makeatother
% Penalties alone cannot guarantee rule 9 for tall blocks — Stage 5 check 8
% verifies the rendered TOC and remediates any residual split (see there).

% Unicode fallbacks — GENERATED, not hardcoded: check every survey character
% against the document fonts and map only the misses (coverage script below).
\usepackage{newunicodechar}
%% \input{unicode-fallbacks.tex}

\emergencystretch=3em               % absorb long inline-code tokens

\hypersetup{pdftitle={<SiteName> <version> — Documentation},
  pdfauthor={<authors>}, bookmarksnumbered=true, bookmarksopen=true}
```

Generate the fallback list programmatically (portable across packages with
different symbol inventories):

```python
from fontTools.ttLib import TTFont
cmaps = [set(TTFont(p).getBestCmap()) for p in (SANS_PATH, MONO_PATH)]
missing = [c for c in nonascii if not any(ord(c) in cm for cm in cmaps)]
# map each miss to \ensuremath{...} or a \newfontfamily fallback; if no
# reasonable mapping exists, that's a finding for the build note.
```

**Patching class internals** (applies to every `\patchcmd`-style line in
`custom.sty`): before touching any macro you did not define, inspect its
definition (`\show\l@section`, or `latexdef -c memoir l@section`) — internal
macros routinely carry parameter texts, and the parameterless etoolbox forms
(`\preto`/`\appto`) silently splice code *in front of* the parameter text,
producing a corrupted macro whose error surfaces far from the cause (e.g. at
`.toc` execution, one full compile later). Always use the parameter-aware
forms (`\pretocmd`/`\apptocmd`/`\patchcmd`) and always give the failure
branch a loud `\PackageError` — the same asserted-edit principle as the
Stage 3 regexes, applied to TeX.

**3.8 Probe the preamble before the full compile.** A `custom.sty` mistake
found by the full document costs a whole Stage-4 cycle; the same mistake in a
probe costs seconds. Build the probe from the **real document's preamble**
(truncate the transformed `main.tex` at `\begin{document}`) — a synthetic
`\documentclass` stub misses definitions the real preamble carries and fails
for its own reasons. Append a specimen body exercising everything
`custom.sty` touches: `\tableofcontents` + a chapter and section (the second
pass executes the patched TOC macros — this is what catches a broken
`\l@section`), a long inline mono token, a minted block, a tabulary table,
and one of each fallback-mapped Unicode character:

```bash
sed -n '1,/\\begin{document}/p' main.tex > probe.tex
cat >> probe.tex <<'EOF'
\tableofcontents
\chapter{Probe}\section{Section}
Prose with \texttt{a\_very/long(token)} and specimen glyphs.
\begin{minted}{julia}
f(x) = x
\end{minted}
\begin{tabulary}{\linewidth}{L L} a & b \\ \end{tabulary}
\end{document}
EOF
xelatex -shell-escape -interaction=nonstopmode probe.tex   # twice: the .toc
xelatex -shell-escape -interaction=nonstopmode probe.tex   # executes on pass 2
```

Gate: both passes error-free (`grep -c '^!' probe.log` = 0). Only then enter
Stage 4 with the real document. (Verified live: a `\preto`-corrupted
`\l@section` that previously cost a full compile cycle fails this probe in
under three seconds, at the preamble line that caused it.)

**Maintaining the pipeline itself.** The survey → transform → assert
discipline applies to editing `transform.py`, `validate.py`, `buildpdf.sh`,
and report generators exactly as it applies to editing the `.tex` — the two
failure modes below were both paid for while editing pipeline files, not
documents:

1. **Survey before substituting.** Before any batch edit (regex, sed),
   grep the *actual* occurrences, derive the pattern from what is really
   there, pre-count them, and assert the substitution count equals the
   pre-count. Anchor patterns on the semantic token (the thing you mean to
   change), never on incidental syntax nearby — a separator or spacing that
   happens to precede it will divide your matches into the ones you
   imagined and the ones you missed.
2. **A launch is not a run.** Long-running chains go through the managed
   background mechanism only — a bare shell `&` inside a foreground command
   dies with its parent, leaving a zero-byte log that looks like "nothing
   happened". After launching anything asynchronous, verify liveness (the
   log is growing / the sentinel appears) before reporting it as running.
3. **Failure-gate dependent steps.** A patch step and the run that depends
   on it must be `&&`-chained (or separated by a verified checkpoint);
   two adjacent statements in one shell will happily run the second after
   the first fails. `buildpdf.sh` itself runs under `set -euo pipefail` and
   ends with an explicit sentinel line — a log without the sentinel means
   killed or truncated, never success.

Two rules stay in the compile/validate loop because they need typeset output:
residual inline-code margin overflows (targeted `\allowbreak` at unambiguous
points) and rule-4 section placement (`\needspace` or `\clearpage` at the
flagged spot). One number governs both loops: **every validator threshold is
derived from a doctrine number stated once** (the ~10 pt hbox investigate
line, the page budget, the margin) — a validator that invents its own
tolerance will fight the triage table until someone reconciles them.

---

## Stage 4 — Compile and triage the log

Always build from a clean state — a stale latexmk database can report
"up-to-date" over an unpopulated TOC.

```bash
rm -f main.pdf main.aux main.toc main.out main.fdb_latexmk
latexmk -xelatex -shell-escape -interaction=nonstopmode -halt-on-error main.tex
```

| Log signal | Meaning | Remedy |
|---|---|---|
| compile error | often the fancyvrb line rule (3.4) or a plugin's LaTeX | fix the transform / handle the construct at source level |
| `Overfull \vbox` (page-scale, e.g. hundreds–thousands of pt) | consecutive unbreakable units with no breakable glue between them (rule 8) | restore the glue between the boxes; do not shrink content |
| `Overfull \vbox` (element-scale) | one unbreakable unit exceeds the page | **hard failure**: unwrap that unit and let it break between its complete elements, or apply the oversized-element treatment (rule 7) |
| `Missing character` | glyph absent despite Stage 3.7 | extend the fallback map |
| multiply-defined labels | duplicates missed in 3.2 | uniquify |
| `Overfull \hbox` beyond ~10 pt | text may enter the margin | `\allowbreak` at an unambiguous point; verify table-cell overfulls against the rendered page — ones absorbed by intercolumn space are harmless |
| empty/short `.toc` | stale aux state | you skipped the clean step |

**Gate 4.** Zero errors, zero `Overfull \vbox`, zero missing characters, no
duplicate labels, and the `.toc` lists every chapter and section.

---

## Stage 5 — Validate: render, inspect, remediate, fixpoint

Source-level directives are asserted, never trusted. Render **every** page at
≥ 200 dpi and run the full battery; after any remediation, recompile and rerun
**everything** until a build passes with zero findings.

```bash
pdftoppm -png -r 200 main.pdf pages/p
```

1. **Split paragraphs** — `Overfull \vbox = 0` proves none (paragraphs cannot
   split under `\interlinepenalty`); additionally each page's last content
   line must end a complete element and each page's first line must start one
   (not a lowercase continuation word). Eyeball flagged boundaries — code
   comments legitimately trip the heuristic.
2. **Stranded headings** — no page's last content line may be heading-styled.
   **Calibrate detection first** on a page with known headings: with fontspec
   `Scale=MatchLowercase`, extracted sizes differ from nominal (e.g. DejaVu
   body ≈ 7.9 pt, sections ≈ 9.4 pt bold), so naïve "large font" thresholds
   miss everything. Check both sectioning heads *and* docstring headers
   (`Name -- {Kind.}`).
3. **Split blocks** — no code/admonition background band touching the bottom
   content edge of page *n* and the top of *n+1*; on a hit, check the source:
   one split block is a violation; two adjacent blocks is a legal break —
   unless they form an input/output pair, which goes back to 3.4. Same scan
   for tables and figures (caption on one page, body on the next = violation).
   Additionally, for every table whose heading→table extent fit the budget
   (the Stage 3.6 keep-together list): assert the table renders on the same
   page as its governing heading — the transform *promises* this; the render
   proves it.
4. **Rule 4** — a section whose first subsection lands on a later page must
   have opened high on its own page; flag sections opening in the bottom third.
5. **Blank pages** — none after the front matter.
6. **Margins** — rightmost/leftmost ink respects the margins on every page;
   for landscape pages, check rotated.
7. **Function** — bookmarks mirror the full pages tree with correct targets;
   every internal `/GoTo` link resolves to an existing named destination; TOC
   page numbers match heading pages; `qpdf --check` is clean; text extracts
   on every page with no U+FFFD or private-use glyphs; figures render
   (non-blank image regions where `\includegraphics` was emitted).
8. **TOC block integrity (rule 9)** — on the rendered contents pages, locate
   each chapter-level entry and its subentry run; assert no block crosses a
   page boundary (except the permitted tall-block case, which must break
   after at least the first subentries and resume with a subentry).
   *Remediation:* write a `\newpage` into the `.toc` immediately before the
   chapter entry that begins the split block. Because latexmk regenerates the
   `.toc`, apply the edit after latexmk reaches its fixpoint and run **one
   final `xelatex` pass directly** (not latexmk); then re-render and confirm
   the TOC page count and all subsequent folios are unchanged — if pagination
   shifted, redo the whole Stage 4 → 5 loop with the edit scripted in.

9. **Page-fill rhythm (the pleasingness metric).** The pagination rules
   trade bad breaks for short pages — correct, but a *run* of half-empty
   pages reads as broken even with every gate green. Measure per-page
   vertical ink extent; flag (a) any non-chapter-final page below ~55% fill
   and (b) two or more consecutive pages below ~70%. Remedies work at the
   source or transform level (reorder, resize the unit that forced the early
   break, `\needspace`) — never by weakening the break rules. A flagged page
   that survives review is *accepted with a reason in the build note*, not
   silently tolerated. The thresholds are doctrine numbers: stated once,
   validator derived from them.
10. **Visual diff against the previous build.** Archive the rendered pages;
   on a rebuild, eyeball **only the pages whose layout changed** — aesthetic
   drift passes every structural gate silently, and re-eyeballing all
   unchanged pages is how inspection quietly stops happening. On a first
   build, substitute a fixed-checklist sample: every chapter opening, the
   TOC pages, the densest table page, the longest code page.

**Gate 5.** Checks 1–8 clean on the same build; every check-9/10 flag either
remediated or recorded as accepted in the build note.

---

## Stage 6 — Package

Deliver three things:

- **The PDF**, named for the package with no version/date in the filename
  (`SmallFloats.pdf` here — strip a `.jl` suffix); the version and the
  build's UTC timestamp (`YYYY-MM-DDThh:mmZ`) live on the cover page, set
  via `\date` in `custom.sty` at transform time.
- **Editable source bundle**: the transformed `main.tex`, `custom.sty` (and
  generated `unicode-fallbacks.tex`), the untouched `documenter.sty` /
  `preamble.tex`, `make_latex.jl`, the transform and validation scripts, and
  a README with the compile command — so the document can be edited at either
  level: regenerate from `docs/src` via Documenter, or edit the resolved
  LaTeX directly.
- **Build note** — the durable record; next build's Stage 0 starts by reading
  it. Use this template (section per heading, one build note per build):

```markdown
# Build note — <SiteName>-<version>.pdf (built <date>)

Source pages (count + first…last), page count, paper size.

## Toolchain
TeX distribution, engine, Pygments, fonts, Documenter version/writer,
validation tools + dpi.

## Reorganizations relative to docs/make.jl
Part-flattening, label uniquification (state whether any were link targets),
page reordering, heading-level regroupings (subsections clustered under new
group headings) — anything where the PDF's structure is not the site's, and
any source-level regrouping shared with the site.

## Special handling
Every decision-table outcome that changed the .tex: wrap counts, glued
chains, docstring treatment, token \allowbreak counts, table treatment,
TOC .toc edits (rule 9), Unicode fallbacks (or "all covered").

## Verification
Gate 4 numbers (worst residual hbox + why it is harmless) and the Gate 5
battery result over all pages.

## Expected warnings
checkdocs / warnonly inherited from docs/make.jl; what the resolve pass
actually emitted.

## Reproducing
The exact commands; where the build bundle is archived; the reminder that
content changes regenerate from docs/src, never by editing the LaTeX.
```

---

## Appendix A — package-specific knobs to revisit on each new package

- **Julia version and binary deps** — from `[compat]` and whatever `using
  <Package>` needs (BinaryBuilder artifacts usually just work; system libs
  may not).
- **Documenter plugins** — DocumenterCitations needs its `.bib` and style in
  the LaTeX build; Literate/DemoCards must run *before* `makedocs`; Mermaid
  and other HTML-only diagram plugins need static image replacement.
- **Pre-build generation steps** — pages copied or generated by `make.jl`
  (reports, changelogs) must run identically in `make_latex.jl`.
- **Geometry and page budget** — recompute whenever paper size, margins, or
  fonts change; all fit-vs-wrap decisions depend on it.
- **The unbreakable-paragraph rule** — safe for typical documentation prose;
  a package whose docs contain page-length paragraphs will hit `Overfull
  \vbox`, which is the signal to exempt that paragraph (locally reset
  `\interlinepenalty`) rather than weaken the global rule.
- **Global minted hook** — only when the survey shows every code block fits a
  page; otherwise wrap selectively.
- **`@example`/doctest output** — executes on the build machine; outputs that
  embed timings, paths, or RNG draws differ between runs. Acceptable for a
  PDF snapshot; note it if reproducibility matters.
- **TOC size** — a package with very many chapters or deep nesting may need
  `\setcounter{tocdepth}` tuning before the rule-9 check is even meaningful;
  decide the depth first, then validate blocks at that depth.

## Appendix B — failure modes already encountered once (don't rediscover them)

- Installing Julia before reading `[compat]`.
- `\preto`/`\appto` on a parameterized class-internal macro (`\l@section`) —
  splices code ahead of the parameter text, and the corruption erupts one
  full compile later, at `.toc` execution. Inspect with `\show` first; use
  `\pretocmd`/`\patchcmd` with a loud failure branch; catch it in seconds
  with the Stage 3.8 preamble probe.
- Long inline `\texttt` tokens (URLs, call chains) treated as a code-block
  problem — `breaklines` never applies to inline mono; they need the survey
  row + intra-token `\allowbreak` transform, not the compile loop.
- A validator threshold invented independently of the doctrine's numbers —
  it flags render-verified-harmless residues (or misses real ones) until the
  two are reconciled to a single stated constant.
- Trusting a warm latexmk state (empty TOC that "compiled fine").
- `%` or anything else on the `\end{minted}` line (fancyvrb error).
- Consecutive unbreakable boxes with no breakable glue between them — one
  4016 pt `Overfull \vbox` from a stack of docstring minipages (rule 8).
- Editing the `.toc` and then re-running latexmk, which regenerates it — the
  rule-9 remediation needs a single direct `xelatex` pass after fixpoint.
- Text edits via unasserted regex/sed — a pattern that no longer matches
  fails silently; always assert match counts against the survey.
- A batch-edit pattern written from memory of the code instead of a grep of
  it, anchored on incidental syntax (a separator before the target kwarg) —
  matched 2 of 8 real sites; the pre-count + semantic-anchor rule in
  "Maintaining the pipeline itself" exists because of this.
- A build chain launched with bare shell `&` from a foreground command —
  orphaned and killed with its parent, leaving a zero-byte log; and its
  dependent patch step wasn't `&&`-gated, so it would have run against
  unpatched sources anyway. Managed background + failure-gating + the
  sentinel-line contract are the fix.
- "Large font" heading detection without calibrating against fontspec's
  scaled sizes.
- Treating every code-background band at a page boundary as a violation —
  adjacent independent blocks may legally break there; check the source.
- Table-cell `Overfull \hbox` warnings that never reach the page margin —
  verify against the render before "fixing" readability away.
- All gates green ≠ pleasing: correctness checks cannot see visual rhythm.
  Without the page-fill metric and the changed-pages visual diff, aesthetic
  regressions ship silently and full-document eyeballing decays to never.
- Probing (or compiling) outside the real build's working directory — the
  minted cache, aux state, and relative `\usepackage{./...}` paths are part
  of the build context; a probe in a fresh directory fails for reasons the
  real document does not have.
- Right-aligned (`R`) tabulary prose columns — they defeat hyphenation and
  inflate minimum column widths; use `L`.

## Appendix C — worked example: SmallFloats.jl 0.1.0 (2026-07-24 build)

The decision table as it came out for a real 11-page docs tree → 65-page
Letter PDF, from that build's note:

| Survey finding | Decision taken |
|---|---|
| 11 one-chapter `\part`s, titles matching | flattened to chapters |
| 8 duplicate labels, none link targets | uniquified, no reference patching |
| 161 code blocks, all ≤ 45-line budget | globally unbreakable minted hook |
| 27 whitespace-adjacent block chains | all glued (each fit the budget) |
| 73 colon-introduced blocks | glued to their introducing paragraph |
| 116 docstrings, all within budget | wrapped whole; breakable glue between them added after a 4016 pt stacked-box overflow |
| 11 tabulary tables | prose columns R → L; each kept whole at footnotesize |
| 284 escaped underscores, 34 slash-joined `\texttt` pairs | `\allowbreak` inserted, counts asserted |
| one paragraph with two 23-char camelCase tokens | local `\emergencystretch` |
| TOC block for one chapter split across contents pages ii/iii | `\newpage` written into the `.toc` before that chapter (rule 9) |
| 62 non-ASCII characters, all in DejaVu coverage | no fallback mappings |

Verification on that build: Gate 4 clean with worst residual `Overfull \hbox`
5.98 pt (absorbed by intercolumn space, confirmed on the render); Gate 5
clean over all 65 pages. The point of the example: **every row is a
measurement paired with a conditional decision** — on a different package, or
after this package's docs change (e.g. adding a table-heavy Benchmarks page),
the measurements change and the decisions must be re-derived, not reused.
