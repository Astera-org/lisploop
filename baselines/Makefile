SBCL ?= sbcl
REPO := $(abspath ..)
X3_BASE_COMMIT ?= 65d1df2

.PHONY: all x1 x2 x3 rebuild-x1 rebuild-x2 rebuild-x3 full full-x1 full-x2 full-x3 clean

# Regenerate the baseline data files read by v2/gates/ and verify against recorded SHA-256 sums.
all: x1 x2 x3

x1:
	@(cd x1 && sha256sum -c --quiet x1-SHA256SUMS >/dev/null 2>&1) || $(MAKE) --no-print-directory rebuild-x1

x2:
	@(cd x2 && sha256sum -c --quiet x2-SHA256SUMS >/dev/null 2>&1) || $(MAKE) --no-print-directory rebuild-x2

x3:
	@(cd x3 && sha256sum -c --quiet x3-SHA256SUMS >/dev/null 2>&1) || $(MAKE) --no-print-directory rebuild-x3

rebuild-x1:
	@set -eu; \
	W="$$PWD/x1"; \
	LOG="$$(mktemp)"; \
	trap 'rc=$$?; if [ "$$rc" -ne 0 ]; then cat "$$LOG" >&2; fi; rm -rf "$$W/v1" "$$LOG"' EXIT; \
	rm -rf "$$W/v1"; \
	cp -r "$(REPO)/v1" "$$W/v1"; \
	X1_V1="$$W/v1" X1_OUT="$$W" $(SBCL) --dynamic-space-size 8192 --non-interactive --no-userinit --no-sysinit \
		--load "$$W/x1-baseline.lisp" >"$$LOG" 2>&1; \
	( cd "$$W" && sha256sum -c --quiet x1-SHA256SUMS ); \
	echo "baselines/x1: verified"

rebuild-x2:
	@set -eu; \
	W="$$PWD/x2"; \
	LOG="$$(mktemp)"; \
	trap 'rc=$$?; if [ "$$rc" -ne 0 ]; then cat "$$LOG" >&2; fi; rm -rf "$$W/v1" "$$W/source-commit.txt" "$$W/source-sha256.txt" "$$LOG"' EXIT; \
	REPO="$(REPO)" bash "$$W/copy-v1.sh" >"$$LOG" 2>&1; \
	$(SBCL) --dynamic-space-size 4096 --noinform --non-interactive --load "$$W/x2-dump.lisp" >>"$$LOG" 2>&1; \
	( cd "$$W" && sha256sum -c --quiet x2-SHA256SUMS ); \
	echo "baselines/x2: verified"

rebuild-x3:
	@set -eu; \
	W="$$PWD/x3"; \
	VR="$(REPO)/plan_v2c_audit/verify-review"; \
	LOG="$$(mktemp)"; \
	trap 'rc=$$?; if [ "$$rc" -ne 0 ]; then cat "$$LOG" >&2; fi; rm -rf "$$W/boot" "$$W/kernel" "$$LOG"' EXIT; \
	rm -rf "$$W/boot" "$$W/kernel"; \
	mkdir -p "$$W/boot" "$$W/kernel"; \
	git -C "$(REPO)" archive "$(X3_BASE_COMMIT)" v2 | tar -x -C "$$W/kernel"; \
	cp -a "$$W/kernel/v2" "$$W/boot/v2"; \
	patch -s "$$W/boot/v2/bootstrap/build-batteries.lisp" "$$W/bootstrap-instrumentation.diff"; \
	( cd "$$W/boot/v2" && $(SBCL) --script bootstrap/build-batteries.lisp ) >"$$LOG" 2>&1; \
	( cd "$$VR" && $(SBCL) --dynamic-space-size 4096 --noinform --non-interactive \
		--load tg-probe-r1.lisp --load r1-spec.lisp --load "$$W/heldout-dump.lisp" \
		--out "$$W/x3-heldout.lisp" --src "$$VR/r1-spec.lisp" ) >>"$$LOG" 2>&1; \
	X3_V2_ROOT="$$W/kernel/v2/" X3_WORK="$$W/" $(SBCL) --dynamic-space-size 4096 --noinform --non-interactive \
		--load "$$W/analyze-rows.lisp" >>"$$LOG" 2>&1; \
	X3_V2_ROOT="$$W/kernel/v2/" X3_WORK="$$W/" $(SBCL) --dynamic-space-size 4096 --noinform --non-interactive \
		--load "$$W/dump-specs.lisp" >>"$$LOG" 2>&1; \
	X3_V2_ROOT="$$W/kernel/v2/" X3_WORK="$$W/" $(SBCL) --dynamic-space-size 4096 --noinform --non-interactive \
		--load "$$W/dump-prereqs.lisp" >>"$$LOG" 2>&1; \
	( cd "$$W" && sha256sum -c --quiet x3-SHA256SUMS ); \
	echo "baselines/x3: verified"

# Full reproduction suites (including memory measurements, extra diagnostics, harness runs, and logs).
full: full-x1 full-x2 full-x3

full-x1:
	REPO="$(REPO)" bash x1/run-baseline.sh | tee x1/run-baseline.out
	bash x1/x1-named-laws.sh > x1/x1-named-laws.log

full-x2:
	mkdir -p x2/logs
	REPO="$(REPO)" bash x2/run-baseline.sh | tee x2/logs/run-baseline.out

full-x3:
	@set -eu; \
	W="$$PWD/x3"; \
	trap 'rm -rf "$$W/boot" "$$W/kernel" "$$W/vr"' EXIT; \
	REPO="$(REPO)" X3_BASE_COMMIT="$(X3_BASE_COMMIT)" sh "$$W/setup.sh"; \
	REPO="$(REPO)" X3_BASE_COMMIT="$(X3_BASE_COMMIT)" sh "$$W/setup-boot.sh"; \
	sh "$$W/run-boot.sh"; \
	sh "$$W/run-heldout.sh" | tee "$$W/logs/run-heldout.out"; \
	bash "$$W/run-lisp.sh" show-boot.lisp show-boot; \
	bash "$$W/run-lisp.sh" analyze-rows.lisp analyze-rows; \
	bash "$$W/run-lisp.sh" dump-specs.lisp dump-specs; \
	bash "$$W/run-lisp.sh" dump-prereqs.lisp dump-prereqs; \
	bash "$$W/run-lisp.sh" probe-primitives.lisp probe-primitives; \
	bash "$$W/run-check-plain.sh"; \
	sh "$$W/run-stage0-unmodified.sh"; \
	bash "$$W/run-prototype.sh"; \
	bash "$$W/run-all-harness.sh" | tee "$$W/logs/run-all-harness.out"; \
	( cd "$$W" && sha256sum -c --quiet x3-SHA256SUMS )

# Remove every generated baseline data file, log, output, and scratch copy.
clean:
	rm -rf x1/v1 x1/*.log x1/*.out x1/*.txt x1/*.sexp
	rm -rf x2/v1 x2/proto-copy x2/logs \
		x2/source-commit.txt x2/source-sha256.txt \
		x2/x2-candidates.txt x2/x2-match-table.tsv \
		x2/x2-solvers.sexp x2/x2-solvers.txt
	rm -rf x3/boot x3/kernel x3/vr x3/logs x3/results \
		x3/boot-specs.sexp x3/x3-row-analysis.sexp \
		x3/x3-specs.lisp x3/x3-heldout.lisp x3/x3-prerequisites.lisp
