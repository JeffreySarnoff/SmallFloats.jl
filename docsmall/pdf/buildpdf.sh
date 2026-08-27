#!/usr/bin/env bash
# docsmall/pdf/buildpdf.sh — the compact manual's PDF pipeline.
#
# Same stages as docs/pdf/buildpdf.sh, and deliberately the same *code* where
# it matters: the survey/transform and validation stages are the full
# manual's docs/pdf/transform.py and docs/pdf/validate.py, invoked by path —
# argument-driven scripts, so nothing is forked to drift. Only this thin
# orchestrator differs: source dir, build dir, artifact name.
#
# Success sentinel: "buildpdf.sh: done — ..."; failure prints
# "buildpdf.sh: FAILED ..."; a log with neither means killed/not-run.
set -euo pipefail
trap 'echo "buildpdf.sh: FAILED at line $LINENO (see the stage banner above)" >&2' ERR

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PDFDIR="$ROOT/docsmall/pdf"
TOOLS="$ROOT/docs/pdf"          # shared transform/validate machinery
BUILD="$PDFDIR/build"
cd "$ROOT"

echo "== Stage 1: resolve (Documenter LaTeX writer) =="
julia --project=docsmall docsmall/make_latex.jl

echo "== Stages 2+3: survey + transform =="
rm -rf "$BUILD"
PYTHONIOENCODING=utf-8 python3 "$TOOLS/transform.py" "$ROOT/docsmall/build_latex" "$BUILD"

# PATH guards, identical to docs/pdf/buildpdf.sh (see the discussion there):
# minted's helper must match minted.sty and only PATH order can select it,
# because MiKTeX's \ShellEscape scrubs the environment; and a non-PDF `qpdf`
# can shadow the real one.
_LM313="$APPDATA/Python/Python313/Scripts"
if [ -x "$_LM313/latexminted.exe" ]; then
    export PATH="$_LM313:$PATH"
fi
for _q in "/c/Program Files"/qpdf*/bin "$PROGRAMFILES"/qpdf*/bin; do
    if [ -x "$_q/qpdf.exe" ] && "$_q/qpdf.exe" --version >/dev/null 2>&1; then
        export PATH="$_q:$PATH"
        break
    fi
done

echo "== Stage 3.8: preamble probe =="
cd "$BUILD"
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
xelatex -shell-escape -interaction=nonstopmode probe.tex > /dev/null 2>&1 || true
if ! xelatex -shell-escape -interaction=nonstopmode probe.tex > /dev/null 2>&1 \
   || [ "$(grep -c '^!' probe.log)" -ne 0 ]; then
  grep -m5 -A3 '^!' probe.log || true
  echo "buildpdf.sh: preamble probe FAILED"
  exit 1
fi
rm -f probe.*
echo "probe clean"

echo "== Stage 4: compile (clean state) =="
rm -f main.pdf main.aux main.toc main.out main.fdb_latexmk
latexmk -xelatex -shell-escape -interaction=nonstopmode -halt-on-error main.tex \
  > latexmk.stdout 2>&1 || { tail -40 latexmk.stdout; echo "buildpdf.sh: latexmk failed"; exit 1; }

VBOX=$(grep -c "^Overfull \\\\vbox" main.log || true)
MISSCHAR=$(grep -c "^Missing character" main.log || true)
MULTIDEF=$(grep -c "multiply defined" main.log || true)
if [ "$VBOX" -ne 0 ] || [ "$MISSCHAR" -ne 0 ] || [ "$MULTIDEF" -ne 0 ]; then
  grep -m5 -A2 "^Overfull \\\\vbox\|^Missing character\|multiply defined" main.log || true
  echo "buildpdf.sh: Gate 4 FAILED (vbox=$VBOX missing-char=$MISSCHAR multiply-defined=$MULTIDEF)"
  exit 1
fi
[ -s main.toc ] || { echo "buildpdf.sh: empty main.toc (stale aux state?)"; exit 1; }
# `|| true`: a log with ZERO overfull hboxes makes the grep exit nonzero, and
# under pipefail that would fail the build precisely when the layout is at its
# cleanest. (Found by this manual's first build, which had none.)
WORST_HBOX=$(grep "^Overfull \\\\hbox" main.log | sed 's/[^0-9.]*\([0-9.]*\)pt.*/\1/' | sort -rn | head -1 || true)
echo "Gate 4 clean (worst residual Overfull hbox: ${WORST_HBOX:-0}pt)"

echo "== Stage 5: validate =="
# Manifest optional: absent on the very first build, persisted afterwards so
# check 10 (visual diff) has a baseline from the second build on.
if [ -f "$PDFDIR/render_manifest.json" ]; then
  python3 "$TOOLS/validate.py" "$BUILD" main.pdf "$PDFDIR/render_manifest.json"
else
  python3 "$TOOLS/validate.py" "$BUILD" main.pdf
fi

echo "== Stage 6: package =="
OUT="$PDFDIR/SmallFloatsCompact.pdf"
cp main.pdf "$OUT"
cp render_manifest.json "$PDFDIR/render_manifest.json"
PAGES=$(pdfinfo main.pdf | awk '/^Pages:/{print $2}')

echo "buildpdf.sh: done — $OUT ($PAGES pages)"
