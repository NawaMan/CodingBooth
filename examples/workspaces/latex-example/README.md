# LaTeX Example

This example is a small LaTeX paper — sections in separate files, mathematics, a table, a code
listing, and a BibTeX bibliography — set up to build into a PDF with `latexmk`. It is about keeping
the host clean: TeX Live is one of the heaviest toolchains there is, hundreds of megabytes even in a
modest install and over 7 GB in full, and a host-wide install is hard to get rid of afterwards. Here
the whole toolchain lives in the booth, the editor comes with it, and `LATEX_SCHEME` picks how much
of TeX Live the image carries.

**Stack:** TeX Live 2023 (Ubuntu 24.04), latexmk, BibTeX, VS Code in the browser with LaTeX Workshop

## Quick start

```bash
# 1. Launch the booth — opens VS Code in your browser
cd examples/workspaces/latex-example
booth

# 2. Open main.tex and save it: LaTeX Workshop builds main.pdf.
#    Ctrl+Alt+V opens the PDF beside the source; Ctrl+click in the PDF jumps to the line.

# Or build from a terminal (inside the booth, or from the host — the recipes run in the booth)
just --list
just build               # latexmk -pdf main.tex
just watch               # rebuild on every save
just clean               # remove build files, keep main.pdf
```

## What's included

| Component       | Details                                                              |
|-----------------|----------------------------------------------------------------------|
| TeX             | TeX Live 2023, `recommended` scheme (~190 MB installed)             |
| Build           | `latexmk` — runs pdflatex and BibTeX as many times as the document needs |
| Editor          | VS Code in the browser (`codeserver` variant)                        |
| VS Code support | LaTeX Workshop: build on save, PDF preview, SyncTeX                  |
| Sample          | `main.tex`, `sections/*.tex`, `references.bib`                       |

## Choosing a scheme

`LATEX_SCHEME` in `.booth/Boothfile` decides how much of TeX Live goes into the image:

| Scheme        | Installed | Adds                                                        |
|---------------|-----------|-------------------------------------------------------------|
| `basic`       | ~150 MB   | pdflatex, BibTeX, the core classes                          |
| `recommended` | ~190 MB   | hyperref, geometry, booktabs, natbib, listings, microtype   |
| `extra`       | ~380 MB   | TikZ/pgfplots, cleveref, siunitx, biblatex, and most of CTAN |
| `full`        | ~7.4 GB   | everything, every language included                          |

A build that stops with ``File `tikz.sty' not found`` needs a larger scheme. Reconfigure rather than
editing the Boothfile by hand:

```bash
booth config --no-tui --select 'latex:extra' --variant codeserver
```

## A desktop editor instead

Prefer a native LaTeX editor to VS Code? `latex+texstudio` adds TeXstudio on a desktop variant —
its icon lands on the desktop, and F5 builds `main.pdf` (running BibTeX when needed) and shows it
beside the source:

```bash
booth config --no-tui --select 'latex+texstudio' --variant desktop-xfce
booth                    # opens the desktop in your browser; double-click TeXstudio
```
