# pandoc markdown -> PDF for every planning / notes document here.
# Wider text block than the LaTeX default so the tables fit; A4 or letter
# is left to the TeX installation's default paper.
# pandoc/pdf.lua adds pandoc/header.tex to the preamble (Unicode symbols that
# pdflatex lacks, wrapped code blocks) and lets long inline code wrap inside
# tables and paragraphs.
PANDOC_SUPPORT = pandoc/pdf.lua pandoc/header.tex
PANDOC_FLAGS = --pdf-engine=pdflatex -V geometry:margin=0.45in -V fontsize=12pt --lua-filter=pandoc/pdf.lua

DOCS = plan_v2.pdf plan_v2b.pdf plan_v2c.pdf plan_v2c_audit.pdf
SBCL ?= sbcl
RESULTS_DIR = intermediate_results

.PHONY: all clean

all: $(DOCS)

figures/%.pdf: figures/%.dot
	dot -Tpdf $< -o $@

%.pdf: %.md $(PANDOC_SUPPORT)
	pandoc $< -o $@ $(PANDOC_FLAGS)

clean:
	rm -f $(DOCS) figures/*.pdf
