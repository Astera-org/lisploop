#!/usr/bin/env python3
"""Per-domain ranges of the work columns of x2-match-table.tsv (ledger units per solver)."""
import csv
import os

here = os.path.dirname(os.path.abspath(__file__))
rows = list(csv.DictReader(open(os.path.join(here, "x2-match-table.tsv")), delimiter="\t"))
for domain in ("GF(5)", "GF(7)", "INT"):
    sel = [r for r in rows if r["domain"] == domain]
    relation = [int(r["work_observe_relation"]) for r in sel]
    discover = [int(r["work_discover"]) for r in sel]
    validate = [int(r["work_validate"]) for r in sel]
    both = [d + v for d, v in zip(discover, validate)]
    retained = [int(r["work_two_retained_ledgers"]) for r in sel]
    # the operator is observed once for its two positions
    relation_once = sum(relation[i] for i in range(0, len(sel), 2))
    print(f"{domain}: observe operator {min(relation):,}..{max(relation):,} (once per operator; 4 operators sum {relation_once:,})")
    print(f"   discover+guard {min(discover):,}..{max(discover):,}; validate {min(validate):,}..{max(validate):,}; "
          f"discover+validate {min(both):,}..{max(both):,}")
    print(f"   two retained ledgers {min(retained):,}..{max(retained):,}; sum {sum(retained):,}")
    print(f"   all ledgers, domain total {relation_once + sum(both):,}")
