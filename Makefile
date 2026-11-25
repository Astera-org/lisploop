# pandoc markdown -> PDF for every planning / notes document here.
# Wider text block than the LaTeX default so the tables fit; A4 or letter
# is left to the TeX installation's default paper.
# pandoc/pdf.lua adds pandoc/header.tex to the preamble (Unicode symbols that
# pdflatex lacks, wrapped code blocks) and lets long inline code wrap inside
# tables and paragraphs.
PANDOC_SUPPORT = pandoc/pdf.lua pandoc/header.tex
PANDOC_FLAGS = --pdf-engine=pdflatex -V geometry:margin=0.45in -V fontsize=12pt --lua-filter=pandoc/pdf.lua

DOCS = plan_v2.pdf plan_v2b.pdf plan_v2c.pdf plan_v2c_audit.pdf plan8.pdf plan9.pdf architecture2.pdf batteries-and-reflection.pdf tests/README.pdf plan7/plan7-recursion.pdf plan7/plan7-higher-order.pdf plan7/plan7-library.pdf plan7/plan7-m9-policy.pdf
SBCL ?= sbcl
RESULTS_DIR = intermediate_results
BENCHMARK_SECONDS ?= 300
BENCHMARK_SOURCES = load.lisp package.lisp ast.lisp knowledge.lisp codec.lisp vm.lisp evidence.lisp persistence.lisp requirements.lisp frame.lisp enumerate.lisp unify.lisp fibers.lisp laws.lisp templates.lisp condense.lisp abstraction.lisp descriptors.lisp relations.lisp synthesize.lisp nogoods.lisp decompose.lisp proposals.lisp consolidate.lisp messages.lisp explain.lisp milestones/load.lisp milestones/corpus.lisp milestones/views.lisp milestones/algebra-discovery.lisp milestones/propagation-search.lisp milestones/dependency-search.lisp benchmark.lisp

.PHONY: all clean bootstrap test test-kernel test-milestones benchmark benchmark-profile

all: $(DOCS)

bootstrap:
	$(SBCL) --script bootstrap/build-batteries.lisp

test-kernel:
	$(SBCL) --script tests/run.lisp kernel

test-milestones:
	$(SBCL) --script tests/run.lisp milestones

test: test-kernel test-milestones

$(RESULTS_DIR):
	mkdir -p $@

# Each invocation starts fresh processes and replaces only the benchmark-* logs.
# Keep runs serial, including when this target is invoked with make -j.
benchmark: | $(RESULTS_DIR)
	@set -eu; \
	for mode in unit batch; do \
		report='$(RESULTS_DIR)'/benchmark-$$mode.txt; \
		printf 'Current kernel, dispatch=%s; three small runs and one large run.\n' "$$mode" > "$$report"; \
		date -u >> "$$report"; \
		uname -sm >> "$$report"; \
		sha256sum $(BENCHMARK_SOURCES) >> "$$report"; \
		for specification in 'linear 61 3' 'quadratic 70 3' 'quartic 77 1'; do \
			set -- $$specification; \
			repetition=1; \
			while [ "$$repetition" -le "$$3" ]; do \
				printf 'Benchmark %s: %s at %s bits, run %s/%s -> %s\n' "$$mode" "$$1" "$$2" "$$repetition" "$$3" "$$report"; \
				printf '\nRun %s/%s\n' "$$repetition" "$$3" >> "$$report"; \
				$(SBCL) --dynamic-space-size 2048 --script benchmark.lisp search "$$1" "$$2" '$(BENCHMARK_SECONDS)' "$$mode" >> "$$report"; \
				awk '/^SEARCH / && !/status=:COMPLETE/ { exit 1 }' "$$report" || { \
					printf 'Benchmark hit a cutoff; see %s\n' "$$report" >&2; exit 1; \
				}; \
				repetition=$$((repetition + 1)); \
			done; \
		done; \
	done
	@printf 'Tariff microbenchmark -> %s/benchmark-meter.txt\n' '$(RESULTS_DIR)'
	@$(SBCL) --dynamic-space-size 2048 --script benchmark.lisp meter > $(RESULTS_DIR)/benchmark-meter.txt

# Profiling is separate so it cannot affect the unprofiled benchmark timings.
benchmark-profile: | $(RESULTS_DIR)
	@$(SBCL) --dynamic-space-size 2048 --script benchmark.lisp search quadratic 70 $(BENCHMARK_SECONDS) batch profile > $(RESULTS_DIR)/benchmark-profile.txt
	@printf 'CPU profile: %s/benchmark-profile.txt\n' '$(RESULTS_DIR)'

plan7/plan7-recursion.pdf: figures/phase3-lifts.pdf
plan8.pdf: figures/smoce-cycle.pdf
batteries-and-reflection.pdf: figures/bootstrap-pipeline.pdf figures/reflective-loop.pdf

figures/%.pdf: figures/%.dot
	dot -Tpdf $< -o $@

%.pdf: %.md $(PANDOC_SUPPORT)
	pandoc $< -o $@ $(PANDOC_FLAGS)

clean:
	rm -f $(DOCS) figures/*.pdf
