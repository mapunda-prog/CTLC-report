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

### 6.1.1 Coverage required of the functional panel

The six engineered controls exercise the interpretation logic. For
validation they are supplemented with clinical sequences chosen so that
every path through the pipeline is exercised at least once — roughly
**25–40 sequences in total**, selected deliberately rather than at random.
For deterministic software, a sequence that repeats a path already covered
adds no evidence.

| Coverage requirement | Rationale |
|---|---|
| Each drug class with at least one major resistance mutation | Exercises every class |
| Each resistance level 1–5 represented | Exercises every branch of the level mapping |
| PR+RT+IN, PR/RT-only and integrase-only configurations | All assay designs the laboratory runs (§7.4) |
| ≥ 1 subtype B, ≥ 1 subtype C, ≥ 1 non-B non-C | Mirrors the WHO proficiency panel rule |
| The subtypes prevalent locally, including recombinants | Validity for the population actually tested |
| At least one sequence with mixtures / ambiguity codes | Mixed specimens are the largest reported source of error in WHO proficiency panels |
| APOBEC hypermutation, stop codon, short or partial sequence, insertion or deletion | Each QC gate must be shown to fire |
| At least one sequence that **should** be rejected | Demonstrates rejection, not only acceptance |

Record which sequence satisfies each row; a single sequence may satisfy
several.

### 6.2 Synthetic patient fixture

`data/example/` — three fabricated patient records exercising the complete
metadata contract. Contains no identifiable data.

### 6.3 Note on the wild-type control

HXB2 carries the accessory integrase polymorphism **D232N**. The wild-type
control is therefore expected to show **EVG and RAL at score 10, level 2**,
not full susceptibility. This is correct algorithm behaviour and is the
stated expected result.

### 6.4 Pinned algorithm version

| | |
|---|---|
| Algorithm | HIVDB |
| **Version in force** | **10.2** |
| Publication date | 2026-04-26 |
| File | `algorithms/HIVDB_10.2.xml` |
| SHA-256 | `4676d08a1dfb263e3a0a178ed886a9b68b0f380bfd162f11a52edb6d48baa339` |
| Source | `hivdb/hivfacts`, `data/algorithms/` (ASI format, public domain) |
| Superseded | 9.7, retained at `algorithms/HIVDB_9.7.xml` |

HIVdb 10.2 is the current HIVdb release and the version Stanford's public
service now applies, so local results match what a clinician or assessor
would obtain by querying the website today.

**This is a pinned snapshot, not a moving target.** The file is fixed in
the repository and is never fetched at run time. Adopting a future release
is a deliberate act requiring revalidation (§11); `--forceupdate` must
never be used in routine reporting.

9.7 is retained because the laboratory's historical reports were produced
under it. Reports issued before and after this change are **not directly
comparable**, and a historical case may be reproduced by passing
`--xml algorithms/HIVDB_9.7.xml`.

sierralocal 0.4.3 ships HIVdb 9.4. The pinned file **overrides** that
default and is applied automatically by `tools/fasta_to_csv.py`, so an
operator cannot report under the shipped version by omission. Verify
integrity before use:

```bash
shasum -a 256 -c algorithms/HIVDB_10.2.xml.sha256
```

**Why this matters — measured effect of version changes.** The control
panel was run under three versions. Each step changed reported results:

| Control | Drug | 9.4 | 9.7 | 10.2 (in force) |
|---|---|---|---|---|
| `CTRL-PR-L90M` | ATV/r | 25, level 3 | 20, level 3 | 20, level 3 |
| `CTRL-PR-L90M` | LPV/r | 15, **level 3** | 10, **level 2** | 10, **level 2** |
| `CTRL-IN-N155H` | CAB | 25, **level 3** | 30, **level 4** | 25, **level 3** |

Moving 9.4 to 9.7 changed the reported clinical category for lopinavir/r
and cabotegravir. Moving 9.7 to 10.2 changed it back for cabotegravir —
one difference in 145 drug-level comparisons across the panel, with
nothing crossing the susceptibility boundary.

This is direct evidence that the algorithm version materially affects the
reported interpretation, including reversals between releases, and is the
justification for treating a version change as a revalidation trigger
(§11).

## 7. Test cases and acceptance criteria

> Expected values in VAL-02 to VAL-06 and VAL-10 were measured by executing
> the panel against the pinned algorithm **HIVdb 10.2 (2026-04-26)**, which is
> the version in force (§6.4). They are stated here before execution and are
> not to be revised to match an observed result.

### 7.1 Installation qualification

| ID | Test | Acceptance criterion | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-01 | Record versions of R, Quarto, R packages, sierralocal, pipeline commit, algorithm XML | All recorded in the validation file | | |

### 7.2 Resistance interpretation (PQ)

Run the control panel through the complete pipeline per SOP-HIVDR-001.

| ID | Control | Acceptance criterion (level codes) | Result | Pass/Fail |
|---|---|---|---|---|
| VAL-02 | `CTRL-WT` | All drugs level 1, **except** EVG and RAL at score 10 / level 2 | | |
| VAL-03 | `CTRL-PR-L90M` | PR L90M reported as a major PI mutation. NFV level 5; IDV/r and SQV/r level 4; ATV/r and FPV/r level 3; LPV/r level 2; DRV/r and TPV/r level 1 | | |
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

### 8.1 How many sequences

The WHO/HIVResNet operational framework sets no fixed number for method
validation. Its designation application instead requires the laboratory to
submit "a summary of the method validation including information on the
specimen types validated, **the number of specimens tested**, and the method
of evaluation or reference assay used for comparison" — that is, the
laboratory must state and **justify** its own number. The framework's
minimum of five samples applies to the annual proficiency panel (§9), which
assesses the whole genotyping process, not this software.

The justification here rests on the nature of the system. The pipeline is
**deterministic**: identical input yields identical output, with no reagent,
operator or run-to-run variability. Sample size therefore governs *coverage
of the input space*, not the precision of an estimate.

With zero discordances observed in *n* comparisons, the 95% upper confidence
bound on the true discordance rate is approximately **3/n** (the rule of
three):

| Sequences | 95% bound per sequence | Drug–sequence pairs | 95% bound per pair |
|---|---|---|---|
| 20 | 15% | 500 | 0.6% |
| 50 | 6% | 1 250 | 0.24% |
| **100** | **3%** | **2 500** | **0.12%** |
| 300 | 1% | 7 500 | 0.04% |

The 25 drug results within one sequence are **not statistically
independent** — a single alignment error affects many drugs at once — so the
per-sequence bound is the defensible figure and the per-pair bound is
supporting detail only.

**Requirement.** Compare **at least 100 sequences**, and in practice **every
archived sequence for which a Stanford website export is held**. Unlike
wet-laboratory validation this consumes no specimen, reagent or instrument
time: it re-runs files the laboratory already holds. There is accordingly no
justification for restricting the number. Record the number used and this
rationale in §13.

### 8.2 Method

Interpret the same sequences by both routes **under the version in force
(10.2)** and compare every drug's level code.

Because the laboratory's archived exports were produced under HIVdb 9.7,
they are **not** directly comparable now that 10.2 is in force. The
reference side must therefore be obtained by querying the Stanford website
afresh under 10.2.

> **Submitting sequences for the reference side.** Querying Stanford sends
> sequences outside the laboratory network, so the identifiers must be
> removed first. `tools/make_test_data.py` does this: it rewrites every
> header to a neutral identifier and, with `--keep-map`, retains the
> mapping locally so results can be matched back afterwards. Submit only
> the renamed FASTA; keep `header_map.csv` inside the laboratory, where it
> is patient data. Obtain the institutional approval required by §7 of the
> SOP. This is a one-off validation activity, never routine practice, and
> routine reporting continues to run entirely offline.
>
> Sequences remain patient-derived material even once the identifiers are
> stripped. Confirm the laboratory's position on sending them to a third
> party before starting, and record it.

> **Version trap.** Both routes must run the same algorithm version.
> Archived exports were produced with HIVdb 9.7, and the pipeline is now
> pinned to HIVdb 9.7 (§6.4), so archived exports are directly comparable.
> Comparing across versions would yield discordances that are genuine
> algorithm differences rather than installation faults, and would
> invalidate the exercise.

Run the comparison with the supplied tool, which refuses to compare files
scored with different algorithm versions:

```bash
python3 tools/compare_concordance.py \
    --reference data/manual_quering/resistanceSummaries.csv \
    --test      data/raw/resistanceSummaries.csv \
    --out       data/processed/concordance_differences.csv
```

It reports level-code concordance, flags any difference crossing the
susceptible / non-susceptible boundary as critical, and gives the rule-of-
three bound. Exit status is 0 only on 100% concordance.

> **Encoding difference, not discordance.** The Stanford website export
> keeps the columns for a gene it did not genotype and writes the literal
> string `NA`; the local adapter omits those columns instead. Both mean
> "not genotyped". The comparison tool treats them as equivalent, and the
> reporting code treats `NA` as missing so it can never reach a report as
> though it were a result.

### 8.3 Pilot result

A pilot was run on the six-sequence test panel, with the sequences
submitted to the Stanford website under de-identified names and the export
compared against local interpretation. Both routes ran **HIVdb 10.2, the
version now in force**, so this is valid evidence as far as it goes. It is
**not** sufficient on its own: six sequences bound the discordance rate at
only 50% per sequence, and all six derive from a single subtype B
reference.

| | |
|---|---|
| Sequences | 6 |
| Algorithm, both routes | HIVdb 10.2 (2026-04-26) |
| Drug-level comparisons | 145 |
| Not genotyped in either | 5 (integrase on the PR/RT-only control) |
| Differences | **0** |
| Level-code concordance | **100.000%** |
| Gene coverage agreement | exact, including PR/RT-only |

The full exercise of §8.1 remains outstanding, and must cover the subtypes
seen locally rather than subtype B alone.

**Acceptance criteria**

1. **100% concordance of resistance level codes** across all drugs and
   sequences.
2. Any discordance is investigated and explained before sign-off. A
   discordance affecting a clinical category (susceptible vs resistant) is a
   **critical** finding and blocks release.
3. The algorithm version used by each route is recorded and identical.

| Metric | Criterion | Result |
|---|---|---|
| Sequences compared | ≥ 100, or all archived | |
| Drug–sequence comparisons | | |
| Subtypes represented | ≥ 1 B, ≥ 1 C, ≥ 1 non-B non-C | |
| Level-code concordance | 100% | |
| Discordances (and category) | 0 critical | |
| 95% upper bound on discordance (3/n) | ≤ 3% per sequence | |

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

1. ~~**Algorithm version discrepancy.**~~ **CLOSED.** HIVdb **9.7
   (2024-11-09)** is confirmed as the version in force, matching the
   historical reports. `algorithms/HIVDB_9.7.xml` is pinned in the
   repository with a recorded SHA-256 and is applied by default, overriding
   the 9.4 algorithm that sierralocal ships. The expected values in §7.2 and
   Annex A have been re-derived under 9.7; see §6.4 for the differences this
   made.

2. **Subtype determination.** The local interpretation engine does **not**
   assign HIV-1 subtypes; the subtype field will be blank unless supplied.
   The laboratory must document its subtyping method and record it in the
   `subtype` metadata column, or formally accept reporting subtype as "Not
   reported". Confirm whether CTLC surveillance reporting requires subtype;
   if it does, this must be resolved before first clinical use.

---

## Annex A — Expected control panel results in full

Level codes: 1 Susceptible · 2 Potential Low-Level · 3 Low-Level ·
4 Intermediate · 5 High-Level. Measured with the pinned algorithm
**HIVdb 10.2 (2026-04-26)**. Bold marks any result that is not susceptible.

| Drug | WT | PR-L90M | RT-K103N | RT-M184V | IN-N155H |
|---|---|---|---|---|---|
| ATV/r | 1 | **3** | 1 | 1 | 1 |
| DRV/r | 1 | 1 | 1 | 1 | 1 |
| FPV/r | 1 | **3** | 1 | 1 | 1 |
| IDV/r | 1 | **4** | 1 | 1 | 1 |
| LPV/r | 1 | **2** | 1 | 1 | 1 |
| NFV | 1 | **5** | 1 | 1 | 1 |
| SQV/r | 1 | **4** | 1 | 1 | 1 |
| TPV/r | 1 | 1 | 1 | 1 | 1 |
| ABC | 1 | 1 | 1 | **3** | 1 |
| AZT | 1 | 1 | 1 | 1 | 1 |
| D4T | 1 | 1 | 1 | 1 | 1 |
| DDI | 1 | 1 | 1 | **2** | 1 |
| FTC | 1 | 1 | 1 | **5** | 1 |
| 3TC | 1 | 1 | 1 | **5** | 1 |
| TDF | 1 | 1 | 1 | 1 | 1 |
| DOR | 1 | 1 | 1 | 1 | 1 |
| EFV | 1 | 1 | **5** | 1 | 1 |
| ETR | 1 | 1 | 1 | 1 | 1 |
| NVP | 1 | 1 | **5** | 1 | 1 |
| RPV | 1 | 1 | 1 | 1 | 1 |
| BIC | 1 | 1 | 1 | 1 | **2** |
| CAB | 1 | 1 | 1 | 1 | **3** |
| DTG | 1 | 1 | 1 | 1 | **2** |
| EVG | **2** | **2** | **2** | **2** | **5** |
| RAL | **2** | **2** | **2** | **2** | **5** |

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
