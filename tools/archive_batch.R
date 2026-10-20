# ---------------------------------------------------------------------------
# Archive a finished batch and clear the working folders for the next one.
#
#   Rscript tools/archive_batch.R <batch-id>
#   Rscript tools/archive_batch.R            # uses a timestamp as the id
#
# Implements SOP-HIVDR-001 section 8.9 step 3-4: everything in data/raw,
# data/processed and output is MOVED into archive/<batch-id>/, leaving the
# working folders empty.
#
# Starting a run with the previous batch still in place is how specimens
# get mixed: the interpretation step overwrites the two Stanford CSVs but
# will not overwrite metadata.csv, so yesterday's patient details would sit
# alongside today's sequences.
#
# Files are moved, never deleted. The archive holds patient data and is
# excluded from version control.
# ---------------------------------------------------------------------------

invisible(suppressWarnings(Sys.setlocale("LC_CTYPE", "en_US.UTF-8")))

WORKING <- c(file.path("data", "raw"),
             file.path("data", "processed"),
             "output")
KEEP <- ".gitkeep"


#' Files in a working folder, excluding the placeholder.
batch_files <- function(dir) {
  if (!dir.exists(dir)) return(character(0))
  found <- list.files(dir, all.files = TRUE, no.. = TRUE, recursive = TRUE)
  found[!basename(found) %in% KEEP]
}


archive_batch <- function(batch_id = NULL, archive_root = "archive") {
  if (!file.exists(file.path("R", "data_prep.R"))) {
    stop("run this from the project root", call. = FALSE)
  }

  present <- lapply(WORKING, batch_files)
  names(present) <- WORKING
  total <- sum(lengths(present))

  if (total == 0) {
    message("Nothing to archive -- the working folders are already clear.")
    return(invisible(NULL))
  }

  if (is.null(batch_id) || !nzchar(batch_id)) {
    batch_id <- format(Sys.time(), "%Y-%m-%d_%H%M%S")
  }
  # Keep the id usable as a folder name.
  batch_id <- gsub("[^A-Za-z0-9._-]+", "_", batch_id)

  destination <- file.path(archive_root, batch_id)
  if (dir.exists(destination) && length(batch_files(destination))) {
    stop("archive already exists and is not empty: ", destination,
         "\nChoose a different batch id.", call. = FALSE)
  }

  message("Archiving ", total, " file(s) to ", destination, "/")
  moved <- 0L
  manifest <- character(0)

  for (dir in WORKING) {
    files <- present[[dir]]
    if (!length(files)) next
    target_dir <- file.path(destination, basename(dir))
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)

    for (f in files) {
      from <- file.path(dir, f)
      to <- file.path(target_dir, f)
      dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
      ok <- suppressWarnings(file.rename(from, to))
      if (!ok) {
        # file.rename fails across filesystems; fall back to copy + remove.
        ok <- file.copy(from, to, overwrite = FALSE, copy.date = TRUE)
        if (ok) ok <- file.remove(from)
      }
      if (!ok) {
        stop("could not move ", from, " -- archive is incomplete, ",
             "resolve before starting a new batch", call. = FALSE)
      }
      moved <- moved + 1L
      manifest <- c(manifest, file.path(basename(dir), f))
      message("  ", dir, "/", f)
    }
    # Remove directories the move left behind, keeping the placeholder.
    leftovers <- setdiff(list.dirs(dir, recursive = TRUE), dir)
    for (d in rev(leftovers)) {
      if (!length(list.files(d, all.files = TRUE, no.. = TRUE))) {
        unlink(d, recursive = TRUE)
      }
    }
  }

  writeLines(
    c(paste("batch:", batch_id),
      paste("archived:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      paste("files:", moved),
      "",
      manifest),
    file.path(destination, "MANIFEST.txt"))

  message("\nArchived ", moved, " file(s). Working folders are clear.")
  message("Manifest: ", file.path(destination, "MANIFEST.txt"))
  message("\nThe archive contains patient data. It is excluded from version ",
          "control;\nstore or back it up according to SOP-HIVDR-001 §11.")
  invisible(destination)
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  archive_batch(if (length(args)) args[[1]] else NULL)
}
