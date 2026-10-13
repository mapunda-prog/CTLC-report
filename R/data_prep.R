# ---------------------------------------------------------------------------
# Build the per-patient reporting table.
#
# Inputs  (data/raw/)
#   sequenceSummaries.csv    Stanford HIVdb export -- gene coordinates, subtype
#   resistanceSummaries.csv  Stanford HIVdb export -- drug scores and levels
#   metadata.csv             locally captured patient + workflow fields
#
# Output  (data/processed/)
#   report_data.csv          one row per sequence, ready for the template
#
# Unlike the original data_cleanup.R this keeps the "<drug> Level" columns.
# Those are Stanford's own 1-5 resistance calls and are what the report
# prints; deriving levels from raw scores locally risks drifting out of step
# with the HIVdb algorithm whenever Stanford revises its thresholds.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(rio)
  library(janitor)
})

# Rscript starts in the C locale, where janitor's internal transliteration
# table emits a warning per accented character. Harmless, but it buries the
# real warnings this script raises, so ask for UTF-8 up front.
invisible(suppressWarnings(Sys.setlocale("LC_CTYPE", "en_US.UTF-8")))

source(file.path("R", "drugs.R"))

# -- metadata contract ------------------------------------------------------
# Fields the report needs that Stanford does not supply. Required ones abort
# the run if missing; optional ones only warn, and render as a blank line.
METADATA_REQUIRED <- c("sequence_name", "sex", "dob", "age",
                       "sample_collection", "pre_gart_vl", "test_date")

METADATA_OPTIONAL <- c("sample_received", "received_from", "district", "region",
                       "requested_by", "received_by", "tested_by",
                       "authorised_by", "report_date", "reported_by",
                       "specimen_type", "specimen_quality", "art_history",
                       "submitted_to_ctlc_date", "submitted_to_ctlc_by",
                       # Subtype is normally taken from the Stanford export,
                       # but sierra-local does not call subtypes. Supplying
                       # it here (from COMET, REGA or similar) overrides the
                       # export; leaving it blank keeps the export's value.
                       "subtype", "comments")


#' Abort unless every required column is present.
require_columns <- function(data, required, source_name) {
  missing <- setdiff(required, names(data))
  if (length(missing)) {
    stop(sprintf("%s is missing required column(s): %s",
                 source_name, paste(missing, collapse = ", ")),
         call. = FALSE)
  }
  invisible(data)
}

#' Add any optional columns that are absent, filled with NA, so downstream
#' code can reference them unconditionally.
add_missing_optional <- function(data, optional) {
  absent <- setdiff(optional, names(data))
  if (length(absent)) {
    message("  note: metadata has no ", paste(absent, collapse = ", "),
            " -- these will be blank on the report")
    data[absent] <- NA_character_
  }
  data
}


#' Assemble the reporting table from the three raw inputs.
#'
#' @param raw_dir directory holding the three source files
#' @return a tibble, one row per sequence present in BOTH Stanford exports
build_report_data <- function(raw_dir = file.path("data", "raw")) {

  path <- function(f) file.path(raw_dir, f)

  for (f in c("sequenceSummaries.csv", "resistanceSummaries.csv", "metadata.csv")) {
    if (!file.exists(path(f))) {
      stop("missing input file: ", path(f), call. = FALSE)
    }
  }

  message("Reading Stanford exports from ", raw_dir, "/")
  sequence_summary   <- clean_names(import(path("sequenceSummaries.csv")))
  resistance_summary <- clean_names(import(path("resistanceSummaries.csv")))
  metadata           <- clean_names(import(path("metadata.csv")))

  # -- work out which drug classes this batch can report on ----------------
  # Assays vary: a PR/RT-only run has no integrase columns at all. Require
  # only the classes that are present, and record them so the template knows
  # which sections to print.
  require_columns(resistance_summary, "sequence_name",
                  "resistanceSummaries.csv")
  reportable <- detect_reportable_classes(resistance_summary)
  message("Reportable drug class(es): ", paste(toupper(reportable), collapse = ", "),
          " (genes ", paste(unique(CLASS_GENE[reportable]), collapse = ", "), ")")

  omitted <- setdiff(names(DRUG_CLASSES), reportable)
  if (length(omitted)) {
    message("  not sequenced in this batch, will be omitted from reports: ",
            paste(toupper(omitted), collapse = ", "))
  }

  required_drug_cols <- unlist(lapply(reportable, function(cls) {
    cols <- DRUGS[DRUGS$class == cls, ]
    c(cols$score_col, cols$level_col)
  }))
  require_columns(resistance_summary, required_drug_cols,
                  "resistanceSummaries.csv")

  # Gene coordinates are required only for the genes actually covered.
  coord_cols <- unlist(lapply(unique(CLASS_GENE[reportable]), function(g) {
    paste0(tolower(g), c("_start", "_end"))
  }))
  require_columns(sequence_summary,
                  c("sequence_name", "subtype_percent", coord_cols),
                  "sequenceSummaries.csv")
  require_columns(metadata, METADATA_REQUIRED, "metadata.csv")
  metadata <- add_missing_optional(metadata, METADATA_OPTIONAL)

  # Take mutations and genes from the resistance export only -- both files
  # carry them, and joining on everything is what produced the .x/.y suffixes
  # in the original script.
  sequence_cols <- c("sequence_name", "genes", "pr_start", "pr_end",
                     "rt_start", "rt_end", "in_start", "in_end",
                     "subtype_percent", "na_mixture_rate_percent")
  sequence_slim <- sequence_summary %>%
    select(any_of(sequence_cols)) %>%
    select(-any_of("genes"))

  stanford <- resistance_summary %>%
    inner_join(sequence_slim, by = "sequence_name")

  # -- report on sequences that fell out of the Stanford join ---------------
  only_resistance <- setdiff(resistance_summary$sequence_name, sequence_slim$sequence_name)
  only_sequence   <- setdiff(sequence_slim$sequence_name, resistance_summary$sequence_name)
  if (length(only_resistance)) {
    warning("in resistanceSummaries but not sequenceSummaries, dropped: ",
            paste(only_resistance, collapse = ", "), call. = FALSE)
  }
  if (length(only_sequence)) {
    warning("in sequenceSummaries but not resistanceSummaries, dropped: ",
            paste(only_sequence, collapse = ", "), call. = FALSE)
  }

  # -- attach metadata ------------------------------------------------------
  # left_join, deliberately: a sequence with no metadata row still gets a
  # report (with blank demographics) rather than silently disappearing from
  # the batch, which is what the original inner_join would have done.
  report_data <- stanford %>%
    left_join(metadata, by = "sequence_name")

  no_metadata <- setdiff(stanford$sequence_name, metadata$sequence_name)
  if (length(no_metadata)) {
    warning("no metadata row for: ", paste(no_metadata, collapse = ", "),
            " -- patient details will be blank on these reports", call. = FALSE)
  }
  unused_metadata <- setdiff(metadata$sequence_name, stanford$sequence_name)
  if (length(unused_metadata)) {
    warning("metadata rows with no sequence result: ",
            paste(unused_metadata, collapse = ", "), call. = FALSE)
  }

  dup <- report_data$sequence_name[duplicated(report_data$sequence_name)]
  if (length(dup)) {
    warning("duplicate sequence_name after join: ",
            paste(unique(dup), collapse = ", "),
            " -- check for repeated metadata rows", call. = FALSE)
  }

  message("Built ", nrow(report_data), " patient record(s).")
  report_data
}


#' Build the table and write it to data/processed/report_data.csv.
prepare_report_data <- function(raw_dir       = file.path("data", "raw"),
                                processed_dir = file.path("data", "processed")) {
  report_data <- build_report_data(raw_dir)
  dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)
  out <- file.path(processed_dir, "report_data.csv")
  export(report_data, out)
  message("Wrote ", out)
  invisible(report_data)
}

# Run when executed with Rscript, stay quiet when source()d.
if (sys.nframe() == 0L) prepare_report_data()
