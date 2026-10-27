# pandoc markdown -> PDF for every planning / notes document here.
# Wider text block than the LaTeX default so the tables fit; A4 or letter
# is left to the TeX installation's default paper.
PANDOC_FLAGS = --pdf-engine=pdflatex -V geometry:margin=0.7in -V fontsize=12pt

DOCS = plan.pdf plan2.pdf plan3.pdf plan4.pdf

all: $(DOCS)

%.pdf: %.md
	pandoc $< -o $@ $(PANDOC_FLAGS)

clean:
	rm -f $(DOCS)
