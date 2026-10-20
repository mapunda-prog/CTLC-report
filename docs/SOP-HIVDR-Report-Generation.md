# Standard Operating Procedure
## Generation of HIV Drug Resistance (HIVDR) Laboratory Reports

| | |
|---|---|
| **Document number** | SOP-HIVDR-001 |
| **Version** | 1.0 (draft — not yet in force) |
| **Supersedes** | None |
| **Effective date** | _to be completed on approval_ |
| **Next review** | 12 months from effective date, or on any revalidation trigger |
| **Laboratory** | National Public Health Laboratory |
| **Author** | _name, title, date, signature_ |
| **Reviewed by** | _Quality Manager — name, date, signature_ |
| **Approved by** | _Laboratory Director — name, date, signature_ |

> **This SOP may not be used for patient reporting until the validation
> protocol (VAL-HIVDR-001) has been executed and signed off, and the two
> open items in §13 have been closed.**

---

## 1. Purpose

To define the procedure for converting HIV-1 *pol* sequences into authorised
HIVDR laboratory report forms for submission to Care and Treatment Clinics
(CTLC), ensuring that every report is traceable, reproducible, and
interpreted using a controlled version of the Stanford HIVdb algorithm.

## 2. Scope

Applies to all HIV-1 drug resistance genotyping performed at the National
Public Health Laboratory, for all specimen types and all assay designs,
including:

- full *pol* assays covering protease, reverse transcriptase and integrase;
- partial assays covering PR/RT only, or integrase only;
- repeat and referred-in testing.

It covers the steps **from an assembled, quality-checked consensus sequence
to an authorised report**. It does not cover nucleic acid extraction,
amplification, sequencing chemistry or sequence assembly, which are described
in their own SOPs.

## 3. Responsibilities

| Role | Responsibility |
|---|---|
| **Laboratory Technologist** | Prepares the FASTA and metadata files; runs the pipeline; reviews QC output; prepares draft reports. |
| **Senior Technologist / Reviewer** | Verifies QC flags have been resolved; checks the draft report against the interpretation data; signs as "Tested by". |
| **Laboratory Director / Authorised Signatory** | Reviews and authorises each report for release; signs as "Authorised by". |
| **Quality Manager** | Maintains this SOP; ensures validation is current; investigates deviations. |
| **Bioinformatics / IT focal person** | Maintains the software installation and the pinned algorithm version; performs revalidation after any change. |

No single person may both test and authorise the same report.

## 4. Abbreviations

| Term | Meaning |
|---|---|
| CTC / CTLC | Care and Treatment Clinic |
| DRM | Drug resistance mutation |
| EQA | External Quality Assessment |
| HIVdb | Stanford HIV Drug Resistance Database algorithm |
| INSTI | Integrase strand transfer inhibitor |
| NRTI / NNRTI | (Non-)nucleoside reverse transcriptase inhibitor |
| PI | Protease inhibitor |
| QC | Quality control |

## 5. Materials and software

| Item | Specification | Control |
|---|---|---|
| Workstation | Laboratory computer, access-controlled | Named users only |
| R | Version 4.6.0 or later | Version recorded in validation file |
| Quarto | Version 1.10 or later (bundled with RStudio) | As above |
| R packages | tidyverse, rio, janitor, quarto, yaml | As above |
| sierralocal | Version 0.4.3 | **HIVdb 10.2 pinned — see §6** |
| Pipeline | This repository, at a recorded commit | Commit hash recorded per run |
| Control panel | `data/example/controls/validation_panel.fasta` | Version controlled |

## 6. Algorithm version control — mandatory

The resistance interpretation depends entirely on the HIVdb algorithm
version. Different versions can give different interpretations for the same
sequence, so the version **must** be fixed, recorded, and printed on every
report.

**Version in force: HIVdb 10.2, published 2026-04-26**, pinned at
`algorithms/HIVDB_10.2.xml`. This is the current HIVdb release, so local
results match what the Stanford website returns today.

It is a **pinned snapshot, not a moving target**: the file is fixed and
never fetched at run time. Reports issued under the superseded 9.7 are not
directly comparable; that algorithm is retained at
`algorithms/HIVDB_9.7.xml` so a historical case can be reproduced with
`--xml algorithms/HIVDB_9.7.xml`.

1. The pinned XML is applied **automatically**; `--xml` is needed only to
   override it, which requires a recorded revalidation. sierralocal ships
   HIVdb 9.4, and the pinned file overrides it, so the shipped version
   cannot be used by omission.
2. Confirm the file's integrity before a run if it may have been altered:
   ```bash
   shasum -a 256 -c algorithms/HIVDB_10.2.xml.sha256
   ```
3. The algorithm version and publication date are carried through to the
   report automatically and appear in the "Algorithm" field. Check this
   field at review (§8.8) — it is the operator's confirmation that the
   correct version was used.
4. The algorithm **must not** be updated mid-batch, and `--forceupdate`
   **must not** be used during routine reporting; it fetches the newest
   algorithm and would silently change interpretations.
5. Any change of algorithm version is a revalidation trigger (§11 of
   VAL-HIVDR-001). This is not a formality: across 9.4, 9.7 and 10.2 the
   control panel changed reported clinical category for lopinavir/r and
   cabotegravir, cabotegravir changing twice and reverting.

## 7. Data confidentiality

- Sequences are interpreted **locally**. No patient-derived sequence, and no
  patient identifier, is transmitted outside the laboratory network.
- `data/raw/`, `data/processed/` and `output/` hold identifiable data. They
  are excluded from version control and **must never** be committed, emailed
  or copied to shared or cloud storage.
- Verify before any push to the code repository:
  ```bash
  git status --short
  ```
  Only code, templates, documentation and the synthetic fixture may appear.
- Finished reports are released only through the approved channel to the
  requesting clinic.

## 8. Procedure

### 8.1 Pre-run checks

Record on the run worksheet (Annex A):

1. Pipeline commit hash: `git rev-parse --short HEAD`
2. Pinned algorithm XML path and version
3. Operator name and date

Confirm the software is healthy before processing patient data:

```bash
Rscript tools/check_setup.R      # must report READY
Rscript tests/smoke_test.R       # all checks must pass
```

**If either fails, stop and refer to §10.** Installation problems are
covered in `docs/INSTALL.md`; `docs/JOB-AID.md` is the bench summary of
this procedure.

### 8.2 Prepare the sequence file

Assemble consensus sequences into a single FASTA file.

- One record per specimen.
- **The FASTA header must begin with the unique CTC ID**, which is the key
  used to join the interpretation to the patient details. Any text after the
  first space is treated as a free-text description and ignored.
- Sequence names must be unique within the batch. Duplicates are rejected.

```
>NN-NN-NNNN-NNNNN          <- the unique CTC ID, nothing else
CCTCAGGTCACTCTTTGGCAACGACCCCTCGTCACAATAAAGATAGGGGGGCAACTAAAG
...
```

**Include the wild-type control (`CTRL-WT`) in every batch** (§9).

### 8.3 Prepare the metadata file

Create or update `data/raw/metadata.csv`.

The simplest and safest start is to let the interpretation step write the
skeleton, which carries the sequence names across from the FASTA so the
CTC IDs are never retyped:

```bash
python3 tools/fasta_to_csv.py data/raw/run.fasta --outdir data/raw \
    --metadata-template
```

Then open `data/raw/metadata.csv` and complete the patient fields. A
re-run will **not** overwrite details already entered.
`data/example/metadata.csv` shows every supported column filled in.

Required for every specimen (the run will abort without them):

`sequence_name`, `sex`, `dob`, `age`, `sample_collection`, `pre_gart_vl`,
`test_date`

Optional but expected for a complete form:

`sample_received`, `received_from`, `district`, `region`, `requested_by`,
`received_by`, `tested_by`, `authorised_by`, `report_date`, `reported_by`,
`specimen_type`, `specimen_quality`, `art_history`, `subtype`, `comments`,
`submitted_to_ctlc_date`, `submitted_to_ctlc_by`

Dates may be entered as `YYYY-MM-DD` or `M/D/YYYY`; both print as
`DD/MM/YYYY`. `sequence_name` **must match the FASTA header exactly**.

> **Subtype:** the local interpretation engine does not assign HIV-1
> subtypes. Determine the subtype by the laboratory's established method and
> enter it in the `subtype` column, or leave the field blank so the report
> shows "Not reported". Do **not** leave a subtype field populated from a
> previous run.

### 8.4 Interpret the sequences

```bash
python3 tools/fasta_to_csv.py data/raw/run.fasta \
    --outdir data/raw \
    --json-out data/processed/sierra_<run-id>.json
```

The pinned HIVdb 10.2 algorithm is applied automatically; the run prints
`Algorithm: HIVDB_10.2.xml` so the operator can confirm it.

This runs entirely offline and writes `sequenceSummaries.csv`,
`resistanceSummaries.csv` and `qc_report.csv` into `data/raw/`.

Retain the `--json-out` file as the primary interpretation record.

**Exit codes:** `0` all passed QC · `2` one or more flagged for review ·
`1` the run failed.

### 8.5 Review the QC report — mandatory stop point

Open `data/raw/qc_report.csv`. Every sequence with `QC Status = REVIEW`
**must** be assessed and the decision recorded on the run worksheet before
proceeding.

| Flag | Meaning | Action |
|---|---|---|
| Coverage below minimum | The gene was only partly sequenced | Assess whether the covered region supports interpretation; consider repeat |
| Stop codon present | Possible defective genome or assembly error | Re-check assembly; repeat if unresolved |
| APOBEC-context mutations | Possible host-mediated hypermutation | Do not report hypermutated sequences; repeat |
| APOBEC-context DRM | A resistance mutation may be an artefact | Interpret with caution; annotate in Comments |
| Subtype not determined | Expected with local interpretation | Supply subtype via metadata (§8.3) |
| No gene aligned | Not an interpretable HIV *pol* sequence | Reject; repeat from extraction |

A flagged sequence may still be reported if the reviewer judges the flag not
to affect the interpretation, **provided the justification is recorded**.

### 8.6 Build the reporting table

```bash
Rscript R/data_prep.R
```

Read the console output. It states which drug classes are reportable, and
warns about:

- metadata columns that are absent (these print blank);
- sequences with no metadata row (reported with blank patient details);
- metadata rows with no sequence result;
- duplicate sequence names.

**Resolve every warning before continuing.** A sequence with no metadata row
produces a report with no patient identifiers on it.

### 8.7 Generate the reports

```bash
Rscript R/render_reports.R                      # whole batch
Rscript R/render_reports.R <CTC-ID> [<CTC-ID>]  # selected specimens
```

Reports are written to `output/lab_report_<CTC-ID>.docx`. One failure does
not stop the batch; any failures are listed at the end and **must** be
resolved.

### 8.8 Review and authorise

For each report, the reviewer confirms:

1. Patient identifiers match the request form.
2. The CTC ID on the report matches the sequence analysed.
3. The algorithm version is the pinned version.
4. Drug classes shown match the genes actually sequenced; any class not
   tested appears under **NOT TESTED**.
5. Scores and interpretations match `resistanceSummaries.csv`.
6. Mutations listed match the interpretation record.
7. The batch control gave its expected result (§9).

The reviewer signs as "Tested by"; the authorised signatory signs as
"Authorised by". **Reports are not released before both signatures.**

### 8.9 Release, record and archive

1. Release the authorised report to the requesting clinic by the approved
   route.
2. Record the submission date and submitting officer.
3. Archive per §11: the FASTA, the sierra JSON, the three CSVs, the
   `report_data.csv`, the final reports, the run worksheet, and the pipeline
   commit hash and algorithm version.
4. Clear `output/` and `data/raw/` of the completed batch once archived, to
   prevent a later run mixing specimens from two batches.

## 9. Quality control

### 9.1 Per-run control

`CTRL-WT` (wild-type HXB2) **must** be included in every batch.

**Expected result:** susceptible to all drugs **except** elvitegravir and
raltegravir, which must both score **10, level 2 (Potential Low-Level
Resistance)**. This reflects the accessory integrase polymorphism D232N
carried by the HXB2 reference and is the correct expected result, not a
defect.

**If the control deviates in any respect, the batch is invalid.** Do not
release any report from that batch. Record as a deviation and investigate —
the most likely cause is an unintended change of algorithm version.

### 9.2 External quality assessment

The laboratory shall participate in an EQA / proficiency testing scheme for
HIVDR genotyping at the frequency required by its accreditation body.
Panel results are processed through this SOP unchanged, and the reports
compared against the provider's expected results.

### 9.3 Periodic verification

At least every 12 months, and after any revalidation trigger, re-run the
full validation control panel and confirm the results still match Annex B
of VAL-HIVDR-001.

## 10. Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| `missing required column(s)` | metadata.csv lacks a required field | Add the column; see §8.3 |
| `drug class(es) only partly present` | The export has some but not all drugs of a class | Do not edit the CSV by hand; re-run the interpretation |
| `no metadata row for ...` | FASTA header does not match `sequence_name` | Correct the mismatch; check for stray spaces |
| `duplicate sequence_name` | Same ID twice in the batch | Resolve before reporting |
| `not present in report_data.csv` | Requested a CTC ID that was not interpreted | Check the ID and the QC report |
| `sierralocal not found` | Software not installed or not on PATH | Reinstall; use `--sierralocal` |
| `quarto failed` | Quarto not on PATH | Add RStudio's bundled Quarto to PATH |
| Subtype blank on the report | Expected — not called locally | Supply via the `subtype` metadata column |
| Smoke test fails | Software or configuration changed | **Stop.** Do not report. Escalate for revalidation |

Any unresolved problem is a deviation: record it, notify the Quality
Manager, and do not release affected reports.

## 11. Records and retention

| Record | Location | Retention |
|---|---|---|
| Consensus FASTA | Archive | Per national policy |
| sierralocal JSON | Archive | Per national policy |
| Interpretation CSVs | Archive | Per national policy |
| QC report | Archive | Per national policy |
| Authorised reports | Archive + LIMS | Per national policy |
| Run worksheet (Annex A) | QA file | Per national policy |
| Validation records | QA file | Life of system + 5 years |

Retention periods are set by national and institutional policy; the Quality
Manager confirms the applicable period.

## 12. References

1. Stanford University HIV Drug Resistance Database — HIVdb genotypic
   resistance interpretation algorithm.
2. WHO. *HIV drug resistance laboratory operational framework* and
   HIVResNet laboratory requirements.
3. ISO 15189 — Medical laboratories: requirements for quality and competence.
4. VAL-HIVDR-001 — Validation protocol for this pipeline.
5. Repository `README.md` — technical description of the pipeline.

## 13. Open items before this SOP takes effect

1. ~~**Algorithm version.**~~ **CLOSED.** HIVdb **10.2 (2026-04-26)**, the
   current release, is the version in force. It is pinned at
   `algorithms/HIVDB_10.2.xml` and applied automatically (§6).
2. **Concordance.** Complete the concordance exercise in VAL-HIVDR-001 §8
   before first clinical use.
3. **Laboratory contact details.** Complete the three `TO BE COMPLETED`
   fields in `config.yml`; they print verbatim on every report.
4. **Subtype determination.** Document the laboratory's subtyping method,
   or formally accept reporting subtype as "Not reported" (VAL-HIVDR-001
   §14, open item 2).

## 14. Revision history

| Version | Date | Author | Change |
|---|---|---|---|
| 1.0 | _draft_ | | Initial issue. Introduces local interpretation, replaces manual website export and the superseded Python report generator. |

---

## Annex A — Run worksheet

| Field | Entry |
|---|---|
| Run / batch ID | |
| Date | |
| Operator | |
| Number of specimens | |
| Pipeline commit hash | |
| Algorithm version (and XML path) | |
| Smoke test passed (Y/N) | |
| `CTRL-WT` result as expected (Y/N) | |
| Sequences flagged at QC | |
| QC decisions and justification | |
| Warnings from `data_prep.R` and resolution | |
| Reports generated (n) | |
| Reports failed (n, and resolution) | |
| Tested by / date | |
| Authorised by / date | |
| Deviations | |

## Annex B — Command summary

```bash
# 0. pre-run check
Rscript tests/smoke_test.R
git rev-parse --short HEAD

# 1. interpret locally
python3 tools/fasta_to_csv.py data/raw/run.fasta \
    --outdir data/raw \
    --json-out data/processed/sierra_<run-id>.json

# 2. review data/raw/qc_report.csv   <-- mandatory stop point

# 3. build the reporting table
Rscript R/data_prep.R

# 4. generate reports
Rscript R/render_reports.R

# 5. confirm nothing sensitive is staged before any commit
git status --short
```
