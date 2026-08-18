# read_generic_excel_injection.R
#
# DUPLICATE — copied verbatim from the repo root so that everything report.Rmd needs
# lives inside examples/example_run_generic_excel_report/, independent of the rest of
# the repo (a knitted Rmd's working directory is its own folder, and this repo has no
# .Rproj/.git/DESCRIPTION marker for here() to anchor to — see CLAUDE.md). If you fix a
# bug here, fix it in the canonical copy at the repo root too, and vice versa.
#
# Shared reader for the generic-Excel per-injection workbook format documented in
# CLAUDE.md ("Generic Excel input format"). Sourced internally by
# process_generic_excel_purity.R, process_generic_excel_std_curve.R, and
# plot_chromatograms.R so the parsing logic exists in exactly one place.
#
# Each workbook has three sheets:
#   Chromatogram: cell A1 = "Wavelength(nm): <value>", header row on row 2 (time, signal)
#   Peak Areas:   header row 1, columns peak_id, r_time, peak_area, wavelength
#   Metadata:     header row 1, one data row, columns analyte, injection_date,
#                 injection_volume, sample_dilution, target_rt, rt_window_min, rt_window_max
#
# type/std_conc/std_conc_unit/sample_id are parsed from the filename, not the workbook,
# using the same STD_/SMP_/BLK_ convention as legacy/.

library(readxl)
library(dplyr)
library(stringr)
library(tibble)
library(purrr)

#' Read one generic-Excel injection workbook
#'
#' @param file Path to a single .xlsx workbook (Chromatogram/Peak Areas/Metadata sheets)
#' @return A list with file/base_name/type/std_conc/std_conc_unit/sample_id/wavelength/
#'   chromatogram (tibble: time, signal)/peaks (tibble: peak_id, r_time, peak_area,
#'   wavelength)/meta (list)
read_injection <- function(file) {
  fname <- basename(file)
  base_name <- tools::file_path_sans_ext(fname)

  type <- dplyr::case_when(
    grepl("^STD", fname, ignore.case = TRUE) ~ "std",
    grepl("^SMP", fname, ignore.case = TRUE) ~ "smp",
    grepl("^BLK", fname, ignore.case = TRUE) ~ "blk",
    TRUE ~ NA_character_
  )
  if (is.na(type)) {
    stop("Cannot determine injection type (STD_/SMP_/BLK_ prefix) from filename: ", fname)
  }

  std_conc <- NA_real_
  std_conc_unit <- NA_character_
  sample_id <- NA_character_

  if (type == "std") {
    m <- stringr::str_match(fname, "STD_([0-9]+(?:\\.[0-9]+)?)[_-]?([^_.]+)?")
    if (is.na(m[1, 2])) {
      stop("STD filename does not encode a concentration (expected STD_<conc>_<unit>...): ", fname)
    }
    std_conc <- as.numeric(m[1, 2])
    std_conc_unit <- m[1, 3]
  } else if (type == "smp") {
    m <- stringr::str_match(fname, "SMP_([A-Za-z0-9]+)")
    if (is.na(m[1, 2])) {
      stop("SMP filename does not encode a sample id (expected SMP_<id>...): ", fname)
    }
    sample_id <- m[1, 2]
  }

  sheets <- readxl::excel_sheets(file)
  required_sheets <- c("Chromatogram", "Peak Areas", "Metadata")
  missing_sheets <- setdiff(required_sheets, sheets)
  if (length(missing_sheets) > 0) {
    stop(fname, " is missing sheet(s): ", paste(missing_sheets, collapse = ", "))
  }

  # Chromatogram: row 1 is a "Wavelength(nm): <value>" annotation, row 2 is the header.
  # suppressMessages() silences readxl/tibble's harmless "New names: `` -> `...1`"
  # notice, expected here since the annotation row's second cell is intentionally blank.
  wl_cell <- as.character(suppressMessages(
    readxl::read_excel(file, sheet = "Chromatogram", col_names = FALSE, n_max = 1)
  )[[1, 1]])
  wavelength <- as.numeric(stringr::str_extract(wl_cell, "[0-9.]+"))
  if (is.na(wavelength)) {
    stop(fname, ": Chromatogram sheet cell A1 must read 'Wavelength(nm): <value>', found: ", wl_cell)
  }

  chromatogram <- suppressMessages(readxl::read_excel(file, sheet = "Chromatogram", skip = 1)) %>%
    dplyr::rename_with(tolower) %>%
    dplyr::transmute(time = as.numeric(time), signal = as.numeric(signal)) %>%
    dplyr::filter(!is.na(time), !is.na(signal))

  peaks <- suppressMessages(readxl::read_excel(file, sheet = "Peak Areas")) %>%
    dplyr::rename_with(tolower) %>%
    dplyr::transmute(
      peak_id = as.integer(peak_id),
      r_time = as.numeric(r_time),
      peak_area = as.numeric(peak_area),
      wavelength = as.numeric(wavelength)
    )

  meta_raw <- suppressMessages(readxl::read_excel(file, sheet = "Metadata", col_types = "text")) %>%
    dplyr::rename_with(tolower)
  if (nrow(meta_raw) < 1) {
    stop(fname, ": Metadata sheet has no data row")
  }
  meta_row <- meta_raw[1, ]
  required_meta <- c(
    "analyte", "injection_date", "injection_volume", "sample_dilution",
    "target_rt", "rt_window_min", "rt_window_max"
  )
  missing_meta <- setdiff(required_meta, names(meta_row))
  if (length(missing_meta) > 0) {
    stop(fname, ": Metadata sheet is missing column(s): ", paste(missing_meta, collapse = ", "))
  }

  meta <- list(
    analyte = as.character(meta_row$analyte),
    injection_date = as.character(meta_row$injection_date),
    injection_volume = as.numeric(meta_row$injection_volume),
    sample_dilution = as.numeric(meta_row$sample_dilution),
    target_rt = as.numeric(meta_row$target_rt),
    rt_window_min = as.numeric(meta_row$rt_window_min),
    rt_window_max = as.numeric(meta_row$rt_window_max)
  )

  list(
    file = fname,
    base_name = base_name,
    type = type,
    std_conc = std_conc,
    std_conc_unit = std_conc_unit,
    sample_id = sample_id,
    wavelength = wavelength,
    chromatogram = chromatogram,
    peaks = peaks,
    meta = meta
  )
}

#' Read every injection workbook in a folder
#'
#' @param dir Folder containing one .xlsx per injection
#' @param pattern Filename pattern, default all .xlsx files
#' @return Named list of injections (as returned by read_injection()), named by filename
read_experiment <- function(dir, pattern = "\\.xlsx$") {
  files <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(files) == 0) {
    stop("No files matching '", pattern, "' found in ", dir)
  }
  purrr::map(files, read_injection) %>% purrr::set_names(basename(files))
}

#' Check that every injection in an experiment agrees on shared, method-level fields
#'
#' @param injections Named list as returned by read_experiment()
#' @param fields Which meta fields must be identical across all injections
#' @return A named list of the single agreed-upon value for each field
check_shared_meta <- function(injections, fields = c("analyte", "injection_date", "target_rt", "rt_window_min", "rt_window_max")) {
  out <- list()
  for (f in fields) {
    vals <- unique(purrr::map_chr(injections, function(inj) as.character(inj$meta[[f]])))
    if (length(vals) != 1) {
      stop("Injections disagree on `", f, "`, found: ", paste(vals, collapse = ", "))
    }
    out[[f]] <- vals
  }
  out
}
