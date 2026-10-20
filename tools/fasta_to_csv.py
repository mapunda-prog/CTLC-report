#!/usr/bin/env python3
"""FASTA -> HIVdb interpretation -> the two CSVs the R pipeline consumes.

Runs the Stanford HIVdb algorithm locally via sierralocal, so patient-derived
sequences never leave the laboratory network, and writes
sequenceSummaries.csv and resistanceSummaries.csv in the same layout as the
HIVdb website export. The downstream R pipeline is therefore unchanged and
does not need revalidating when this step is introduced.

    python3 tools/fasta_to_csv.py run.fasta --outdir data/raw

Then continue as usual:

    Rscript R/data_prep.R
    Rscript R/render_reports.R

Genes that were not sequenced produce no score or level columns at all, so
the report omits those drug classes rather than printing them as untested.

Exit codes:  0 all sequences interpreted
             1 the run failed outright
             2 interpreted, but one or more sequences were flagged by QC
"""

import argparse
import csv
import json
import shutil
import subprocess
import sys
import tempfile
from collections import OrderedDict
from pathlib import Path

# Drug order per class, matching R/drugs.R and the HIVdb export column order.
DRUG_ORDER = OrderedDict([
    ("PI",    ["ATV/r", "DRV/r", "FPV/r", "IDV/r", "LPV/r", "NFV", "SQV/r", "TPV/r"]),
    ("NRTI",  ["ABC", "AZT", "D4T", "DDI", "FTC", "3TC", "TDF"]),
    ("NNRTI", ["DOR", "EFV", "ETR", "NVP", "RPV"]),
    ("INSTI", ["BIC", "CAB", "DTG", "EVG", "RAL"]),
])

# Which gene each drug class is interpreted from.
CLASS_GENE = {"PI": "PR", "NRTI": "RT", "NNRTI": "RT", "INSTI": "IN"}

GENES = ["PR", "RT", "IN"]

# The algorithm version in force for this laboratory.
#
# This is a PINNED SNAPSHOT of the current HIVdb release, not a moving
# target: the file is fixed in the repository and never fetched at run time.
# Adopting a newer release means replacing this constant deliberately and
# revalidating (VAL-HIVDR-001 section 11), because the version materially
# changes the interpretation reported to clinicians.
#
# sierralocal ships an older default, which this overrides. --xml overrides
# in turn, for the version comparisons in VAL-HIVDR-001 section 8.
PINNED_ALGORITHM = (Path(__file__).resolve().parent.parent
                    / "algorithms" / "HIVDB_10.2.xml")

# Stanford mutation columns, as (csv column, gene, mutationType).
MUTATION_COLUMNS = [
    ("PI Major",        "PR", "Major"),
    ("PI Accessory",    "PR", "Accessory"),
    ("NRTI",            "RT", "NRTI"),
    ("NNRTI",           "RT", "NNRTI"),
    ("INSTI Major",     "IN", "Major"),
    ("INSTI Accessory", "IN", "Accessory"),
]

NONE = "None"

# Every column data_prep.R recognises, in report order. Used to emit a
# metadata template pre-filled with the sequence names from the run.
METADATA_COLUMNS = [
    "sequence_name", "sex", "dob", "age", "sample_collection",
    "sample_received", "received_from", "district", "region",
    "requested_by", "received_by", "pre_gart_vl", "specimen_type",
    "specimen_quality", "art_history", "subtype", "comments", "test_date",
    "tested_by", "authorised_by", "report_date", "reported_by",
    "submitted_to_ctlc_date", "submitted_to_ctlc_by",
]


def run_sierralocal(fasta_paths, json_out, sierralocal="sierralocal", xml=None):
    """Interpret the FASTA files locally and return the parsed JSON."""
    if shutil.which(sierralocal) is None:
        sys.exit(
            f"error: '{sierralocal}' not found on PATH.\n"
            "Install it with:  pip install sierralocal\n"
            "or pass --sierralocal /path/to/sierralocal"
        )

    cmd = [sierralocal, "-o", str(json_out)]
    if xml:
        cmd += ["-xml", str(xml)]
    cmd += [str(p) for p in fasta_paths]

    print("Interpreting locally (no network):", " ".join(cmd), file=sys.stderr)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout)
        sys.stderr.write(proc.stderr)
        sys.exit(f"error: sierralocal exited {proc.returncode}")

    for line in proc.stderr.splitlines():
        if "HIVdb version" in line:
            print(" ", line.strip(), file=sys.stderr)

    with open(json_out, encoding="utf-8") as fh:
        return json.load(fh)


def sequence_name(record):
    """The sequence identifier: the first whitespace-delimited token of the
    FASTA header. Anything after it is a free-text description and must not
    become part of the name, or it will never match a metadata.csv key."""
    header = (record.get("inputSequence") or {}).get("header", "")
    return header.strip().split()[0] if header.strip() else ""


def aligned_genes(record):
    """Map gene name -> (firstAA, lastAA) for the genes actually aligned."""
    out = {}
    for aln in record.get("alignedGeneSequences") or []:
        name = (aln.get("gene") or {}).get("name")
        if name:
            out[name] = (aln.get("firstAA"), aln.get("lastAA"))
    return out


def drug_scores(record):
    """Map displayAbbr -> (score, level) across every gene reported."""
    out = {}
    for block in record.get("drugResistance") or []:
        for item in block.get("drugScores") or []:
            abbr = (item.get("drug") or {}).get("displayAbbr")
            if abbr:
                out[abbr] = (item.get("score"), item.get("level"))
    return out


def mutations_by(record, gene, mutation_type):
    """Comma-joined mutations of one type in one gene, or 'None'."""
    hits = []
    for aln in record.get("alignedGeneSequences") or []:
        if (aln.get("gene") or {}).get("name") != gene:
            continue
        for mut in aln.get("mutations") or []:
            if mut.get("primaryType") == mutation_type:
                hits.append(mut.get("text", ""))
    return ",".join(h for h in hits if h) or NONE


def algorithm_info(record):
    for block in record.get("drugResistance") or []:
        version = block.get("version") or {}
        if version.get("text"):
            return version.get("text"), version.get("publishDate", "")
    return "", ""


def qc_flags(record, present_genes, min_pr=60, min_rt=200, min_in=200):
    """Collect QC concerns. Advisory -- a flagged sequence is still written,
    so a reviewer decides, but the run exits 2 so it cannot pass silently."""
    flags = []

    for note in record.get("validationResults") or []:
        level = note.get("level", "")
        message = note.get("message", str(note))
        flags.append(f"{level}: {message}" if level else str(message))

    if not present_genes:
        flags.append("no HIV pol gene could be aligned")

    aligned = aligned_genes(record)
    minimums = {"PR": min_pr, "RT": min_rt, "IN": min_in}
    for gene, (first, last) in aligned.items():
        if first is None or last is None:
            continue
        covered = last - first + 1
        floor = minimums.get(gene)
        if floor and covered < floor:
            flags.append(
                f"{gene} coverage {covered} aa is below the {floor} aa minimum"
            )

    for aln in record.get("alignedGeneSequences") or []:
        gene = (aln.get("gene") or {}).get("name", "?")
        muts = aln.get("mutations") or []
        if any(m.get("hasStop") for m in muts):
            flags.append(f"{gene} contains a stop codon")
        apobec = sum(1 for m in muts if m.get("isApobecMutation"))
        if apobec >= 2:
            flags.append(
                f"{gene} has {apobec} APOBEC-context mutations "
                "(possible hypermutation)"
            )
        if any(m.get("isApobecDRM") for m in muts):
            flags.append(f"{gene} has an APOBEC-context drug-resistance mutation")

    if not (record.get("subtypeText") or "").strip():
        flags.append("subtype could not be determined")

    return flags


def build_rows(records):
    """Turn sierralocal records into the two CSV row sets.

    Columns for a gene that no sequence covered are omitted entirely, which
    is what makes the downstream report drop that drug class.
    """
    present_genes = set()
    for rec in records:
        present_genes |= set(aligned_genes(rec))

    active_classes = [c for c in DRUG_ORDER if CLASS_GENE[c] in present_genes]
    gene_order = [g for g in GENES if g in present_genes]

    seq_rows, res_rows, qc_rows = [], [], []

    for rec in records:
        name = sequence_name(rec)
        aligned = aligned_genes(rec)
        scores = drug_scores(rec)
        version, pub_date = algorithm_info(rec)
        genes_here = [g for g in GENES if g in aligned]

        seq = OrderedDict()
        seq["Sequence Name"] = name
        seq["Genes"] = ",".join(genes_here)
        for gene in gene_order:
            first, last = aligned.get(gene, ("", ""))
            seq[f"{gene} Start"] = first if first is not None else ""
            seq[f"{gene} End"] = last if last is not None else ""
        seq["Subtype (%)"] = rec.get("subtypeText", "")
        seq_rows.append(seq)

        res = OrderedDict()
        res["Sequence Name"] = name
        res["Genes"] = ",".join(genes_here)
        for column, gene, mutation_type in MUTATION_COLUMNS:
            if gene in present_genes:
                res[column] = (mutations_by(rec, gene, mutation_type)
                               if gene in aligned else NONE)
        for cls in active_classes:
            for abbr in DRUG_ORDER[cls]:
                score, level = scores.get(abbr, ("", ""))
                res[f"{abbr} Score"] = "" if score is None else score
                res[f"{abbr} Level"] = "" if level is None else level
        res["Algorithm Name"] = "HIVDB"
        res["Algorithm Version"] = version
        res["Algorithm Date"] = pub_date
        res_rows.append(res)

        flags = qc_flags(rec, genes_here)
        qc_rows.append(OrderedDict([
            ("Sequence Name", name),
            ("Genes", ",".join(genes_here)),
            ("Subtype", rec.get("subtypeText", "")),
            ("Algorithm Version", version),
            ("QC Status", "REVIEW" if flags else "PASS"),
            ("QC Notes", "; ".join(flags)),
        ]))

    return seq_rows, res_rows, qc_rows


def write_metadata_template(path, names, overwrite=False):
    """Write a metadata.csv skeleton with the sequence names already filled.

    Transcribing CTC IDs by hand is the easiest way to break the join
    between a result and its patient, so the names are carried straight
    across from the FASTA. Every other field is left blank for the
    laboratory to complete.

    Refuses to overwrite an existing file: that file may hold the patient
    details someone has already typed in.
    """
    if path.exists() and not overwrite:
        print(f"  kept existing {path} (use --force-metadata-template to "
              f"replace it)", file=sys.stderr)
        return False

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=METADATA_COLUMNS)
        writer.writeheader()
        for name in names:
            writer.writerow({"sequence_name": name})
    print(f"  wrote {path} -- {len(names)} row(s), patient fields blank",
          file=sys.stderr)
    return True


def write_csv(path, rows):
    if not rows:
        sys.exit(f"error: nothing to write to {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"  wrote {path}", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(
        description="FASTA -> local HIVdb interpretation -> HIVdb-format CSVs")
    ap.add_argument("fasta", nargs="+", help="input FASTA file(s)")
    ap.add_argument("--outdir", default="data/raw",
                    help="where to write the CSVs (default: data/raw)")
    ap.add_argument("--json-out",
                    help="keep the raw sierralocal JSON here (audit record)")
    ap.add_argument("--xml", default=None,
                    help=f"HIVdb algorithm XML to interpret with. Defaults to "
                         f"the pinned {PINNED_ALGORITHM.name}; override only "
                         f"with a recorded revalidation.")
    ap.add_argument("--sierralocal", default="sierralocal",
                    help="path to the sierralocal executable")
    ap.add_argument("--metadata-template", action="store_true",
                    help="also write a metadata.csv skeleton into --outdir "
                         "with the sequence names filled in and every "
                         "patient field blank. Useful for testing "
                         "interpretation, and for starting a real batch "
                         "without transcribing CTC IDs by hand.")
    ap.add_argument("--force-metadata-template", action="store_true",
                    help="replace an existing metadata.csv when writing the "
                         "template (destroys any details already entered)")
    args = ap.parse_args()

    for f in args.fasta:
        if not Path(f).is_file():
            sys.exit(f"error: no such FASTA file: {f}")

    # Fall back to the pinned algorithm rather than sierralocal's bundled
    # default, so an operator cannot silently report under the wrong version.
    xml = Path(args.xml) if args.xml else PINNED_ALGORITHM
    if not xml.is_file():
        sys.exit(
            f"error: algorithm XML not found: {xml}\n"
            "The pinned HIVdb algorithm is required. Restore it from the "
            "repository, or pass --xml with the version recorded in the "
            "validation file."
        )
    print(f"Algorithm: {xml.name}", file=sys.stderr)

    outdir = Path(args.outdir)

    if args.json_out:
        json_path = Path(args.json_out)
        json_path.parent.mkdir(parents=True, exist_ok=True)
        records = run_sierralocal(args.fasta, json_path, args.sierralocal, xml)
    else:
        with tempfile.TemporaryDirectory() as tmp:
            records = run_sierralocal(args.fasta, Path(tmp) / "sierra.json",
                                      args.sierralocal, xml)

    if not records:
        sys.exit("error: sierralocal returned no sequences")

    names = [sequence_name(r) for r in records]
    blank = [i for i, n in enumerate(names, 1) if not n.strip()]
    if blank:
        sys.exit(f"error: FASTA record(s) {blank} have an empty header; "
                 "each sequence must be named with its CTC ID")
    duplicates = {n for n in names if names.count(n) > 1}
    if duplicates:
        sys.exit("error: duplicate sequence name(s): "
                 + ", ".join(sorted(duplicates)))

    seq_rows, res_rows, qc_rows = build_rows(records)

    write_csv(outdir / "sequenceSummaries.csv", seq_rows)
    write_csv(outdir / "resistanceSummaries.csv", res_rows)
    write_csv(outdir / "qc_report.csv", qc_rows)

    flagged = [r for r in qc_rows if r["QC Status"] == "REVIEW"]
    print(f"\n{len(records)} sequence(s) interpreted, "
          f"{len(flagged)} flagged for review.", file=sys.stderr)
    for row in flagged:
        print(f"  REVIEW  {row['Sequence Name']}: {row['QC Notes']}",
              file=sys.stderr)

    if args.metadata_template:
        write_metadata_template(outdir / "metadata.csv", names,
                                overwrite=args.force_metadata_template)

    if not (outdir / "metadata.csv").exists():
        print(f"\nInterpretation is complete and can be reviewed in "
              f"{outdir}/resistanceSummaries.csv and qc_report.csv.\n"
              f"To build patient reports, add {outdir}/metadata.csv "
              f"(--metadata-template starts one), then run "
              f"Rscript R/data_prep.R", file=sys.stderr)
    else:
        print(f"\nnext: complete {outdir}/metadata.csv, then run "
              "Rscript R/data_prep.R", file=sys.stderr)

    sys.exit(2 if flagged else 0)


if __name__ == "__main__":
    main()
