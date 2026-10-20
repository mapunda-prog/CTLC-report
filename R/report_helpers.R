# ---------------------------------------------------------------------------
# Formatting helpers used by templates/ctlc-report.qmd
#
# All of these are defensive about missing values: a blank metadata field
# renders as an empty space on the form rather than the literal "NA", which
# on a clinical report could be read as a result.
# ---------------------------------------------------------------------------

#' Empty string for anything absent, otherwise the value as character.
#'
#' The Stanford website export writes the literal string "NA" for a gene
#' that was not genotyped -- it keeps the columns rather than omitting them,
#' unlike the local adapter. That string means "no result", so it is treated
#' as missing here; otherwise it could reach a report as though it were one.
#' Stanford uses "None" for an empty mutation list, so no real value is lost.
blank_if_na <- function(x) {
  if (length(x) == 0) return("")
  x <- as.character(x[1])
  if (is.na(x)) return("")
  x <- trimws(x)
  if (!nzchar(x) || identical(toupper(x), "NA")) "" else x
}

#' Stanford writes "None" for an empty mutation list; show that as "None"
#' but show a genuinely missing value as "Not reported".
fmt_mutations <- function(x) {
  v <- blank_if_na(x)
  if (!nzchar(v)) "Not reported" else v
}

#' Dates arrive in several shapes across the Stanford exports and the locally
#' maintained metadata (ISO, US m/d/Y, or already-parsed Date). Normalise to
#' dd/mm/YYYY, and pass anything unrecognised through untouched rather than
#' silently emitting NA.
fmt_date <- function(x) {
  v <- blank_if_na(x)
  if (!nzchar(v)) return("")
  # as.Date() raises an error rather than returning NA when no format in
  # tryFormats matches, so catch rather than suppress -- an odd date in one
  # metadata cell must not abort that patient's report.
  parsed <- tryCatch(
    suppressWarnings(
      as.Date(v, tryFormats = c("%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y", "%Y/%m/%d"))
    ),
    error = function(e) NA
  )
  if (length(parsed) != 1 || is.na(parsed)) v else format(parsed, "%d/%m/%Y")
}

#' Viral loads print with thousands separators and their unit.
fmt_viral_load <- function(x) {
  v <- blank_if_na(x)
  if (!nzchar(v)) return("")
  n <- suppressWarnings(as.numeric(gsub("[ ,]", "", v)))
  if (is.na(n)) return(v)
  paste0(format(n, big.mark = ",", scientific = FALSE, trim = TRUE),
         " copies/mL")
}

#' Emit "**Label:** value" lines as markdown, one per line.
#' Takes named arguments; a value that is blank still prints its label so the
#' form keeps a consistent shape and gaps are visibly gaps.
field_lines <- function(...) {
  fields <- list(...)
  for (nm in names(fields)) {
    cat(sprintf("**%s:** %s\n\n", nm, blank_if_na(fields[[nm]])))
  }
  invisible(NULL)
}

#' Map a Stanford level code (1-5) to its wording, via config.yml.
level_label <- function(code, cfg) {
  v <- blank_if_na(code)
  if (!nzchar(v)) return("Not reported")
  lookup <- cfg$resistance_levels
  key <- as.character(suppressWarnings(as.integer(v)))
  if (is.na(key) || is.null(lookup[[key]])) {
    paste0("Unrecognised level (", v, ")")
  } else {
    lookup[[key]]
  }
}

#' Make sure flextable can find a pandoc to render Word tables with.
#'
#' Quarto keeps its pandoc inside its own installation rather than on PATH,
#' so rmarkdown -- and therefore flextable -- cannot see it and refuses to
#' print. Point RSTUDIO_PANDOC at Quarto's copy when nothing else is
#' available. RStudio sets this itself, so this is a no-op there.
ensure_pandoc <- function() {
  if (requireNamespace("rmarkdown", quietly = TRUE) &&
      rmarkdown::pandoc_available("2")) {
    return(invisible(TRUE))
  }

  quarto_bin <- tryCatch(quarto::quarto_path(), error = function(e) NULL)
  if (is.null(quarto_bin) || !nzchar(quarto_bin)) {
    quarto_bin <- unname(Sys.which("quarto"))
  }
  if (!nzchar(quarto_bin)) return(invisible(FALSE))

  candidates <- Sys.glob(file.path(dirname(quarto_bin), "tools", "*", "pandoc"))
  candidates <- c(candidates,
                  Sys.glob(file.path(dirname(quarto_bin), "tools", "pandoc")))
  candidates <- candidates[file.exists(candidates)]
  if (!length(candidates)) return(invisible(FALSE))

  Sys.setenv(RSTUDIO_PANDOC = dirname(candidates[[1]]))
  invisible(TRUE)
}


#' Render one drug-class table as a Word table.
#'
#' flextable writes borders and shading directly onto every cell, rather
#' than relying on a named Word style the reader's software has to resolve,
#' so the result looks the same in Word, LibreOffice and Google Docs.
#'
#' Non-susceptible interpretations are bold: on a printed form the clinically
#' actionable rows should be findable at a glance.
drug_flextable <- function(tbl, font = "Times New Roman", size = 11) {
  resistant <- which(!is.na(tbl$.level) & tbl$.level > 1)
  display <- tbl[, c("Drug", "Score", "Interpretation")]

  ft <- flextable::flextable(display)
  ft <- flextable::set_header_labels(ft, Drug = "Drug", Score = "Score",
                                     Interpretation = "Interpretation")
  ft <- flextable::font(ft, fontname = font, part = "all")
  ft <- flextable::fontsize(ft, size = size, part = "all")

  ft <- flextable::bg(ft, bg = "#D9D9D9", part = "header")
  ft <- flextable::bold(ft, part = "header")

  rule <- officer::fp_border(color = "black", width = 0.5)
  ft <- flextable::border_outer(ft, part = "all", border = rule)
  ft <- flextable::border_inner_h(ft, part = "all", border = rule)
  ft <- flextable::border_inner_v(ft, part = "all", border = rule)

  ft <- flextable::align(ft, j = "Score", align = "right", part = "all")
  ft <- flextable::align(ft, j = "Drug", align = "left", part = "all")
  ft <- flextable::align(ft, j = "Interpretation", align = "left", part = "all")

  if (length(resistant)) {
    ft <- flextable::bold(ft, i = resistant, j = "Interpretation")
  }

  ft <- flextable::padding(ft, padding.top = 1, padding.bottom = 1,
                           part = "all")
  ft <- flextable::width(ft, j = "Drug", width = 2.7)
  ft <- flextable::width(ft, j = "Score", width = 0.8)
  ft <- flextable::width(ft, j = "Interpretation", width = 2.5)
  flextable::fix_border_issues(ft)
}


#' One drug-class table: drug, Stanford score, Stanford interpretation.
#'
#' The score is shown for reference but the interpretation comes straight
#' from the algorithm's own "<drug> Level" column -- it is never re-derived
#' from the score locally.
drug_table <- function(record, class_key, cfg) {
  drugs <- DRUGS[DRUGS$class == class_key, ]

  score <- vapply(drugs$score_col, function(col) {
    if (is.null(record[[col]])) "" else blank_if_na(record[[col]])
  }, character(1))

  interp <- vapply(drugs$level_col, function(col) {
    if (is.null(record[[col]])) "Not reported" else level_label(record[[col]], cfg)
  }, character(1))

  # .level is carried for styling only (it drives the bolding of
  # non-susceptible rows) and is dropped before the table is printed.
  level_num <- vapply(drugs$level_col, function(col) {
    if (is.null(record[[col]])) return(NA_integer_)
    suppressWarnings(as.integer(blank_if_na(record[[col]])))
  }, integer(1))

  data.frame(
    Drug           = drugs$label,
    Score          = score,
    Interpretation = interp,
    .level         = level_num,
    stringsAsFactors = FALSE,
    row.names      = NULL,
    check.names    = FALSE
  )
}
