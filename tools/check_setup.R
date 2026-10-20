# ---------------------------------------------------------------------------
# Check this machine can run the pipeline.
#
#   Rscript tools/check_setup.R
#
# Reports every requirement as OK, MISSING or WARN, with the command needed
# to fix anything missing. Run it after installing, after any software
# change, and as the first step when something stops working.
#
# Exits 0 if the pipeline can run, 1 if something essential is missing.
# ---------------------------------------------------------------------------

invisible(suppressWarnings(Sys.setlocale("LC_CTYPE", "en_US.UTF-8")))

problems <- character(0)
warnings_found <- character(0)

say <- function(status, item, detail = "") {
  mark <- switch(status, OK = "  OK     ", MISSING = "  MISSING",
                 WARN = "  WARN   ")
  cat(mark, " ", item, if (nzchar(detail)) paste0("  --  ", detail), "\n",
      sep = "")
}

need <- function(ok, item, detail = "", fix = "") {
  if (isTRUE(ok)) {
    say("OK", item, detail)
  } else {
    say("MISSING", item, detail)
    problems <<- c(problems, paste0(item, if (nzchar(fix)) paste0("\n      ", fix)))
  }
  invisible(ok)
}

warn <- function(ok, item, detail = "", advice = "") {
  if (isTRUE(ok)) {
    say("OK", item, detail)
  } else {
    say("WARN", item, detail)
    warnings_found <<- c(warnings_found,
                         paste0(item, if (nzchar(advice)) paste0("\n      ", advice)))
  }
  invisible(ok)
}

cat("\nCTLC-report setup check\n")
cat("=======================\n\n")

# -- are we in the project? -------------------------------------------------
cat("Project\n")
in_project <- file.exists(file.path("R", "data_prep.R")) &&
  file.exists(file.path("templates", "ctlc-report.qmd"))
need(in_project, "run from the project root",
     if (in_project) getwd() else paste("current directory is", getwd()),
     "cd into the CTLC-report folder, or open CTLC-report.Rproj in RStudio")
if (!in_project) {
  cat("\nCannot continue from here.\n")
  quit(status = 1)
}

# -- R ----------------------------------------------------------------------
cat("\nR\n")
rv <- getRversion()
need(rv >= "4.1.0", "R version", as.character(rv),
     "install a current R from https://cran.r-project.org")

pkgs <- c("dplyr", "rio", "janitor", "quarto", "yaml", "flextable",
          "officer", "rmarkdown", "tibble")
missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1),
                             quietly = TRUE)]
need(length(missing_pkgs) == 0, "R packages",
     if (length(missing_pkgs)) paste("missing:", paste(missing_pkgs, collapse = ", "))
     else paste(length(pkgs), "packages present"),
     sprintf('install.packages(c(%s))',
             paste(sprintf('"%s"', missing_pkgs), collapse = ", ")))

# -- Quarto and pandoc ------------------------------------------------------
cat("\nQuarto\n")
suppressWarnings(suppressMessages(
  try(source(file.path("R", "report_helpers.R")), silent = TRUE)))

quarto_ok <- exists("ensure_quarto") && isTRUE(ensure_quarto())
quarto_where <- tryCatch(quarto::quarto_path(), error = function(e) "")
if (is.null(quarto_where)) quarto_where <- ""
if (!nzchar(quarto_where)) quarto_where <- Sys.getenv("QUARTO_PATH", "")
need(quarto_ok, "quarto executable", quarto_where,
     "install Quarto from https://quarto.org/docs/get-started/ (or install RStudio, which bundles it)")

pandoc_ok <- exists("ensure_pandoc") && isTRUE(ensure_pandoc())
need(pandoc_ok, "pandoc (needed for the drug tables)",
     Sys.getenv("RSTUDIO_PANDOC", ""),
     "normally resolved from Quarto; install Quarto or RStudio")

# -- Python and sierra-local ------------------------------------------------
cat("\nLocal HIVdb interpretation\n")
py <- Sys.which(c("python3", "python"))
py <- py[nzchar(py)][1]
if (is.na(py)) py <- ""
need(nzchar(py), "python3", py,
     "install Python 3 from https://www.python.org/downloads/")

sl <- unname(Sys.which("sierralocal"))
need(nzchar(sl), "sierralocal", sl,
     "pip install sierralocal    (then reopen the terminal)")

# -- pinned algorithm -------------------------------------------------------
cat("\nAlgorithm\n")
alg_dir <- "algorithms"
xmls <- list.files(alg_dir, pattern = "^HIVDB_.*\\.xml$", full.names = TRUE)
need(length(xmls) > 0, "pinned algorithm XML present",
     paste(basename(xmls), collapse = ", "),
     "restore the algorithms/ folder from the repository")

for (x in xmls) {
  sha_file <- paste0(x, ".sha256")
  if (!file.exists(sha_file)) next
  recorded <- sub("\\s.*$", "", readLines(sha_file, warn = FALSE)[1])
  # Prefer digest when available; fall back to the shasum command, which
  # exists on macOS and Linux.
  actual <- NA_character_
  if (requireNamespace("digest", quietly = TRUE)) {
    actual <- digest::digest(file = x, algo = "sha256")
  } else {
    out <- suppressWarnings(
      tryCatch(system2("shasum", c("-a", "256", shQuote(x)),
                       stdout = TRUE, stderr = NULL),
               error = function(e) character(0)))
    if (length(out)) actual <- sub("\\s.*$", "", out[1])
  }
  if (is.na(actual)) {
    warn(FALSE, paste("checksum", basename(x)), "could not be computed",
         "install the digest package, or check manually with shasum -a 256")
  } else {
    warn(identical(actual, recorded), paste("checksum", basename(x)),
         if (identical(actual, recorded)) "matches" else "DOES NOT MATCH",
         "the algorithm file has changed; restore it from the repository")
  }
}

# -- configuration ----------------------------------------------------------
cat("\nConfiguration\n")
cfg_ok <- file.exists("config.yml")
need(cfg_ok, "config.yml present")
if (cfg_ok && requireNamespace("yaml", quietly = TRUE)) {
  cfg <- yaml::read_yaml("config.yml")
  todo <- names(Filter(function(v) {
    is.character(v) && length(v) == 1 && grepl("TO BE COMPLETED", v)
  }, cfg$laboratory))
  warn(length(todo) == 0, "laboratory contact details",
       if (length(todo)) paste("still to complete:", paste(todo, collapse = ", "))
       else "completed",
       "edit config.yml -- these fields print on every report")
}

# -- summary ----------------------------------------------------------------
cat("\n")
if (length(problems)) {
  cat("NOT READY -", length(problems), "requirement(s) missing:\n\n")
  for (p in problems) cat("  * ", p, "\n", sep = "")
  cat("\n")
  if (length(warnings_found)) {
    cat("Also check:\n")
    for (w in warnings_found) cat("  * ", w, "\n", sep = "")
    cat("\n")
  }
  quit(status = 1)
}

if (length(warnings_found)) {
  cat("READY, with", length(warnings_found), "thing(s) to check:\n\n")
  for (w in warnings_found) cat("  * ", w, "\n", sep = "")
  cat("\n")
} else {
  cat("READY - everything needed is installed.\n\n")
}

cat("Next: try the pipeline on the supplied test data.\n")
cat("  Rscript tests/smoke_test.R\n\n")
quit(status = 0)
