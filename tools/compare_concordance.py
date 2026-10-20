#!/usr/bin/env python3
"""Compare two resistanceSummaries.csv files drug by drug.

Supports the concordance exercise in VAL-HIVDR-001 section 8: does the local
interpretation agree with the Stanford reference for every drug of every
sequence?

    python3 tools/compare_concordance.py \\
        --reference data/manual_quering/resistanceSummaries.csv \\
        --test      data/test_data/resistanceSummaries.csv

Reports per-drug level-code concordance, highlights any difference that
crosses the susceptible / non-susceptible boundary, and gives the 95% upper
confidence bound on the discordance rate.

IMPORTANT: both files must have been produced by the SAME HIVdb algorithm
version. The tool refuses to proceed otherwise unless --allow-version-
mismatch is given, because differing versions produce genuine algorithm
differences that are not implementation faults and would invalidate the
exercise.
"""

import argparse
import csv
import sys
from pathlib import Path

DRUGS = ["ATV/r", "DRV/r", "FPV/r", "IDV/r", "LPV/r", "NFV", "SQV/r", "TPV/r",
         "ABC", "AZT", "D4T", "DDI", "FTC", "3TC", "TDF",
         "DOR", "EFV", "ETR", "NVP", "RPV",
         "BIC", "CAB", "DTG", "EVG", "RAL"]

LEVEL_NAME = {
    "1": "Susceptible", "2": "Potential Low-Level", "3": "Low-Level",
    "4": "Intermediate", "5": "High-Level",
}


def load(path):
    with open(path, encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        sys.exit(f"error: no rows in {path}")
    return {r["Sequence Name"].strip(): r for r in rows}


def algorithm_of(rows):
    versions = {(r.get("Algorithm Name", ""), r.get("Algorithm Version", ""),
                 r.get("Algorithm Date", "")) for r in rows.values()}
    return versions


def normalise(value):
    """Absent and Stanford's literal "NA" both mean the gene was not
    genotyped. The website export keeps the columns and writes "NA"; the
    local adapter omits the columns. Same meaning, different encoding, so
    neither is a discordance."""
    if value is None:
        return ""
    value = value.strip()
    return "" if value.upper() == "NA" else value


def susceptible(level):
    return level == "1"


def main():
    ap = argparse.ArgumentParser(description="drug-by-drug concordance check")
    ap.add_argument("--reference", required=True,
                    help="Stanford website export (the reference)")
    ap.add_argument("--test", required=True,
                    help="pipeline output to be checked")
    ap.add_argument("--allow-version-mismatch", action="store_true",
                    help="compare even if the algorithm versions differ. The "
                         "result is then a measure of the version difference, "
                         "NOT a concordance result.")
    ap.add_argument("--out", help="write the per-difference detail to CSV")
    args = ap.parse_args()

    ref, test = load(args.reference), load(args.test)

    ref_alg, test_alg = algorithm_of(ref), algorithm_of(test)
    print(f"Reference : {args.reference}")
    for a in sorted(ref_alg):
        print(f"            algorithm {a[0]} {a[1]} ({a[2]})")
    print(f"Test      : {args.test}")
    for a in sorted(test_alg):
        print(f"            algorithm {a[0]} {a[1]} ({a[2]})")
    print()

    versions_match = ref_alg == test_alg
    if not versions_match:
        if not args.allow_version_mismatch:
            sys.exit(
                "error: the two files were scored with different HIVdb "
                "algorithm versions.\n"
                "A comparison across versions measures algorithm change, not "
                "implementation concordance, and cannot be used as evidence "
                "for VAL-HIVDR-001 section 8.\n"
                "Re-run the pipeline with the matching algorithm, or pass "
                "--allow-version-mismatch to quantify the version difference "
                "instead."
            )
        print("*** ALGORITHM VERSIONS DIFFER ***")
        print("This is a measure of the VERSION DIFFERENCE, not a concordance")
        print("result. It is not valid evidence for VAL-HIVDR-001 section 8.\n")

    only_ref = sorted(set(ref) - set(test))
    only_test = sorted(set(test) - set(ref))
    if only_ref:
        print(f"in reference only : {', '.join(only_ref)}")
    if only_test:
        print(f"in test only      : {', '.join(only_test)}")
    shared = sorted(set(ref) & set(test))
    if not shared:
        sys.exit("error: no sequence names in common")

    compared = 0
    skipped = 0
    diffs = []
    for name in shared:
        for drug in DRUGS:
            key = f"{drug} Level"
            r = normalise(ref[name].get(key))
            t = normalise(test[name].get(key))
            # A drug not genotyped in both is not a comparison; not
            # genotyped in only one of them is a real difference.
            if r == "" and t == "":
                skipped += 1
                continue
            compared += 1
            if r != t:
                diffs.append({
                    "sequence": name, "drug": drug,
                    "reference_level": r or "(not genotyped)",
                    "test_level": t or "(not genotyped)",
                    "reference_label": LEVEL_NAME.get(r, r or "(not genotyped)"),
                    "test_label": LEVEL_NAME.get(t, t or "(not genotyped)"),
                    "reference_score": ref[name].get(f"{drug} Score", ""),
                    "test_score": test[name].get(f"{drug} Score", ""),
                    "crosses_susceptibility": (
                        "YES" if susceptible(r) != susceptible(t) else "no"),
                })

    n_seq = len(shared)
    n_diff = len(diffs)
    critical = [d for d in diffs if d["crosses_susceptibility"] == "YES"]

    print(f"sequences compared        : {n_seq}")
    print(f"drug-level comparisons    : {compared}")
    print(f"not genotyped in either    : {skipped}")
    print(f"differences               : {n_diff}")
    print(f"  crossing susceptibility : {len(critical)}")
    if compared:
        pct = 100.0 * (compared - n_diff) / compared
        print(f"level-code concordance    : {pct:.3f}%")

    if diffs:
        print("\nDifferences:")
        print(f"  {'sequence':16} {'drug':7} "
              f"{'reference':28} {'test':28} crosses")
        for d in diffs:
            ref_s = f"{d['reference_label']} ({d['reference_score']})"
            test_s = f"{d['test_label']} ({d['test_score']})"
            flag = "  <-- CLINICAL CATEGORY" if d["crosses_susceptibility"] == "YES" else ""
            print(f"  {d['sequence']:16} {d['drug']:7} "
                  f"{ref_s:28} {test_s:28}{flag}")

    if n_diff == 0 and compared:
        # Rule of three: with zero events in n trials the 95% upper bound on
        # the rate is about 3/n. Quoted per sequence as well as per drug
        # because the 25 drugs within a sequence are not independent.
        print(f"\n95% upper bound on discordance (rule of three):")
        print(f"  per sequence : {3.0 / n_seq * 100:.2f}%  (n={n_seq})")
        print(f"  per drug     : {3.0 / compared * 100:.3f}%  (n={compared})"
              f"  -- drugs within a sequence are correlated, so treat the")
        print(f"                 per-sequence bound as the defensible figure")

    if args.out and diffs:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=list(diffs[0].keys()))
            w.writeheader()
            w.writerows(diffs)
        print(f"\nwrote {out}")

    print()
    if not versions_match:
        print("RESULT: version comparison only -- not a concordance result.")
        sys.exit(0)
    if critical:
        print("RESULT: FAIL -- differences cross the susceptibility boundary.")
        sys.exit(1)
    if diffs:
        print("RESULT: FAIL -- level codes are not 100% concordant.")
        sys.exit(1)
    print("RESULT: PASS -- 100% level-code concordance.")
    sys.exit(0)


if __name__ == "__main__":
    main()
