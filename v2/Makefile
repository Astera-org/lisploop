SBCL ?= sbcl
SHELL := /bin/bash
BASELINES_DIR := ../baselines
RESULTS_DIR := gates/results

.PHONY: all test baselines baselines-full baseline-x1 baseline-x2 baseline-x3 x1 x2 x3 x3-quick gates clean

all: test

# The contracts of the store core and of the synthesizer. Under a second.
test:
	$(SBCL) --noinform --script tests/run.lisp

# Regenerate the recorded v1/Stage-0 baseline data files in ../baselines/ (verified by SHA256SUMS).
baselines:
	$(MAKE) -C $(BASELINES_DIR)

baselines-full:
	$(MAKE) -C $(BASELINES_DIR) full

baseline-x1:
	@$(MAKE) --no-print-directory -C $(BASELINES_DIR) x1

baseline-x2:
	@$(MAKE) --no-print-directory -C $(BASELINES_DIR) x2

baseline-x3:
	@$(MAKE) --no-print-directory -C $(BASELINES_DIR) x3

$(RESULTS_DIR):
	mkdir -p $@

# The gates of plan_v2c.md section 11.2. Each compares this kernel with the baseline in
# ../baselines/ (building it if absent), and writes what it prints to gates/results/.
x1: baseline-x1 | $(RESULTS_DIR)
	set -o pipefail; $(SBCL) --noinform --dynamic-space-size 8000 --script gates/x1.lisp | tee $(RESULTS_DIR)/x1.txt

x2: baseline-x2 | $(RESULTS_DIR)
	set -o pipefail; $(SBCL) --noinform --dynamic-space-size 4000 --script gates/x2.lisp | tee $(RESULTS_DIR)/x2.txt

# About four minutes, and up to 20 GB of heap for the run at a billion cells.
x3: baseline-x3 | $(RESULTS_DIR)
	set -o pipefail; $(SBCL) --noinform --dynamic-space-size 20000 --script gates/x3.lisp | tee $(RESULTS_DIR)/x3.txt

# The gate's own run only, without the budget ladder, the ablations and the size-order section.
x3-quick: baseline-x3
	$(SBCL) --noinform --dynamic-space-size 20000 --script gates/x3.lisp quick

gates: x1 x2 x3

# Remove gate results and all generated baseline data, logs, and scratch copies.
clean:
	rm -rf $(RESULTS_DIR)
	$(MAKE) -C $(BASELINES_DIR) clean
