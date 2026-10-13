# ---------------------------------------------------------------------------
# Render one Word report per patient.
#
#   Rscript R/render_reports.R                 all patients in the batch
#   Rscript R/render_reports.R SYN-0001-TEST ...  named patients only
#
# Reports land in output/ as lab_report_<CTC-ID>.docx. The directory is
# gitignored -- finished reports contain patient data and must never be
# committed.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(rio)
  library(quarto)
})

invisible(suppressWarnings(Sys.setlocale("LC_CTYPE", "en_US.UTF-8")))

# Resolve pandoc here so the setting is inherited by the render process that
# Quarto spawns; without it flextable cannot draw the drug tables.
source(file.path("R", "report_helpers.R"))
invisible(ensure_pandoc())

TEMPLATE  <- file.path("templates", "ctlc-report.qmd")
DATA_FILE <- file.path("data", "processed", "report_data.csv")
OUTPUT_DIR <- "output"


#' Make a CTC ID safe to use as a filename.
safe_filename <- function(x) gsub("[^A-Za-z0-9._-]+", "_", x)


#' Render the report for a single sequence.
#'
#' Quarto writes its output next to the template, so the finished file is
#' moved into output/ afterwards.
render_one <- function(sequence_name, data_file = DATA_FILE,
                       output_dir = OUTPUT_DIR) {

  out_name <- paste0("lab_report_", safe_filename(sequence_name), ".docx")
  rendered <- file.path(dirname(TEMPLATE), out_name)
  final    <- file.path(output_dir, out_name)

  quarto::quarto_render(
    input         = TEMPLATE,
    output_file   = out_name,
    execute_params = list(
      sequence_name = sequence_name,
      # The template runs with its own directory as the working directory,
      # so make every path absolute before handing it over rather than
      # prefixing "../", which would corrupt an already-absolute path.
      data_file     = normalizePath(data_file, mustWork = TRUE),
      config_file   = normalizePath("config.yml", mustWork = TRUE)
    ),
    quiet = TRUE
  )

  if (!file.exists(rendered)) {
    stop("quarto reported success but produced no file for ", sequence_name,
         call. = FALSE)
  }
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  if (!file.rename(rendered, final)) {
    file.copy(rendered, final, overwrite = TRUE)
    file.remove(rendered)
  }
  final
}


#' Render every patient in the processed table, or a named subset.
#'
#' One failure does not abort the batch -- the remaining patients are still
#' rendered and the failures are listed at the end.
render_reports <- function(sequence_names = NULL, data_file = DATA_FILE,
                           output_dir = OUTPUT_DIR) {

  if (!file.exists(data_file)) {
    stop("no ", data_file, " -- run Rscript R/data_prep.R first", call. = FALSE)
  }

  report_data <- import(data_file)
  available <- as.character(report_data$sequence_name)

  if (is.null(sequence_names) || length(sequence_names) == 0) {
    sequence_names <- available
  } else {
    unknown <- setdiff(sequence_names, available)
    if (length(unknown)) {
      stop("not present in ", data_file, ": ",
           paste(unknown, collapse = ", "), call. = FALSE)
    }
  }

  message("Rendering ", length(sequence_names), " report(s) to ", output_dir, "/")

  ok <- character(0)
  failed <- list()
  for (sn in sequence_names) {
    result <- tryCatch(render_one(sn, data_file, output_dir),
                       error = function(e) e)
    if (inherits(result, "error")) {
      message("  FAILED  ", sn, ": ", conditionMessage(result))
      failed[[sn]] <- conditionMessage(result)
    } else {
      message("  ok      ", basename(result))
      ok <- c(ok, result)
    }
  }

  message("\nRendered ", length(ok), " of ", length(sequence_names), ".")
  if (length(failed)) {
    message("Failed: ", paste(names(failed), collapse = ", "))
  }
  invisible(list(rendered = ok, failed = failed))
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  render_reports(if (length(args)) args else NULL)
}
