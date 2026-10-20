# JOB AID — Generating HIVDR Reports

**Quick reference for the bench. Not a substitute for SOP-HIVDR-001 —
the SOP governs. Keep this beside the workstation.**

Algorithm in force: **HIVdb 10.2** · Run everything from the project folder
(the one containing `README.md`). In RStudio use the **Terminal** tab.

---

## Before you start

```bash
Rscript tools/check_setup.R      # must say READY
Rscript tests/smoke_test.R       # all checks must pass
git rev-parse --short HEAD       # record this on the worksheet
```

**If either fails, stop. Do not report patients.** See `docs/INSTALL.md`.

---

## The four steps

### 1 · Prepare the files

Put in `data/raw/`:

- **`run.fasta`** — one record per specimen.
  The header must **start with the CTC ID** and nothing else matters:
  ```
  >01-04-0100-07107
  CCTCAGGTCACTCTTTGGCAACGACCC...
  ```
- Include the wild-type control **`CTRL-WT`** in every batch.

### 2 · Interpret the sequences

```bash
python3 tools/fasta_to_csv.py data/raw/run.fasta \
    --outdir data/raw \
    --json-out data/processed/sierra_<run-id>.json \
    --metadata-template
```

Check the screen says `Algorithm: HIVDB_10.2.xml`.

This writes the interpretation **and** starts `data/raw/metadata.csv` with
the CTC IDs already filled in. It will not overwrite details you have
already entered.

### 3 · Review QC, then complete the metadata — **MANDATORY STOP**

Open **`data/raw/qc_report.csv`**. Every row marked `REVIEW` must be
assessed and the decision written on the worksheet **before** you continue.

| Flag | What to do |
|---|---|
| Coverage below minimum | Judge whether the covered region supports interpretation |
| Stop codon | Re-check assembly; repeat if unresolved |
| APOBEC mutations | Possible hypermutation — **do not report**; repeat |
| APOBEC drug-resistance mutation | Interpret with caution; note in Comments |
| Subtype not determined | Expected — enter the subtype in `metadata.csv` |
| No gene aligned | Reject; repeat from extraction |

Then open **`data/raw/metadata.csv`** and complete the patient fields.

**Required** (the run stops without them): `sex` · `dob` · `age` ·
`sample_collection` · `pre_gart_vl` · `test_date`

Dates may be `YYYY-MM-DD` or `M/D/YYYY`. **Never leave a subtype from a
previous run in place.**

### 4 · Build and render

```bash
Rscript R/data_prep.R         # read every warning before continuing
Rscript R/render_reports.R    # one .docx per patient in output/
```

Render selected patients only:
```bash
Rscript R/render_reports.R <CTC-ID> <CTC-ID>
```

---

## Warnings from step 4 and what they mean

| Warning | Meaning | Action |
|---|---|---|
| `no metadata row for ...` | FASTA header and `sequence_name` differ | Fix the mismatch — check for stray spaces |
| `metadata rows with no sequence result` | a specimen did not interpret | Check the QC report |
| `duplicate sequence_name` | same ID twice | Resolve before reporting |
| `not sequenced in this batch` | a drug class is absent | Expected for PR/RT-only runs |
| `missing required column(s)` | metadata incomplete | Add the column |

---

## Before releasing each report

- [ ] Patient identifiers match the request form
- [ ] CTC ID on the report matches the sequence analysed
- [ ] **Algorithm reads `HIVDB v10.2`**
- [ ] Drug classes shown match the genes sequenced; any untested class
      appears under **NOT TESTED**
- [ ] **Results summary agrees with the drug tables below it**
- [ ] Mutations match the interpretation record
- [ ] `CTRL-WT` gave its expected result (see below)
- [ ] Tested-by **and** authorised-by signed — *no single person may do both*

## Batch control — `CTRL-WT`

Expected: **all drugs susceptible, except EVG and RAL at score 10,
level 2 (Potential Low-Level Resistance).**

This is correct — it reflects a natural polymorphism in the HXB2 reference.

**Any other result invalidates the whole batch.** Release nothing, record a
deviation, and check the algorithm version first.

---

## Finishing up

1. Release reports through the approved route.
2. Archive: the FASTA, the sierra JSON, the three CSVs, `report_data.csv`,
   the reports, the worksheet, the commit hash and algorithm version.
3. **Clear `data/raw/` and `output/` of the finished batch** so the next
   run cannot mix specimens.

---

## Never

- Never use `--forceupdate` — it silently changes the algorithm.
- Never edit `resistanceSummaries.csv` or `sequenceSummaries.csv` by hand.
- Never commit or email anything from `data/raw/`, `data/processed/` or
  `output/` — these hold patient data.
- Never report a batch whose control failed, or whose smoke test failed.

## If something goes wrong

```bash
Rscript tools/check_setup.R
```

Troubleshooting tables: `docs/INSTALL.md` (installation) and
SOP-HIVDR-001 §10 (operation). Unresolved problems are deviations —
record them and tell the Quality Manager.
