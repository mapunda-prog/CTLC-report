#!/usr/bin/env python3
"""Build a test dataset: renamed sequences plus simulated metadata.

Takes any FASTA, renames each record to a neutral test identifier
(test_seq_001, test_seq_002, ...) and writes a matching metadata.csv of
**entirely fabricated** patient details, so the whole pipeline can be
exercised end to end without using real patient information.

    python3 tools/make_test_data.py input.fasta --outdir data/test_data

Then run the pipeline as normal:

    python3 tools/fasta_to_csv.py data/test_data/test_sequences.fasta \\
        --outdir data/test_data
    Rscript R/data_prep.R           # pointed at data/test_data
    Rscript R/render_reports.R

The simulated details are deterministic for a given --seed, so a test run
is reproducible, which matters for the reproducibility checks in
VAL-HIVDR-001 section 7.8.

NOT FOR CLINICAL USE. Every patient field produced here is invented. The
facility, district, region and staff names are obviously fictitious so a
test report can never be mistaken for a real one.
"""

import argparse
import csv
import random
import sys
from datetime import date, timedelta
from pathlib import Path

METADATA_COLUMNS = [
    "sequence_name", "sex", "dob", "age", "sample_collection",
    "sample_received", "received_from", "district", "region",
    "requested_by", "received_by", "pre_gart_vl", "specimen_type",
    "specimen_quality", "art_history", "subtype", "comments", "test_date",
    "tested_by", "authorised_by", "report_date", "reported_by",
    "submitted_to_ctlc_date", "submitted_to_ctlc_by",
]

# Deliberately fictitious. Nothing here should resemble a real facility,
# person or patient.
FACILITIES = [
    ("Test Facility Alpha", "Test District One", "Test Region North"),
    ("Test Facility Bravo", "Test District Two", "Test Region North"),
    ("Test Facility Charlie", "Test District Three", "Test Region South"),
]
SPECIMEN_TYPES = ["Whole blood", "DBS", "Plasma"]
REGIMENS = ["TDF/3TC/DTG", "ABC/3TC/DTG", "TDF/3TC/EFV",
            "AZT/3TC/LPVr", "TDF/FTC/DTG"]
SUBTYPES = ["A1", "C", "D", "A1/D recombinant", "C", "A1"]

# National ART rollout; simulated regimens never start before this.
ART_ROLLOUT_YEAR = 2004


def read_fasta(path):
    """Yield (header, sequence) pairs."""
    header, chunks = None, []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n\r")
            if line.startswith(">"):
                if header is not None:
                    yield header, "".join(chunks)
                header, chunks = line[1:].strip(), []
            elif line.strip():
                chunks.append(line.strip())
    if header is not None:
        yield header, "".join(chunks)


def wrap(seq, width=70):
    return "\n".join(seq[i:i + width] for i in range(0, len(seq), width))


def simulated_row(name, index, rng, collection):
    """One fabricated patient record, internally consistent."""
    # One paediatric case in every batch, so the age handling is exercised.
    if index == 2:
        age = rng.randint(2, 14)
    else:
        age = rng.randint(18, 62)

    # Date of birth consistent with the age at collection, give or take.
    dob = collection - timedelta(days=age * 365 + rng.randint(0, 364))

    received = collection + timedelta(days=rng.randint(1, 5))
    tested = received + timedelta(days=rng.randint(3, 21))
    reported = tested + timedelta(days=rng.randint(1, 4))
    submitted = reported + timedelta(days=rng.randint(0, 3))

    facility, district, region = FACILITIES[index % len(FACILITIES)]

    # Spread across the range that matters clinically: some near the
    # 1000 copies/mL treatment-failure threshold, some very high.
    vl = rng.choice([1200, 5400, 9600, 48000, 125000, 369000, 760000])

    return {
        "sequence_name": name,
        "sex": "Female" if index % 2 == 0 else "Male",
        "dob": dob.isoformat(),
        "age": age,
        "sample_collection": collection.isoformat(),
        "sample_received": received.isoformat(),
        "received_from": facility,
        "district": district,
        "region": region,
        "requested_by": "Dr Test Requester",
        "received_by": "Test Receiving Officer",
        "pre_gart_vl": vl,
        "specimen_type": SPECIMEN_TYPES[index % len(SPECIMEN_TYPES)],
        "specimen_quality": "Suitable",
        # Start the regimen after birth, no earlier than the national ART
        # rollout, and before collection -- so a paediatric record cannot
        # claim treatment predating the patient, nor anyone predate ART.
        "art_history": "{} since {}".format(
            REGIMENS[index % len(REGIMENS)],
            rng.randint(max(dob.year + 1, ART_ROLLOUT_YEAR),
                        max(dob.year + 1, ART_ROLLOUT_YEAR,
                            collection.year - 1)),
        ),
        "subtype": SUBTYPES[index % len(SUBTYPES)],
        "comments": "SIMULATED TEST RECORD - NOT A REAL PATIENT",
        "test_date": tested.isoformat(),
        "tested_by": "Test Technologist",
        "authorised_by": "Test Authorising Officer",
        "report_date": reported.isoformat(),
        "reported_by": "Test Reporting Officer",
        "submitted_to_ctlc_date": submitted.isoformat(),
        "submitted_to_ctlc_by": "Test Reporting Officer",
    }


def main():
    ap = argparse.ArgumentParser(
        description="rename sequences and simulate matching metadata")
    ap.add_argument("fasta", help="input FASTA (headers are discarded)")
    ap.add_argument("--outdir", default="data/test_data")
    ap.add_argument("--prefix", default="test_seq_",
                    help="identifier prefix (default: test_seq_)")
    ap.add_argument("--seed", type=int, default=42,
                    help="seed, so a run is reproducible (default: 42)")
    ap.add_argument("--start-date", default="2025-06-02",
                    help="first collection date, ISO format")
    ap.add_argument("--keep-map", action="store_true",
                    help="also write header_map.csv linking the original "
                         "headers to the test identifiers. The original "
                         "headers may be real CTC IDs, so this file is "
                         "patient data; it stays in the gitignored outdir.")
    args = ap.parse_args()

    src = Path(args.fasta)
    if not src.is_file():
        sys.exit(f"error: no such FASTA file: {src}")

    records = list(read_fasta(src))
    if not records:
        sys.exit(f"error: no sequences found in {src}")

    rng = random.Random(args.seed)
    try:
        start = date.fromisoformat(args.start_date)
    except ValueError:
        sys.exit(f"error: --start-date must be ISO format, got {args.start_date}")

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    renamed, rows, mapping = [], [], []
    for i, (header, seq) in enumerate(records):
        name = f"{args.prefix}{i + 1:03d}"
        renamed.append((name, seq))
        collection = start + timedelta(days=rng.randint(0, 45))
        rows.append(simulated_row(name, i, rng, collection))
        mapping.append({"test_identifier": name, "original_header": header})

    fasta_out = outdir / "test_sequences.fasta"
    with fasta_out.open("w", encoding="utf-8") as fh:
        for name, seq in renamed:
            fh.write(f">{name}\n{wrap(seq)}\n")
    print(f"wrote {fasta_out} -- {len(renamed)} sequence(s) renamed")

    meta_out = outdir / "metadata.csv"
    with meta_out.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=METADATA_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {meta_out} -- simulated, fabricated patient details")

    if args.keep_map:
        map_out = outdir / "header_map.csv"
        with map_out.open("w", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(
                fh, fieldnames=["test_identifier", "original_header"])
            writer.writeheader()
            writer.writerows(mapping)
        print(f"wrote {map_out} -- treat as patient data")

    print("\nSimulated records:")
    for r in rows:
        print(f"  {r['sequence_name']}  {r['sex']:6} age {r['age']:>2}  "
              f"{r['specimen_type']:11} VL {r['pre_gart_vl']:>7}  "
              f"subtype {r['subtype']}")

    print(f"\nNext:\n"
          f"  python3 tools/fasta_to_csv.py {fasta_out} --outdir {outdir}\n"
          f"  Rscript -e 'source(\"R/data_prep.R\"); "
          f"prepare_report_data(\"{outdir}\", \"{outdir}\")'\n"
          f"  Rscript -e 'source(\"R/render_reports.R\"); "
          f"render_reports(data_file=\"{outdir}/report_data.csv\", "
          f"output_dir=\"{outdir}/out\")'")


if __name__ == "__main__":
    main()
