# pandoc markdown -> PDF for every planning / notes document here.
# Wider text block than the LaTeX default so the tables fit; A4 or letter
# is left to the TeX installation's default paper.
PANDOC_FLAGS = --pdf-engine=pdflatex -V geometry:margin=0.7in -V fontsize=12pt

DOCS = plan.pdf plan2.pdf plan3.pdf plan4.pdf plan5.pdf plan6.pdf architecture.pdf results.pdf results-history.pdf
SBCL ?= sbcl
RESULTS_DIR = intermediate_results
BENCHMARK_SECONDS ?= 300
BENCHMARK_SOURCES = load.lisp package.lisp ast.lisp codec.lisp vm.lisp frame.lisp enumerate.lisp factor.lisp laws.lisp benchmark.lisp

.PHONY: all clean test m1 m2 m3 m4 m5 m6 m7 visualizer benchmark benchmark-profile

all: $(DOCS)

test:
	$(SBCL) --script tests/run.lisp
	$(SBCL) --script tests/visualizer.lisp

m1: | $(RESULTS_DIR)
	@$(SBCL) --script experiments.lisp m1 > $(RESULTS_DIR)/milestone1.txt
	@printf 'Milestone 1 report: %s/milestone1.txt\n' '$(RESULTS_DIR)'

m2: | $(RESULTS_DIR)
	@$(SBCL) --script experiments.lisp m2 > $(RESULTS_DIR)/milestone2.txt
	@printf 'Milestone 2 report: %s/milestone2.txt\n' '$(RESULTS_DIR)'

m3: | $(RESULTS_DIR)
	@$(SBCL) --script experiments.lisp m3 > $(RESULTS_DIR)/milestone3.txt
	@printf 'Milestone 3 report: %s/milestone3.txt\n' '$(RESULTS_DIR)'

m4: | $(RESULTS_DIR)
	@$(SBCL) --script experiments.lisp m4 > $(RESULTS_DIR)/milestone4.txt
	@printf 'Milestone 4 report: %s/milestone4.txt\n' '$(RESULTS_DIR)'

m5: | $(RESULTS_DIR)
	@$(SBCL) --script experiments.lisp m5 > $(RESULTS_DIR)/milestone5.txt
	@printf 'Milestone 5 report: %s/milestone5.txt\n' '$(RESULTS_DIR)'

m6: | $(RESULTS_DIR)
	@$(SBCL) --script experiments.lisp m6 > $(RESULTS_DIR)/milestone6.txt
	@printf 'Milestone 6 report: %s/milestone6.txt\n' '$(RESULTS_DIR)'

m7: | $(RESULTS_DIR)
	@$(SBCL) --script experiments.lisp m7 > $(RESULTS_DIR)/milestone7.txt
	@printf 'Milestone 7 report: %s/milestone7.txt\n' '$(RESULTS_DIR)'

visualizer:
	$(SBCL) --script visualizer/generate.lisp

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

%.pdf: %.md
	pandoc $< -o $@ $(PANDOC_FLAGS)

clean:
	rm -f $(DOCS)
