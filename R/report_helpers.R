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

#' Candidate locations for a bundled or standalone Quarto installation.
quarto_candidates <- function() {
  exe <- if (.Platform$OS.type == "windows") "quarto.exe" else "quarto"
  c(
    # Standalone installs
    file.path(c("/usr/local/bin", "/opt/homebrew/bin", "/opt/quarto/bin",
                "/usr/bin", "/usr/lib/quarto/bin"), exe),
    # Bundled with RStudio -- macOS, Windows, Linux
    file.path("/Applications/RStudio.app/Contents/Resources/app/quarto/bin", exe),
    file.path(c("C:/Program Files/RStudio/resources/app/quarto/bin",
                "C:/Program Files/Quarto/bin",
                "C:/Program Files/RStudio/bin/quarto/bin"), exe),
    file.path(c("/usr/lib/rstudio/resources/app/quarto/bin",
                "/usr/lib/rstudio-server/resources/app/quarto/bin"), exe)
  )
}


#' Make sure the quarto command can be found.
#'
#' Quarto is usually installed as part of RStudio rather than on the system
#' PATH, so a plain `Rscript` run cannot see it and every render fails. Look
#' in the usual places and tell the quarto package where it is.
#'
#' @return TRUE if quarto is now locatable
ensure_quarto <- function() {
  found <- tryCatch(quarto::quarto_path(), error = function(e) NULL)
  if (!is.null(found) && nzchar(found) && file.exists(found)) {
    return(invisible(TRUE))
  }
  on_path <- unname(Sys.which("quarto"))
  if (nzchar(on_path)) {
    Sys.setenv(QUARTO_PATH = on_path)
    return(invisible(TRUE))
  }
  for (candidate in quarto_candidates()) {
    if (file.exists(candidate)) {
      Sys.setenv(QUARTO_PATH = candidate)
      return(invisible(TRUE))
    }
  }
  invisible(FALSE)
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

  ensure_quarto()
  quarto_bin <- tryCatch(quarto::quarto_path(), error = function(e) NULL)
  if (is.null(quarto_bin) || !nzchar(quarto_bin)) {
    quarto_bin <- Sys.getenv("QUARTO_PATH", unset = "")
  }
  if (!nzchar(quarto_bin)) quarto_bin <- unname(Sys.which("quarto"))
  if (!nzchar(quarto_bin)) return(invisible(FALSE))

  candidates <- Sys.glob(file.path(dirname(quarto_bin), "tools", "*", "pandoc"))
  candidates <- c(candidates,
                  Sys.glob(file.path(dirname(quarto_bin), "tools", "pandoc")))
  candidates <- candidates[file.exists(candidates)]
  if (!length(candidates)) return(invisible(FALSE))

  Sys.setenv(RSTUDIO_PANDOC = dirname(candidates[[1]]))
  invisible(TRUE)
}


#' Shared border for every table on the report.
report_rule <- function() officer::fp_border(color = "black", width = 0.5)


#' Lay out label/value pairs as a bordered form table.
#'
#' Replaces a run of "Label: value" paragraphs, which read as a wall of
#' text and leave a dangling colon wherever a field is blank. In a ruled
#' table an empty cell is visibly an empty field, and the values align.
#'
#' @param pairs named character vector or list: names are labels
#' @param ncol number of label/value column pairs across the page
#' @param blank_fields labels to leave as empty space rather than marking
#'   absent -- lines meant to be completed by hand, such as a signature
info_flextable <- function(pairs, ncol = 2, font = "Times New Roman",
                           size = 10, blank_fields = character()) {
  labels <- names(pairs)
  values <- vapply(pairs, blank_if_na, character(1), USE.NAMES = FALSE)

  # An em dash reads as "recorded as absent" rather than leaving the reader
  # to wonder whether the form is truncated. Used for descriptive fields
  # only -- never for a drug result, where absence must stay unmarked.
  # Fields named in blank_fields are left as space to write in.
  fill <- !nzchar(values) & !(labels %in% blank_fields)
  values[fill] <- "—"

  pad <- (-length(labels)) %% ncol
  if (pad) {
    labels <- c(labels, rep("", pad))
    values <- c(values, rep("", pad))
  }

  rows <- length(labels) %/% ncol
  cells <- list()
  for (j in seq_len(ncol)) {
    idx <- seq(j, by = ncol, length.out = rows)
    cells[[paste0("l", j)]] <- labels[idx]
    cells[[paste0("v", j)]] <- values[idx]
  }
  df <- as.data.frame(cells, stringsAsFactors = FALSE)

  ft <- flextable::flextable(df)
  ft <- flextable::delete_part(ft, part = "header")
  ft <- flextable::font(ft, fontname = font, part = "all")
  ft <- flextable::fontsize(ft, size = size, part = "all")
  ft <- flextable::border_outer(ft, part = "all", border = report_rule())
  ft <- flextable::border_inner_h(ft, part = "all", border = report_rule())
  ft <- flextable::border_inner_v(ft, part = "all", border = report_rule())
  ft <- flextable::padding(ft, padding.top = 1.5, padding.bottom = 1.5,
                           padding.left = 3, padding.right = 3, part = "all")

  for (j in seq_len(ncol)) {
    lab <- paste0("l", j)
    ft <- flextable::bold(ft, j = lab)
    ft <- flextable::bg(ft, j = lab, bg = "#F2F2F2")
    ft <- flextable::width(ft, j = lab, width = 1.55 * 2 / ncol)
    ft <- flextable::width(ft, j = paste0("v", j), width = 1.45 * 2 / ncol)
  }
  flextable::fix_border_issues(ft)
}


#' A shaded bar used as a section heading.
section_bar <- function(text, font = "Times New Roman", size = 11) {
  df <- data.frame(x = text, stringsAsFactors = FALSE)
  ft <- flextable::flextable(df)
  ft <- flextable::delete_part(ft, part = "header")
  ft <- flextable::font(ft, fontname = font, part = "all")
  ft <- flextable::fontsize(ft, size = size, part = "all")
  ft <- flextable::bold(ft)
  ft <- flextable::bg(ft, bg = "#D9D9D9")
  ft <- flextable::border_outer(ft, part = "all", border = report_rule())
  ft <- flextable::padding(ft, padding.top = 2, padding.bottom = 2,
                           padding.left = 4, part = "all")
  ft <- flextable::width(ft, j = "x", width = 6.0)
  flextable::fix_border_issues(ft)
}


#' Group the reportable drugs by resistance level.
#'
#' @return named list of character vectors, level label -> drug abbreviations
resistance_by_level <- function(record, reportable, cfg) {
  drugs <- DRUGS[DRUGS$class %in% reportable, ]
  out <- list()
  for (i in seq_len(nrow(drugs))) {
    lvl <- suppressWarnings(
      as.integer(blank_if_na(record[[drugs$level_col[i]]])))
    if (is.na(lvl) || lvl <= 2) next          # 1-2 are effectively active
    label <- cfg$resistance_levels[[as.character(lvl)]]
    if (is.null(label)) next
    # Abbreviation only -- "atazanavir/r (ATV/r)" becomes "ATV/r".
    abbr <- sub(".*\\(([^)]+)\\)$", "\\1", drugs$label[i])
    out[[label]] <- c(out[[label]], abbr)
  }
  # Most severe first.
  order_by <- c("High-Level Resistance", "Intermediate Resistance",
                "Low-Level Resistance")
  out[intersect(order_by, names(out))]
}


#' The results summary printed at the head of the results page.
#'
#' Gives the clinician the actionable finding without reading four tables.
#' Only levels 3-5 are listed: those are the drugs whose use is in question.
#' The per-class tables below remain the full record.
summary_flextable <- function(record, reportable, cfg,
                              font = "Times New Roman", size = 11) {
  grouped <- resistance_by_level(record, reportable, cfg)

  if (length(grouped) == 0) {
    rows <- data.frame(
      level = "No resistance detected",
      drugs = paste("All drugs tested are predicted susceptible or of",
                    "potential low-level resistance only."),
      stringsAsFactors = FALSE)
  } else {
    rows <- data.frame(
      level = names(grouped),
      drugs = vapply(grouped, paste, character(1), collapse = ", "),
      stringsAsFactors = FALSE, row.names = NULL)
  }

  ft <- flextable::flextable(rows)
  ft <- flextable::delete_part(ft, part = "header")
  ft <- flextable::font(ft, fontname = font, part = "all")
  ft <- flextable::fontsize(ft, size = size, part = "all")
  ft <- flextable::bold(ft, j = "level")
  ft <- flextable::bg(ft, j = "level", bg = "#F2F2F2")
  ft <- flextable::border_outer(ft, part = "all", border = report_rule())
  ft <- flextable::border_inner_h(ft, part = "all", border = report_rule())
  ft <- flextable::border_inner_v(ft, part = "all", border = report_rule())
  ft <- flextable::padding(ft, padding.top = 2, padding.bottom = 2,
                           padding.left = 4, padding.right = 4, part = "all")
  ft <- flextable::width(ft, j = "level", width = 2.0)
  ft <- flextable::width(ft, j = "drugs", width = 4.0)
  flextable::fix_border_issues(ft)
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
