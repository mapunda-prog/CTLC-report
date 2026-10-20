# Installing the CTLC-report pipeline

How to set the pipeline up on a laboratory workstation, and how to give it
to someone else for testing.

Allow about 30 minutes on a machine that has none of the software yet. You
need administrator rights to install R, RStudio and Python.

---

## 1. What to install

| Software | Why | Where |
|---|---|---|
| **R** 4.1 or later | runs the pipeline | <https://cran.r-project.org> |
| **RStudio Desktop** | the easiest place to run it, and it bundles Quarto | <https://posit.co/download/rstudio-desktop/> |
| **Python 3.8** or later | runs the local HIVdb interpretation | <https://www.python.org/downloads/> |
| **sierralocal** | the offline HIVdb algorithm | installed with pip, below |

Quarto does **not** need a separate install if you have RStudio — the
pipeline finds RStudio's copy automatically. If you prefer not to install
RStudio, get Quarto from <https://quarto.org/docs/get-started/>.

> **Windows:** when installing Python, tick **"Add python.exe to PATH"** on
> the first screen of the installer. Almost every "sierralocal not found"
> problem traces back to this box being left unticked.

## 2. Get the pipeline

With git:

```bash
git clone https://github.com/mapunda-prog/CTLC-report.git
cd CTLC-report
```

Without git: open <https://github.com/mapunda-prog/CTLC-report>, choose
**Code → Download ZIP**, and unzip it somewhere sensible. Avoid a folder
that syncs to cloud storage while a run is in progress.

## 3. Install the R packages

Open `CTLC-report.Rproj` in RStudio, then in the Console:

```r
install.packages(c("dplyr", "rio", "janitor", "quarto", "yaml",
                   "flextable", "officer", "rmarkdown", "tibble"))
```

## 4. Install sierralocal

In the RStudio **Terminal** tab (not the Console):

```bash
pip install sierralocal
```

If `pip` is not recognised, try `pip3`, or on Windows `py -m pip install
sierralocal`. Close and reopen RStudio afterwards so it picks up the new
command.

## 5. Check it worked

In the RStudio Terminal:

```bash
Rscript tools/check_setup.R
```

It lists every requirement as OK or MISSING, and tells you the command to
fix anything missing. Work through it until it reports **READY**.

Then run the built-in tests, which use synthetic data only:

```bash
Rscript tests/smoke_test.R
```

All checks should pass.

## 6. Complete the configuration

Open `config.yml` and replace the three `TO BE COMPLETED` fields with the
laboratory's **institutional** contact details. They print on every report.

## 7. Try it end to end

The repository ships with test sequences, so you can produce real output
immediately without any patient data:

```bash
python3 tools/fasta_to_csv.py data/example/controls/validation_panel.fasta \
    --outdir data/test_data --metadata-template
Rscript -e 'source("R/data_prep.R");      prepare_report_data("data/test_data","data/test_data")'
Rscript -e 'source("R/render_reports.R"); render_reports(data_file="data/test_data/report_data.csv", output_dir="data/test_data/out")'
```

Six Word reports appear in `data/test_data/out/`. Open one — that is what a
patient report looks like.

---

## Where to run it

| | |
|---|---|
| **RStudio** (recommended) | Open `CTLC-report.Rproj`. Use the **Terminal** tab for the commands in the SOP. Everything is found automatically. |
| **A plain terminal** | Works too. Change into the project folder first — every command is relative to it. |
| **VS Code** | Works with the R extension. Use the integrated terminal the same way. |

The commands are identical everywhere. On Windows use PowerShell or the
RStudio Terminal, and write `python` if `python3` is not recognised.

**Always run from the project root** — the folder containing `README.md`.
`tools/check_setup.R` tells you if you are somewhere else.

---

## Sharing it for testing

The repository is safe to share as it stands: `data/raw/`,
`data/processed/` and `output/` are excluded from version control, so a
clone or a ZIP downloaded from GitHub contains **no patient data**. Only
the synthetic fixture and the HXB2-derived control panel travel with it.

Send a tester this:

> 1. Install R, RStudio and Python 3 (tick "Add python.exe to PATH").
> 2. `git clone https://github.com/mapunda-prog/CTLC-report.git`
>    — or download the ZIP from the same page.
> 3. Open `CTLC-report.Rproj` in RStudio.
> 4. Console: `install.packages(c("dplyr","rio","janitor","quarto","yaml","flextable","officer","rmarkdown","tibble"))`
> 5. Terminal: `pip install sierralocal`
> 6. Terminal: `Rscript tools/check_setup.R` — fix anything it reports.
> 7. Terminal: `Rscript tests/smoke_test.R` — all checks should pass.
> 8. Follow `docs/INSTALL.md` §7 to produce six example reports.
>
> The pipeline ships with its own test sequences. **Do not put real
> patient data in a test installation.**

### If you must share a folder rather than a repository

Copy the project, then **delete `data/raw/`, `data/processed/`, `output/`
and any other folder you created under `data/` before sending it**. Those
are the paths that hold patient data. The simplest safe way to produce a
shareable copy is to clone from GitHub rather than copy your working
folder, because the clone cannot contain them.

### What a tester should report back

- the output of `Rscript tools/check_setup.R`
- whether `Rscript tests/smoke_test.R` passed
- whether the six example reports rendered, and how they look
- anything in the instructions that did not match what they saw

---

## Common problems

| Message | Cause | Fix |
|---|---|---|
| `Quarto not found` | Quarto missing, or RStudio installed somewhere unusual | Install Quarto, or set `QUARTO_PATH` to the quarto executable |
| `sierralocal not found on PATH` | not installed, or Python not on PATH | `pip install sierralocal`; on Windows reinstall Python with "Add to PATH" ticked |
| `pandoc (>= 2) required` | pandoc not resolvable | Install Quarto or RStudio; `tools/check_setup.R` will confirm |
| `could not find function "..."` | an R package is missing | rerun the `install.packages` line in §3 |
| `missing input file: data/raw/...` | running from the wrong folder, or inputs not placed yet | `cd` to the project root; check the file names |
| `algorithm XML not found` | `algorithms/` folder missing from the copy | restore it from the repository — the pipeline will not run without it |
| Reports render but tables have no borders | pandoc not found when rendering | as above; rerun `tools/check_setup.R` |

If `check_setup.R` reports READY and the smoke test passes, the
installation is sound and any remaining problem is with the input data
rather than the software.
