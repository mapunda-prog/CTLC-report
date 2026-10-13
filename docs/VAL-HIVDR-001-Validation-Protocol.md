# Validation Protocol
## HIVDR Sequence Interpretation and Reporting Pipeline

| | |
|---|---|
| **Document number** | VAL-HIVDR-001 |
| **Version** | 1.0 (draft — for execution) |
| **System validated** | CTLC-report pipeline (local HIVdb interpretation + report generation) |
| **Laboratory** | National Public Health Laboratory |
| **Framework** | WHO HIVResNet / WHO HIVDR laboratory requirements; supported by ISO 15189 §7.3 |
| **Prepared by** | _name, title, date, signature_ |
| **Reviewed by** | _Quality Manager — name, date, signature_ |
| **Approved by** | _Laboratory Director — name, date, signature_ |

---

## 1. Purpose

To document and execute the validation of a laboratory-developed software
system that interprets HIV-1 *pol* sequences against the Stanford HIVdb
algorithm and generates HIVDR laboratory report forms for CTLC submission.

The validation establishes that the system produces **correct, complete,
reproducible and traceable** resistance reports across the full range of
HIVDR tests performed by this laboratory.

## 2. Scope

### 2.1 In scope

| Component | Function validated |
|---|---|
| `tools/fasta_to_csv.py` | Local HIVdb interpretation of FASTA; QC flagging; conversion to HIVdb-format CSV |
| `R/data_prep.R` | Joining of interpretation and patient metadata; input validation; drug-class determination |
| `R/drugs.R`, `R/report_helpers.R` | Drug registry; resistance level mapping; field formatting |
| `templates/ctlc-report.qmd` | Report content, structure and gene-coverage logic |
| `R/render_reports.R` | Batch report generation |

The validation covers **all HIVDR test configurations** the laboratory
performs: full *pol* (PR+RT+IN), PR/RT only, and integrase only.

### 2.2 Out of scope

Extraction, amplification, sequencing chemistry, base calling and consensus
assembly — validated separately. The Stanford HIVdb algorithm itself is an
externally developed and internationally accepted reference algorithm; this
validation verifies **correct local execution and faithful reporting** of
that algorithm, not the algorithm's clinical correctness.

## 3. System description

### 3.1 Intended use

To generate HIVDR laboratory reports for clinical patient management and for
national HIVDR surveillance reporting to CTLC.

### 3.2 Data flow

```
Consensus FASTA  ──►  sierralocal (offline HIVdb)  ──►  sierra JSON
                                                          │
                                                          ▼
                                     sequenceSummaries.csv · resistanceSummaries.csv · qc_report.csv
                                                          │
                      metadata.csv  ──────────────────────┤
                                                          ▼
                                                   report_data.csv
                                                          │
                                                          ▼
                                            lab_report_<CTC-ID>.docx
```

### 3.3 Key design decisions to be verified

| # | Decision | Rationale |
|---|---|---|
| D1 | Interpretation runs **locally**; no sequence leaves the network | Patient confidentiality |
| D2 | Resistance interpretation is read **directly from the algorithm's level codes**, never re-derived locally from scores | Prevents drift from the HIVdb algorithm |
| D3 | Drug classes are reported **only where the gene was sequenced**; untested classes are declared | Prevents an untested drug reading as susceptible |
| D4 | Missing data renders **blank**, never as "NA" | "NA" on a clinical report could be read as a result |
| D5 | A sequence without metadata still produces a report, with a warning | Prevents a patient silently vanishing from a batch |
| D6 | The algorithm version is pinned and printed on every report | Traceability and comparability |
| D7 | Drug results are presented as ruled tables with a shaded header, and non-susceptible interpretations are bold | Each drug stays tied to its score and interpretation in print; actionable results are findable at a glance |

## 4. Risk assessment

| # | Hazard | Potential clinical consequence | Sev. | Control | Verified by |
|---|---|---|---|---|---|
| R1 | Result attributed to the wrong patient | Wrong treatment decision | Critical | Join on unique CTC ID; duplicate detection; unmatched-record warnings | VAL-07, VAL-08, VAL-09 |
| R2 | Untested drug class read as susceptible | Failing regimen continued | Critical | Class omitted and declared under NOT TESTED | VAL-10, VAL-11, VAL-12 |
| R3 | Resistance interpretation wrong or absent | Wrong regimen chosen | Critical | Levels taken verbatim from the algorithm | VAL-02 – VAL-06, VAL-13 |
| R4 | Wrong algorithm version used | Non-comparable or outdated interpretation | Major | Version pinned, printed on report, control per batch | VAL-14, VAL-15 |
| R5 | Missing value misread as a result | Misinterpretation | Major | Blanks render blank; "Not reported" where meaningful | VAL-16, VAL-17 |
| R6 | Hypermutated/poor sequence reported | False resistance call | Major | QC flags; mandatory review stop point | VAL-18, VAL-19 |
| R7 | Patient data leaves the laboratory | Confidentiality breach | Critical | Offline interpretation; data paths excluded from version control | VAL-20, VAL-21 |
| R8 | Silent partial failure in a batch | Missing report unnoticed | Major | Per-sequence pass/fail reporting; failures listed | VAL-22 |

## 5. Validation approach

A three-stage approach:

| Stage | Question | Evidence |
|---|---|---|
| **Installation (IQ)** | Is the correct software correctly installed? | Versions recorded; smoke test passes |
| **Operational (OQ)** | Does each function behave as specified, including at its limits? | Automated test suite; negative and boundary cases |
| **Performance (PQ)** | Does the whole system give correct results on material resembling real specimens? | Control panel with pre-stated expected results; concordance; reproducibility |

Acceptance criteria are stated **before** execution. Any deviation is
recorded in §12 and assessed before sign-off.

## 6. Reference materials

### 6.1 Validation control panel

`data/example/controls/validation_panel.fasta`, generated reproducibly by
`tools/make_control_panel.py` from the public HIV-1 reference **HXB2
(GenBank K03455.1, *pol* 2253–5096)**. No patient material is used, so the
panel may be shared with an assessor.

| Control | Engineered mutation | Purpose |
|---|---|---|
| `CTRL-WT` | none (wild type) | Negative control; per-batch control |
| `CTRL-PR-L90M` | PR L90M | Major PI resistance |
| `CTRL-RT-K103N` | RT K103N | Major NNRTI resistance |
| `CTRL-RT-M184V` | RT M184V | Major NRTI resistance |
| `CTRL-IN-N155H` | IN N155H | Major INSTI resistance |
| `CTRL-PRRT-ONLY` | truncated after RT | Partial-gene coverage |

### 6.2 Synthetic patient fixture

`data/example/` — three fabricated patient records exercising the complete
metadata contract. Contains no identifiable data.

### 6.3 Note on the wild-type control

HXB2 carries the accessory integrase polymorphism **D232N**. The wild-type
control is therefore expected to show **EVG and RAL at score 10, level 2**,
not full susceptibility. This is correct algorithm behaviour and is the
stated expected result.

## 7. Test cases and acceptance criteria

> Expected values in VAL-02 to VAL-06 and VAL-10 were obtained by executing
> the panel against HIVdb **9.4**. **Before execution, confirm these against
> the algorithm version the laboratory has pinned** and update if it differs
> (see §14, open item 1).

### 7.1 Installation qualification

| ID | Test | Acceptance criterion | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-01 | Record versions of R, Quarto, R packages, sierralocal, pipeline commit, algorithm XML | All recorded in the validation file | | |

### 7.2 Resistance interpretation (PQ)

Run the control panel through the complete pipeline per SOP-HIVDR-001.

| ID | Control | Acceptance criterion (level codes) | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-02 | `CTRL-WT` | All drugs level 1, **except** EVG and RAL at score 10 / level 2 | | |
| VAL-03 | `CTRL-PR-L90M` | PR L90M reported as a major PI mutation. NFV level 5; IDV/r and SQV/r level 4; ATV/r, FPV/r and LPV/r level 3; DRV/r and TPV/r level 1 | | |
| VAL-04 | `CTRL-RT-K103N` | RT K103N reported as a major NNRTI mutation. EFV and NVP level 5; DOR, ETR and RPV level 1 | | |
| VAL-05 | `CTRL-RT-M184V` | RT M184V reported as a major NRTI mutation. FTC and 3TC level 5; ABC level 3; DDI level 2; AZT, D4T and TDF level 1 | | |
| VAL-06 | `CTRL-IN-N155H` | IN N155H reported as a major INSTI mutation. EVG and RAL level 5; CAB level 3; BIC and DTG level 2 | | |

> VAL-04 note: etravirine must remain **susceptible** to K103N. A pipeline
> that reported ETR as resistant here would be clinically misleading.

### 7.3 Patient identity and data joining

| ID | Test | Acceptance criterion | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-07 | Each report's patient details match the metadata row for that CTC ID | 100% correct attribution across the panel | | |
| VAL-08 | Submit a batch containing a duplicated sequence name | Run rejects or warns; duplicate never silently merged | | |
| VAL-09 | Submit a sequence with no metadata row, and a metadata row with no sequence | Both warned explicitly and named; sequence still reported with blank patient fields | | |

### 7.4 Gene coverage — all HIVDR test configurations

| ID | Test | Acceptance criterion | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-10 | `CTRL-PRRT-ONLY` | Report shows PI, NRTI and NNRTI only. **No INSTI results of any kind.** A NOT TESTED section names the integrase class and states no inference may be drawn | | |
| VAL-11 | Integrase-only export | Report shows INSTI only; PI/NRTI/NNRTI declared not tested | | |
| VAL-12 | Mixed batch of full-*pol* and PR/RT-only specimens | Each report reflects **its own** gene coverage, not the batch's | | |
| VAL-13 | Export with a drug class only partly present | Run **rejected** with an explicit error; no report produced | | |

### 7.5 Algorithm version control

| ID | Test | Acceptance criterion | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-14 | Inspect every report produced from the panel | Algorithm name, version and date printed, matching the pinned version | | |
| VAL-15 | Confirm no network access occurs during interpretation | Interpretation completes with the network disconnected | | |

### 7.6 Handling of missing and unusual data

| ID | Test | Acceptance criterion | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-16 | Metadata with optional fields blank | Fields render blank. The string "NA" appears nowhere on any report | | |
| VAL-17 | Metadata with an unparseable date | Printed as entered; the report still generates | | |
| VAL-18 | Review `qc_report.csv` for the panel | Subtype-not-determined flagged on all controls; APOBEC-context DRM flagged on HXB2-derived controls | | |
| VAL-19 | Sequence with a stop codon or low coverage | Flagged `REVIEW` with the reason stated; exit code 2 | | |

### 7.7 Data confidentiality

| ID | Test | Acceptance criterion | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-20 | `git status --short` after a full patient run | No file under `data/raw/`, `data/processed/` or `output/` appears | | |
| VAL-21 | Search the tracked repository for patient identifiers | No real CTC ID, DOB or viral load present in any tracked file | | |

### 7.8 Batch robustness and reproducibility

| ID | Test | Acceptance criterion | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-22 | Batch containing one uninterpretable sequence | Remaining specimens still reported; the failure is named; count of successes and failures reported | | |
| VAL-23 | Run the panel twice from the same inputs | Interpretation outputs byte-identical; reports identical in content | | |
| VAL-24 | Run the panel on a second workstation | Same results as VAL-02 to VAL-06 | | |

### 7.9 Automated regression suite

| ID | Test | Acceptance criterion | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-25 | `Rscript tests/smoke_test.R` | All checks pass; exits 0 | | |

### 7.10 Report legibility

| ID | Test | Acceptance criterion | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-26 | Open a rendered report in the laboratory's word processor | Each drug class appears as a ruled table with a shaded, bold header row; every drug is on its own ruled row with its score and interpretation | | |
| VAL-27 | Print a report in black and white | All table rules and text legible; non-susceptible interpretations visibly bold; header repeats on any table split across pages | | |

The suite covers formatting, resistance-level mapping, drug registry
integrity, gene-coverage logic and the pipeline on the synthetic fixture. It
is re-run before every batch (SOP §8.1) and after any software change.

## 8. Concordance with the Stanford reference implementation

Local execution must agree with the Stanford reference. Published
concordance for sierra-local is 99.997%, but **local verification is
required**.

**Method.** Select at least **20 sequences** spanning the subtypes and
resistance patterns seen locally — ideally previously reported specimens
with an existing Stanford website export, plus the control panel. Interpret
by both routes **using the same algorithm version**, and compare every drug's
level code.

**Acceptance criteria**

1. **100% concordance of resistance level codes** across all drugs and
   sequences.
2. Any discordance is investigated and explained before sign-off. A
   discordance affecting a clinical category (susceptible vs resistant) is a
   **critical** finding and blocks release.
3. The algorithm version used by each route is recorded and identical.

> If sequences are sent to the Stanford website for this exercise, they
> leave the laboratory network. Use **de-identified sequence names** and
> obtain the institutional approval required by §7 of the SOP. This is a
> one-off validation activity, not routine practice.

| Metric | Criterion | Result |
|---|---|---|
| Sequences compared | ≥ 20 | |
| Drug–sequence comparisons | | |
| Level-code concordance | 100% | |
| Discordances (and category) | 0 critical | |

## 9. External quality assessment

Enrol in an EQA/proficiency scheme for HIVDR genotyping. Process panels
through the validated pipeline unchanged.

**Acceptance criterion:** reported resistance interpretations agree with the
provider's expected results, with any discordance investigated and
documented.

## 10. Overall acceptance criteria

The system is fit for clinical use when **all** hold:

1. All test cases VAL-01 to VAL-27 pass.
2. Concordance (§8) meets its criteria.
3. All critical risks in §4 have a verified control.
4. SOP-HIVDR-001 is approved and in force.
5. Both open items in §14 are closed.
6. Staff are trained and training is recorded.
7. This protocol is signed by all parties in §13.

**A failure of any test case involving patient identity (VAL-07 to VAL-09),
gene coverage (VAL-10 to VAL-13) or resistance interpretation (VAL-02 to
VAL-06) blocks release outright.**

## 11. Revalidation triggers

Repeat validation, in whole or in part, on any of:

| Trigger | Extent |
|---|---|
| HIVdb algorithm version change | Full §7.2 and §8 |
| sierralocal version change | Full §7.2 and §8 |
| Change to drug registry, template or interpretation logic | Affected cases plus §7.9 |
| New drug or drug class added | Full §7.2 |
| New assay design (different gene coverage) | §7.4 |
| R, Quarto or operating system major upgrade | §7.9 plus a panel run |
| Workstation replacement or migration | §7.9 plus a panel run |
| EQA failure or significant deviation | As determined by investigation |
| Routine interval | At least every 12 months |

## 12. Deviations

| # | Test ID | Description | Assessment | Action | Accepted by | Date |
|---|---|---|---|---|---|---|
| | | | | | | |

## 13. Approval

Validation executed by:

| Role | Name | Signature | Date |
|---|---|---|---|
| Validation Officer | | | |
| Bioinformatics / IT focal person | | | |

Reviewed and approved:

| Role | Name | Signature | Date |
|---|---|---|---|
| Quality Manager | | | |
| Laboratory Director | | | |

**Validation conclusion:** ☐ Accepted for clinical use ☐ Accepted with
restrictions (specify) ☐ Not accepted

Restrictions / conditions:

_______________________________________________________________

## 14. Open items — must be closed before sign-off

1. **Algorithm version discrepancy.** The installed sierralocal 0.4.3 ships
   HIVdb **9.4**, while historical reports were produced with HIVdb **9.7**.
   The laboratory must decide which version is in force, obtain and pin the
   corresponding XML, and re-derive the expected values in §7.2 if 9.7 is
   chosen. Reports produced under different algorithm versions are not
   directly comparable.

2. **Subtype determination.** The local interpretation engine does **not**
   assign HIV-1 subtypes; the subtype field will be blank unless supplied.
   The laboratory must document its subtyping method and record it in the
   `subtype` metadata column, or formally accept reporting subtype as "Not
   reported". Confirm whether CTLC surveillance reporting requires subtype;
   if it does, this must be resolved before first clinical use.

---

## Annex A — Expected control panel results in full

Level codes: 1 Susceptible · 2 Potential Low-Level · 3 Low-Level ·
4 Intermediate · 5 High-Level. Obtained with HIVdb 9.4 — reconfirm against
the pinned version.

| Drug | WT | PR-L90M | RT-K103N | RT-M184V | IN-N155H |
|---|---|---|---|---|---|
| ATV/r | 1 | 3 | 1 | 1 | 1 |
| DRV/r | 1 | 1 | 1 | 1 | 1 |
| FPV/r | 1 | 3 | 1 | 1 | 1 |
| IDV/r | 1 | 4 | 1 | 1 | 1 |
| LPV/r | 1 | 3 | 1 | 1 | 1 |
| NFV | 1 | 5 | 1 | 1 | 1 |
| SQV/r | 1 | 4 | 1 | 1 | 1 |
| TPV/r | 1 | 1 | 1 | 1 | 1 |
| ABC | 1 | 1 | 1 | 3 | 1 |
| AZT | 1 | 1 | 1 | 1 | 1 |
| D4T | 1 | 1 | 1 | 1 | 1 |
| DDI | 1 | 1 | 1 | 2 | 1 |
| FTC | 1 | 1 | 1 | 5 | 1 |
| 3TC | 1 | 1 | 1 | 5 | 1 |
| TDF | 1 | 1 | 1 | 1 | 1 |
| DOR | 1 | 1 | 1 | 1 | 1 |
| EFV | 1 | 1 | 5 | 1 | 1 |
| ETR | 1 | 1 | 1 | 1 | 1 |
| NVP | 1 | 1 | 5 | 1 | 1 |
| RPV | 1 | 1 | 1 | 1 | 1 |
| BIC | 1 | 1 | 1 | 1 | 2 |
| CAB | 1 | 1 | 1 | 1 | 3 |
| DTG | 1 | 1 | 1 | 1 | 2 |
| EVG | **2** | **2** | **2** | **2** | 5 |
| RAL | **2** | **2** | **2** | **2** | 5 |

Bold level-2 entries reflect the HXB2 D232N accessory polymorphism, present
in every control except the integrase mutant, where N155H dominates.

`CTRL-PRRT-ONLY`: PI, NRTI and NNRTI all level 1; **the report shows no
INSTI results and declares the integrase class not tested.**

Note on the interpretation CSV for this control. When the batch contains
*only* PR/RT specimens, the integrase columns are absent from
`resistanceSummaries.csv` altogether. When the batch **also** contains
full-*pol* specimens, the file carries integrase columns for all rows and
this control's integrase cells are **empty**. Both are correct. The report
must omit the integrase class in either case, which is why the template
tests both the gene list and the presence of level values. Verify the
**report**, not only the CSV.

## Annex B — Evidence to retain

| Evidence | Form |
|---|---|
| Software versions and pipeline commit | Validation file |
| Control panel FASTA and its generator | Version controlled |
| sierralocal JSON for the panel | Archived |
| Interpretation CSVs and QC report | Archived |
| Rendered control reports | Archived |
| Automated suite output | Archived |
| Concordance comparison | Spreadsheet, archived |
| Completed test tables from §7 | This document, signed |
| Deviation records | §12 |
