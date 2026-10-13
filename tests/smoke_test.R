# ---------------------------------------------------------------------------
# End-to-end check against the synthetic fixture.
#
#   Rscript tests/smoke_test.R
#
# Uses data/example/ only, so it is safe to run anywhere and proves the
# pipeline works without any patient data present. Exits non-zero on failure.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(rio)
  library(yaml)
  library(janitor)
})
invisible(suppressWarnings(Sys.setlocale("LC_CTYPE", "en_US.UTF-8")))

failures <- character(0)

check <- function(label, expr) {
  ok <- tryCatch(isTRUE(expr), error = function(e) {
    failures <<- c(failures, paste0(label, " (error: ", conditionMessage(e), ")"))
    NA
  })
  if (is.na(ok)) return(invisible(NULL))
  if (!ok) failures <<- c(failures, label)
  message(if (ok) "  ok    " else "  FAIL  ", label)
}

source("R/drugs.R")
source("R/report_helpers.R")
source("R/data_prep.R")
cfg <- yaml::read_yaml("config.yml")

message("Formatting helpers")
check("blank_if_na turns NA into an empty string", blank_if_na(NA) == "")
check("missing values never render as 'NA'", blank_if_na(NA_character_) != "NA")
check("ISO dates reformat to dd/mm/YYYY", fmt_date("2024-10-25") == "25/10/2024")
check("US dates reformat to dd/mm/YYYY", fmt_date("11/9/2024") == "09/11/2024")
check("unparseable dates pass through", fmt_date("week 42") == "week 42")
check("blank date stays blank", fmt_date(NA) == "")
check("viral load gets separators and unit",
      fmt_viral_load(500000) == "500,000 copies/mL")
check("viral load is never scientific notation",
      !grepl("e\\+", fmt_viral_load(1000000)))
check("absent mutation field reads 'Not reported'",
      fmt_mutations(NA) == "Not reported")
check("Stanford 'None' is preserved", fmt_mutations("None") == "None")

message("Resistance levels")
check("level 1 is Susceptible", level_label(1, cfg) == "Susceptible")
check("level 5 is High-Level Resistance",
      level_label(5, cfg) == "High-Level Resistance")
check("unknown level codes are flagged, not silently dropped",
      grepl("Unrecognised", level_label(9, cfg)))
check("missing level reads 'Not reported'", level_label(NA, cfg) == "Not reported")

message("Drug registry")
check("25 drugs registered", nrow(DRUGS) == 25)
check("every drug has a class in DRUG_CLASSES",
      all(DRUGS$class %in% names(DRUG_CLASSES)))
check("no duplicate drug codes", !any(duplicated(DRUGS$code)))

message("Pipeline on the synthetic fixture")
fixture <- build_report_data("data/example")
check("fixture yields 3 records", nrow(fixture) == 3)
check("fixture carries every score column", all(DRUGS$score_col %in% names(fixture)))
check("fixture carries every level column", all(DRUGS$level_col %in% names(fixture)))
check("fixture satisfies the full metadata contract",
      all(c(METADATA_REQUIRED, METADATA_OPTIONAL) %in% names(fixture)))
check("fixture holds no real CTC identifiers",
      all(grepl("^SYN-", fixture$sequence_name)))

rec <- fixture[1, ]
message("Drug tables")
for (cls in names(DRUG_CLASSES)) {
  tbl <- drug_table(rec, cls, cfg)
  check(paste0(cls, " table has one row per drug"),
        nrow(tbl) == sum(DRUGS$class == cls))
  check(paste0(cls, " table has no NA interpretation"),
        !any(is.na(tbl$Interpretation)) && !any(tbl$Interpretation == "NA"))
}

message("Gene coverage")
res_full <- clean_names(import("data/example/resistanceSummaries.csv"))
check("a three-gene export reports all four classes",
      setequal(detect_reportable_classes(res_full), names(DRUG_CLASSES)))

res_prrt <- res_full[, !grepl("^(bic|cab|dtg|evg|ral)_", names(res_full))]
check("a PR/RT-only export reports exactly PI, NRTI and NNRTI",
      setequal(detect_reportable_classes(res_prrt), c("pi", "nrti", "nnrti")))
check("a PR/RT-only export does not report INSTI",
      !"insti" %in% detect_reportable_classes(res_prrt))

res_in <- res_full[, !grepl(
  "^(atv_r|drv_r|fpv_r|idv_r|lpv_r|nfv|sqv_r|tpv_r|abc|azt|d4t|ddi|ftc|x3tc|tdf|dor|efv|etr|nvp|rpv)_",
  names(res_full))]
check("an integrase-only export reports exactly INSTI",
      setequal(detect_reportable_classes(res_in), "insti"))

res_partial <- res_full[, names(res_full) != "dtg_level"]
check("a half-present drug class is rejected, not silently dropped",
      inherits(try(detect_reportable_classes(res_partial), silent = TRUE),
               "try-error"))

check("an export with no complete class is rejected",
      inherits(try(detect_reportable_classes(res_full[, "sequence_name",
                                                      drop = FALSE]),
                   silent = TRUE), "try-error"))

check("genes_for_record splits a comma list",
      setequal(genes_for_record("PR,RT,IN"), c("PR", "RT", "IN")))
check("genes_for_record handles a single gene",
      setequal(genes_for_record("IN"), "IN"))
check("genes_for_record copes with a blank", length(genes_for_record("")) == 0)
check("every class maps to a gene",
      all(names(DRUG_CLASSES) %in% names(CLASS_GENE)))

message("Rendered drug table")
pi_tbl <- drug_table(rec, "pi", cfg)
check("drug_table carries a .level column for styling",
      ".level" %in% names(pi_tbl))
check("the printed table shows only Drug, Score and Interpretation",
      setequal(setdiff(names(pi_tbl), ".level"),
               c("Drug", "Score", "Interpretation")))
if (requireNamespace("flextable", quietly = TRUE)) {
  ft <- drug_flextable(pi_tbl)
  check("flextable is built from exactly the three visible columns",
        setequal(ft$col_keys, c("Drug", "Score", "Interpretation")))
  check(".level never reaches the rendered table",
        !".level" %in% ft$col_keys)
}

message("\nNegative-score regression")
# The legacy Python script returned no label at all for negative scores,
# so a susceptible drug printed with a bare number and no interpretation.
neg <- drug_table(rec, "nrti", cfg)
check("negative scores still get an interpretation",
      all(nzchar(neg$Interpretation)))

if (length(failures)) {
  message("\n", length(failures), " check(s) failed:")
  for (f in failures) message("  - ", f)
  quit(status = 1)
}
message("\nAll checks passed.")
