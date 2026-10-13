# ---------------------------------------------------------------------------
# Drug registry
#
# Single definition of every antiretroviral reported on, the class it belongs
# to, and the two columns Stanford HIVdb emits for it. Both the data prep and
# the report template read this, so a drug is added or renamed in one place.
#
# Column names are the janitor::clean_names() form of the Stanford headers --
# note "3TC Score" becomes x3tc_score, since R names cannot start with a digit.
# ---------------------------------------------------------------------------

DRUG_CLASSES <- c(
  pi    = "PROTEASE INHIBITORS",
  nrti  = "NUCLEOSIDE REVERSE TRANSCRIPTASE INHIBITORS",
  nnrti = "NON-NUCLEOSIDE REVERSE TRANSCRIPTASE INHIBITORS",
  insti = "INTEGRASE STRAND TRANSFER INHIBITORS"
)

# The gene each drug class is interpreted from. Assays differ -- many HIVDR
# tests cover PR/RT only -- so a class is reported only when its gene was
# actually sequenced. Reporting "dolutegravir: not reported" on a run where
# integrase was never amplified invites it being read as a tested result.
CLASS_GENE <- c(pi = "PR", nrti = "RT", nnrti = "RT", insti = "IN")

DRUGS <- tibble::tribble(
  ~class,  ~code,    ~label,
  "pi",    "atv_r",  "atazanavir/r (ATV/r)",
  "pi",    "drv_r",  "darunavir/r (DRV/r)",
  "pi",    "fpv_r",  "fosamprenavir/r (FPV/r)",
  "pi",    "idv_r",  "indinavir/r (IDV/r)",
  "pi",    "lpv_r",  "lopinavir/r (LPV/r)",
  "pi",    "nfv",    "nelfinavir (NFV)",
  "pi",    "sqv_r",  "saquinavir/r (SQV/r)",
  "pi",    "tpv_r",  "tipranavir/r (TPV/r)",
  "nrti",  "abc",    "abacavir (ABC)",
  "nrti",  "azt",    "zidovudine (AZT)",
  "nrti",  "d4t",    "stavudine (D4T)",
  "nrti",  "ddi",    "didanosine (DDI)",
  "nrti",  "ftc",    "emtricitabine (FTC)",
  "nrti",  "x3tc",   "lamivudine (3TC)",
  "nrti",  "tdf",    "tenofovir (TDF)",
  "nnrti", "dor",    "doravirine (DOR)",
  "nnrti", "efv",    "efavirenz (EFV)",
  "nnrti", "etr",    "etravirine (ETR)",
  "nnrti", "nvp",    "nevirapine (NVP)",
  "nnrti", "rpv",    "rilpivirine (RPV)",
  "insti", "bic",    "bictegravir (BIC)",
  "insti", "cab",    "cabotegravir (CAB)",
  "insti", "dtg",    "dolutegravir (DTG)",
  "insti", "evg",    "elvitegravir (EVG)",
  "insti", "ral",    "raltegravir (RAL)"
)

DRUGS$score_col <- paste0(DRUGS$code, "_score")
DRUGS$level_col <- paste0(DRUGS$code, "_level")

# Mutation fields printed under each class heading, in report order.
CLASS_MUTATIONS <- list(
  pi    = c("PI Major Resistance Associated Mutations"     = "pi_major",
            "PI Accessory Resistance Associated Mutations" = "pi_accessory"),
  nrti  = c("NRTI Resistance Associated Mutations"         = "nrti"),
  nnrti = c("NNRTI Resistance Associated Mutations"        = "nnrti"),
  insti = c("INSTI Major Resistance Associated Mutations"     = "insti_major",
            "INSTI Accessory Resistance Associated Mutations" = "insti_accessory")
)
#' Which genes did this export actually cover?
#'
#' An assay that amplifies PR/RT only produces no integrase columns at all,
#' so the drug classes to report must be worked out per batch rather than
#' assumed. A class is reportable only when its Stanford score and level
#' columns are present.
#'
#' @return character vector of class keys, in DRUG_CLASSES order
detect_reportable_classes <- function(resistance_summary) {
  present <- vapply(names(DRUG_CLASSES), function(cls) {
    cols <- DRUGS[DRUGS$class == cls, ]
    all(c(cols$score_col, cols$level_col) %in% names(resistance_summary))
  }, logical(1))

  partial <- vapply(names(DRUG_CLASSES), function(cls) {
    cols <- DRUGS[DRUGS$class == cls, ]
    any(c(cols$score_col, cols$level_col) %in% names(resistance_summary)) &&
      !all(c(cols$score_col, cols$level_col) %in% names(resistance_summary))
  }, logical(1))

  if (any(partial)) {
    stop("drug class(es) only partly present in resistanceSummaries.csv: ",
         paste(names(DRUG_CLASSES)[partial], collapse = ", "),
         " -- a class must be wholly present or wholly absent, otherwise a ",
         "report could omit a drug without saying so", call. = FALSE)
  }
  if (!any(present)) {
    stop("resistanceSummaries.csv contains no complete drug class",
         call. = FALSE)
  }
  names(DRUG_CLASSES)[present]
}


#' Per-sample gene coverage, read from the Stanford "genes" column.
#'
#' Falls back to the batch-level classes when the column is absent.
genes_for_record <- function(genes_value) {
  v <- toupper(trimws(as.character(genes_value)))
  if (length(v) == 0 || is.na(v) || !nzchar(v)) return(character(0))
  trimws(strsplit(v, "[,;/ ]+")[[1]])
}


