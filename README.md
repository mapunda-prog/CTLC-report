# CTLC-report

Generates HIV drug resistance (HIVDR) laboratory report forms for CTLC
submission. It takes the Stanford HIVdb genotyping output plus locally
captured patient details and produces one Word report per patient, laid out
to the Ministry of Health HIVDR form.

Built with R and Quarto. The pipeline is two commands.

## Patient data

**Nothing under `data/raw/`, `data/processed/` or `output/` may be committed.**
Those paths are gitignored because they hold CTC IDs, dates of birth and viral
loads. Only `data/example/` — a synthetic three-patient fixture with fabricated
identifiers — is tracked, and it is what the tests run against.

Before pushing, confirm nothing sensitive is staged:

```bash
git status --short
```

## Requirements

- R (tested on 4.6.0) with: `tidyverse`, `rio`, `janitor`, `quarto`, `yaml`
- Quarto — bundled with RStudio, or install separately. If `quarto` is not on
  your `PATH`, add RStudio's copy:

  ```bash
  export PATH="/Applications/RStudio.app/Contents/Resources/app/quarto/bin:$PATH"
  ```

Python is **not** needed to run the pipeline. It is used only by
`tools/make_reference_docx.py`, a one-off build step described below.

## Documents

Routine use and validation are governed by two controlled documents, not by
this README:

- [`docs/SOP-HIVDR-Report-Generation.md`](docs/SOP-HIVDR-Report-Generation.md)
  — SOP-HIVDR-001, the step-by-step operating procedure.
- [`docs/VAL-HIVDR-001-Validation-Protocol.md`](docs/VAL-HIVDR-001-Validation-Protocol.md)
  — the validation protocol, with the control panel's expected results.

**Both are drafts. The pipeline must not be used for patient reporting until
the validation protocol has been executed and signed off.**

## Running it

### From FASTA (recommended)

Interpretation runs locally via [sierra-local], so sequences never leave the
laboratory network. Requires `pip install sierralocal`.

```bash
python3 tools/fasta_to_csv.py data/raw/run.fasta \
    --outdir data/raw \
    --json-out data/processed/sierra_<run-id>.json \
    --xml /controlled/path/HIVDB_<version>.xml   # pin the algorithm version

# review data/raw/qc_report.csv before continuing

Rscript R/data_prep.R
Rscript R/render_reports.R
```

The FASTA header must begin with the CTC ID; anything after the first space
is treated as a description and ignored.

`fasta_to_csv.py` exits `0` if all sequences passed QC, `2` if any were
flagged for review, and `1` on failure.

### From a Stanford website export

If the two CSVs were downloaded from the HIVdb website, place them in
`data/raw/` with `metadata.csv` and skip straight to:

```bash
Rscript R/data_prep.R        # join the inputs -> data/processed/report_data.csv
Rscript R/render_reports.R   # render every patient -> output/*.docx
```

[sierra-local]: https://github.com/PoonLab/sierra-local

To render only certain patients, pass their CTC IDs:

```bash
Rscript R/render_reports.R SYN-0001-TEST SYN-0003-TEST
```

A failure on one patient does not abort the batch; the rest still render and
the failures are listed at the end.

## Inputs

Three files in `data/raw/`:

| File | Source | Contents |
|---|---|---|
| `sequenceSummaries.csv` | Stanford HIVdb export | gene coordinates, subtype |
| `resistanceSummaries.csv` | Stanford HIVdb export | drug scores and resistance levels |
| `metadata.csv` | maintained locally | patient demographics and workflow fields |

All three are joined on `sequence_name` (the unique CTC ID).

### metadata.csv

Stanford supplies no patient or workflow detail, so `metadata.csv` provides it.
`data/example/metadata.csv` is a working template with every supported column.

**Required** — the run aborts without these:

`sequence_name`, `sex`, `dob`, `age`, `sample_collection`, `pre_gart_vl`,
`test_date`

**Optional** — absent columns are reported at startup and render as a blank on
the form:

`sample_received`, `received_from`, `district`, `region`, `requested_by`,
`received_by`, `tested_by`, `authorised_by`, `report_date`, `reported_by`,
`specimen_type`, `specimen_quality`, `art_history`,
`submitted_to_ctlc_date`, `submitted_to_ctlc_by`

Dates are accepted as `YYYY-MM-DD` or `M/D/YYYY` and printed as `DD/MM/YYYY`.
Anything unrecognised is printed as written rather than blanked.

A sequence with no matching metadata row still produces a report, with the
patient fields blank and a warning naming it — so a patient can never drop out
of a batch silently.

## Configuration

`config.yml` holds everything identical across reports: laboratory name and
contact, analyzer and instrument ID, sequenced gene regions, form title and
revision, and the Stanford resistance-level wording. Edit it rather than the
scripts or the template.

## Layout

```
R/
  drugs.R           the 25 reported antiretrovirals and their Stanford columns
  data_prep.R       joins the three inputs, validates, writes report_data.csv
  report_helpers.R  formatting used by the template
  render_reports.R  renders one .docx per patient
templates/
  ctlc-report.qmd   the report, parameterised by sequence_name
  reference.docx    Word styles, MoH letterhead, page-numbered footer
  emblem.jpg        national emblem used in the letterhead
data/
  raw/              interpretation CSVs + metadata (gitignored)
  processed/        joined table, sierra JSON      (gitignored)
  example/          synthetic fixture              (tracked)
    controls/       HXB2-derived validation panel  (tracked)
output/             finished reports               (gitignored)
docs/               SOP and validation protocol
tests/smoke_test.R  regression suite, runs on the fixture
tools/
  fasta_to_csv.py       FASTA -> local HIVdb -> CSVs (pipeline step)
  make_control_panel.py builds the validation panel  (build-time)
  make_reference_docx.py builds the Word styles      (build-time)
reference/          the superseded original scripts, kept for comparison
```

## Gene coverage

Assays differ, and the pipeline adapts to each batch. A drug class is
reported **only where its gene was actually sequenced**: PI from PR,
NRTI/NNRTI from RT, INSTI from IN. A class whose gene was not sequenced is
omitted from the report and listed under a **NOT TESTED** heading stating
that no inference about those drugs can be drawn — printing them blank could
be read as a susceptible result.

This works per specimen, so a batch mixing full-*pol* and PR/RT-only samples
produces correct reports for both. A drug class that is only *partly*
present in an export is rejected outright rather than silently reported with
a drug missing.

## Known limitations

- **Subtype is not called locally.** sierra-local does not assign HIV-1
  subtypes, so the subtype field is blank unless supplied in the `subtype`
  metadata column. A subtype in metadata overrides the export's value.
- **Algorithm version.** sierralocal 0.4.3 ships HIVdb 9.4, while earlier
  reports used 9.7. Pin the version the laboratory has decided on, with
  `--xml`, and record it. This is an open item in both documents.

## Resistance interpretation

Each drug prints Stanford's numeric score alongside its interpretation. The
interpretation is read **directly from the `<drug> Level` column** (codes 1–5)
rather than re-derived from the score locally, so it cannot drift out of step
when Stanford revises its thresholds. The wording for each code lives in
`config.yml`.

This also fixes a defect in the original Python script, which re-thresholded
scores locally and had no branch below zero: a drug scoring `-10` printed with
no interpretation at all. Such drugs now correctly read *Susceptible*.

## Regenerating reference.docx

`templates/reference.docx` carries the Word styles, the Ministry letterhead and
the `Page X of Y` footer. Word headers and footers cannot be expressed in
Markdown, so it is built once by a script and committed.

Only needed when the letterhead, fonts or footer change:

```bash
python3 tools/make_reference_docx.py   # needs python-docx and pyyaml
```

Then commit the regenerated file.

## Tests

```bash
Rscript tests/smoke_test.R
```

Runs against `data/example/` only, so it needs no patient data. Exits non-zero
on failure.

## reference/

Holds the superseded implementations, kept until the Quarto output has been
checked against them:

- `legacy_hivdr_script.py` — the original python-docx generator. Note it reads
  `row[13]` for both the pre-GART viral load and the HIV-1 subtype, which
  appears to shift every drug score one column left. Treat its output as
  suspect and verify against the Stanford export before relying on it.
- `data_cleanup_original.R`, `ctlc-report-form_original.qmd`,
  `ctlc_markdown_original.Rmd` — the earlier R/Quarto scaffolding.

These are not part of the pipeline and can be deleted once you are satisfied
with the new output.
