#!/usr/bin/env python3
"""Build the HIVDR validation control panel.

BUILD-TIME ONLY. Produces data/example/controls/validation_panel.fasta from
the public HIV-1 HXB2 reference (GenBank K03455.1, pol 2253-5096). No patient
material is involved, so the panel is safe to keep in version control and to
share with an assessor.

    python3 tools/make_control_panel.py --hxb2 path/to/hxb2_pol.fasta

Each control carries a known resistance mutation, so the expected
interpretation is known in advance and can be stated in the validation
protocol before the run. The panel also includes a wild-type negative control
and a PR/RT-only control that exercises the partial-gene path.

HXB2 pol codon layout used for the edits:
    PR  codons   1-99    nucleotide offset 0
    RT  codons   1-560   nucleotide offset 297
    IN  codons   1-289   nucleotide offset 1977
"""

import argparse
from pathlib import Path

PR_OFFSET, RT_OFFSET, IN_OFFSET = 0, 297, 1977
PR_NT, RT_NT = 297, 1680

# (control id, gene, codon, new codon, what it is for)
CONTROLS = [
    ("CTRL-WT",       None, None, None,
     "wild-type negative control"),
    ("CTRL-PR-L90M",  PR_OFFSET, 90,  "ATG",
     "protease L90M, a major PI mutation"),
    ("CTRL-RT-K103N", RT_OFFSET, 103, "AAC",
     "reverse transcriptase K103N, a major NNRTI mutation"),
    ("CTRL-RT-M184V", RT_OFFSET, 184, "GTG",
     "reverse transcriptase M184V, a major NRTI mutation"),
    ("CTRL-IN-N155H", IN_OFFSET, 155, "CAT",
     "integrase N155H, a major INSTI mutation"),
]


def read_fasta_sequence(path):
    lines = Path(path).read_text().splitlines()
    return "".join(l.strip() for l in lines if l and not l.startswith(">"))


def mutate(seq, gene_offset, codon, new_codon):
    at = gene_offset + (codon - 1) * 3
    return seq[:at] + new_codon + seq[at + 3:]


def wrap(seq, width=70):
    return "\n".join(seq[i:i + width] for i in range(0, len(seq), width))


def main():
    ap = argparse.ArgumentParser(description="build the HIVDR control panel")
    ap.add_argument("--hxb2", required=True,
                    help="FASTA of HXB2 pol, K03455.1 positions 2253-5096")
    ap.add_argument("--out",
                    default="data/example/controls/validation_panel.fasta")
    args = ap.parse_args()

    wt = read_fasta_sequence(args.hxb2)
    expected = PR_NT + RT_NT + 289 * 3
    if len(wt) != expected:
        raise SystemExit(
            f"error: expected {expected} nt of HXB2 pol, got {len(wt)}. "
            "Fetch K03455.1 positions 2253-5096."
        )

    records = []
    for name, offset, codon, new_codon, note in CONTROLS:
        seq = wt if offset is None else mutate(wt, offset, codon, new_codon)
        records.append((name, note, seq))

    # Truncated to PR+RT, so no integrase is amplified. Exercises the
    # partial-gene path: the report must omit INSTI and say it was not tested.
    records.append((
        "CTRL-PRRT-ONLY",
        "PR/RT only, no integrase -- partial-gene control",
        wt[:PR_OFFSET + PR_NT + RT_NT],
    ))

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as fh:
        for name, note, seq in records:
            fh.write(f">{name} {note}\n{wrap(seq)}\n")

    print(f"wrote {out} with {len(records)} controls")
    for name, note, seq in records:
        print(f"  {name:16} {len(seq):5} nt  {note}")


if __name__ == "__main__":
    main()
