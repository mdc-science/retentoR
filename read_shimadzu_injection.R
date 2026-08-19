# read_shimadzu_injection.R
#
# Reader for native Shimadzu LabSolutions ASCII (.txt) chromatogram exports, ported from
# legacy/'s ad hoc scripts. Returns the SAME per-injection list shape as
# read_generic_excel_injection.R's read_injection() (file/base_name/type/std_conc/
# std_conc_unit/sample_id/wavelength/chromatogram/peaks/meta), so nothing downstream
# needs to know which format an injection came from -- but this file is otherwise fully
# independent of read_generic_excel_injection.R (filename parsing and
# check_shared_meta() are duplicated here, not shared), matching this repo's convention
# of duplicating rather than cross-linking per-format readers (see CLAUDE.md).
#
# Unlike a generic-Excel workbook, a raw LabSolutions export carries no analyte name,
# target retention time, purity window, or sample dilution -- those are domain
# knowledge, not instrument output. They're supplied via a companion per-experiment CSV
# (read_shimadzu_experiment()'s `metadata_file`), one row per injection, columns:
# filename, analyte, injection_date, target_rt, rt_window_min, rt_window_max,
# sample_dilution. injection_volume, by contrast, *is* in the raw export (an
# "Injection Volume" line) and is read from there, not from the CSV.
#
# Deliberate divergence from legacy/: the legacy scripts divided intensity by 1e6
# (single-channel) or 1e3 (multi-channel) to approximate AU, a conversion CLAUDE.md
# already flags as unverified against real data and inconsistent between the two code
# paths. Purity (%) and the standard-curve fit/LoD/LoQ are unit-agnostic as long as
# every injection in one experiment is on the same raw scale, which they inherently are
# here (same instrument, same export format) -- so this reader does NOT apply either
# divisor. `signal`/`peak_area` are the raw exported numbers, decimal-comma converted
# to decimal-point only. If you need real AU for display, scale downstream of this
# reader once you've confirmed the correct factor against real data.
#
# Chromatogram section markers (both handled by parse_shimadzu_txt()):
#   Single-channel: "R.Time (min)\tIntensity" starts the one data table in the file.
#   Multi-channel:  one or more "[PDA Multi Chromatogram(ChN)]" blocks, each with its
#                   own "Wavelength(nm)" line and its own "R.Time (min)\tIntensity"
#                   table, terminated by the next "[...]" section or end of file.
# Peak table markers: one or more "[Peak Table(PDA-ChN)]" blocks; "# of Peaks" is 1 line
#   below the block header, a column-header line 1 below that, data 1 below that (i.e.
#   data starts at block_header_line + 3). Ch->wavelength is resolved by matching the
#   ChN in "[Peak Table(PDA-ChN)]" against the corresponding "[PDA Multi
#   Chromatogram(ChN)]" block's own Wavelength(nm) line.

library(readr)
library(dplyr)
library(stringr)
library(tibble)
library(purrr)

#' Low-level parse of one Shimadzu LabSolutions .txt export
#'
#' @param file Path to the raw .txt file
#' @return list(injection_volume, channels = named list of Ch key -> list(wavelength,
#'   chromatogram), peaks = combined tibble across every peak table found: peak_id,
#'   r_time, peak_area, wavelength)
parse_shimadzu_txt <- function(file) {
  lines <- readLines(file, warn = FALSE)

  inj_line <- grep("^Injection Volume", lines, value = TRUE)
  injection_volume <- if (length(inj_line) > 0) {
    as.numeric(gsub(",", ".", stringr::str_extract(inj_line[1], "[0-9]+(,[0-9]+)?")))
  } else {
    NA_real_
  }

  parse_chrom_block <- function(block_lines) {
    wl_line <- stringr::str_subset(block_lines, "^Wavelength\\(nm\\)")
    wavelength <- if (length(wl_line) > 0) as.numeric(stringr::str_extract(wl_line[1], "[0-9]+")) else NA_real_

    data_start <- grep("^R\\.Time \\(min\\)\\tIntensity", block_lines)
    if (length(data_start) == 0) return(NULL)

    data_lines <- block_lines[(data_start + 1):length(block_lines)] %>%
      stringr::str_replace_all(",", ".") %>%
      stringr::str_subset("^[0-9]+\\.[0-9]+\\t-?[0-9]+(\\.[0-9]+)?$")
    if (length(data_lines) == 0) return(NULL)

    chrom <- readr::read_tsv(
      paste(data_lines, collapse = "\n"),
      col_names = c("time", "signal"),
      col_types = readr::cols(time = readr::col_double(), signal = readr::col_double()),
      progress = FALSE
    )
    list(wavelength = wavelength, chromatogram = chrom)
  }

  multi_starts <- grep("^\\[PDA Multi Chromatogram\\(Ch[0-9]+\\)\\]", lines)
  channels <- list()

  if (length(multi_starts) > 0) {
    block_ends <- c(multi_starts[-1] - 1, length(lines))
    for (i in seq_along(multi_starts)) {
      ch_match <- stringr::str_match(lines[multi_starts[i]], "Ch([0-9]+)")
      if (is.na(ch_match[1, 2])) next
      ch_key <- paste0("Ch", ch_match[1, 2])
      parsed <- parse_chrom_block(lines[multi_starts[i]:block_ends[i]])
      if (!is.null(parsed)) channels[[ch_key]] <- parsed
    }
  } else {
    # Single-channel export: no [PDA Multi Chromatogram] wrapper, one global table
    parsed <- parse_chrom_block(lines)
    if (!is.null(parsed)) channels[["Ch1"]] <- parsed
  }

  if (length(channels) == 0) {
    stop("No chromatogram data found (no 'R.Time (min)\tIntensity' section) in: ", basename(file))
  }

  peak_starts <- grep("^\\[Peak Table\\(PDA-Ch[0-9]+\\)\\]", lines)
  section_starts <- grep("^\\[", lines)

  peaks <- purrr::map_dfr(peak_starts, function(idx) {
    ch_match <- stringr::str_match(lines[idx], "PDA-Ch([0-9]+)")
    if (is.na(ch_match[1, 2])) return(NULL)
    ch_key <- paste0("Ch", ch_match[1, 2])
    wavelength <- channels[[ch_key]]$wavelength
    if (is.null(wavelength)) wavelength <- NA_real_

    end_idx <- min(section_starts[section_starts > idx], length(lines) + 1) - 1
    peak_lines <- lines[(idx + 3):end_idx] %>%
      stringr::str_replace_all(",", ".") %>%
      stringr::str_subset("^[0-9]+\\t[0-9.]+\\t[0-9.]+\\t[0-9.]+\\t[0-9.]+\\t[0-9.]+")
    if (length(peak_lines) == 0) return(NULL)

    readr::read_tsv(
      paste(peak_lines, collapse = "\n"), col_names = FALSE,
      col_types = readr::cols(.default = "c"), progress = FALSE
    ) %>%
      dplyr::transmute(
        peak_id = dplyr::row_number(),
        r_time = as.numeric(X2),
        peak_area = as.numeric(X5),
        wavelength = wavelength
      )
  })

  list(injection_volume = injection_volume, channels = channels, peaks = peaks)
}

#' Parse type/std_conc/std_conc_unit/sample_id from an injection filename
#'
#' Duplicated from read_generic_excel_injection.R's read_injection() rather than
#' shared -- same STD_/SMP_/BLK_ convention, kept independent on purpose (see file
#' header). If you fix a bug here, check the other copy too.
parse_shimadzu_filename <- function(fname) {
  # (^|_) rather than a plain ^ anchor -- real instrument-export filenames often prefix
  # the type token with a date (e.g. "2025.07.03_BLK_2-propanol_01.txt"), not just place
  # it first (e.g. the fabricated examples' "BLK_01.txt"). Both are supported.
  type <- dplyr::case_when(
    grepl("(^|_)STD_", fname, ignore.case = TRUE) ~ "std",
    grepl("(^|_)SMP_", fname, ignore.case = TRUE) ~ "smp",
    grepl("(^|_)BLK", fname, ignore.case = TRUE) ~ "blk",
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

  list(type = type, std_conc = std_conc, std_conc_unit = std_conc_unit, sample_id = sample_id)
}

#' Read one Shimadzu .txt injection into the shared injection list shape
#'
#' @param file Path to the raw .txt export
#' @param wavelength Which channel's Wavelength(nm) to use for `chromatogram`. Required
#'   if the file has more than one channel; optional (auto-detected) if it has exactly
#'   one. Every peak from every channel's peak table is still included in `peaks`
#'   (tagged by its own `wavelength`), regardless of this argument.
#' @param analyte,injection_date,target_rt,rt_window_min,rt_window_max,sample_dilution
#'   Not present in the raw export -- supplied by the caller (normally via
#'   read_shimadzu_experiment()'s metadata_file, one row per injection). Left as NA/1 by
#'   default so this function is still usable on its own (e.g. by plot_chromatograms.R,
#'   which only needs `chromatogram`/`peaks` and doesn't care about any of these) without
#'   requiring a metadata_file -- process_shimadzu_purity.R/std_curve.R still get them
#'   from read_shimadzu_experiment(), which enforces they're present via metadata_file's
#'   required columns regardless of these defaults.
read_shimadzu_injection <- function(
    file, analyte = NA_character_, injection_date = NA_character_,
    target_rt = NA_real_, rt_window_min = NA_real_, rt_window_max = NA_real_,
    wavelength = NULL, sample_dilution = 1
) {
  fname <- basename(file)
  base_name <- tools::file_path_sans_ext(fname)
  parsed_name <- parse_shimadzu_filename(fname)
  raw <- parse_shimadzu_txt(file)

  if (is.null(wavelength)) {
    if (length(raw$channels) != 1) {
      available <- paste(purrr::map_dbl(raw$channels, "wavelength"), collapse = ", ")
      stop(fname, " has ", length(raw$channels), " channels -- pass `wavelength` to pick one (available: ", available, ")")
    }
    wavelength <- raw$channels[[1]]$wavelength
  }

  ch_match <- purrr::keep(raw$channels, ~ isTRUE(.x$wavelength == wavelength))
  if (length(ch_match) == 0) {
    available <- paste(purrr::map_dbl(raw$channels, "wavelength"), collapse = ", ")
    stop(fname, ": no channel found at wavelength ", wavelength, " (available: ", available, ")")
  }

  list(
    file = fname,
    base_name = base_name,
    type = parsed_name$type,
    std_conc = parsed_name$std_conc,
    std_conc_unit = parsed_name$std_conc_unit,
    sample_id = parsed_name$sample_id,
    wavelength = wavelength,
    chromatogram = ch_match[[1]]$chromatogram,
    peaks = raw$peaks,
    meta = list(
      analyte = analyte,
      injection_date = injection_date,
      injection_volume = raw$injection_volume,
      sample_dilution = sample_dilution,
      target_rt = target_rt,
      rt_window_min = rt_window_min,
      rt_window_max = rt_window_max
    )
  )
}

#' Read every .txt injection in a folder, joined against a per-experiment metadata CSV
#'
#' @param raw_dir Folder of raw .txt exports, one per injection
#' @param metadata_file CSV with one row per injection: filename, analyte,
#'   injection_date, target_rt, rt_window_min, rt_window_max, sample_dilution
#' @param wavelength Passed through to read_shimadzu_injection() for every file
#' @return Named list of injections, named by filename
read_shimadzu_experiment <- function(raw_dir, metadata_file, wavelength = NULL) {
  files <- list.files(raw_dir, pattern = "\\.txt$", full.names = TRUE)
  if (length(files) == 0) {
    stop("No .txt files found in ", raw_dir)
  }

  meta_table <- readr::read_csv(metadata_file, show_col_types = FALSE, col_types = readr::cols(.default = "c"))
  required_cols <- c("filename", "analyte", "injection_date", "target_rt", "rt_window_min", "rt_window_max", "sample_dilution")
  missing_cols <- setdiff(required_cols, names(meta_table))
  if (length(missing_cols) > 0) {
    stop(metadata_file, " is missing column(s): ", paste(missing_cols, collapse = ", "))
  }

  injections <- purrr::map(files, function(f) {
    row <- meta_table[meta_table$filename == basename(f), ]
    if (nrow(row) != 1) {
      stop("Expected exactly one metadata row for ", basename(f), " in ", metadata_file, ", found ", nrow(row))
    }
    read_shimadzu_injection(
      f,
      analyte = row$analyte[1],
      injection_date = row$injection_date[1],
      target_rt = as.numeric(row$target_rt[1]),
      rt_window_min = as.numeric(row$rt_window_min[1]),
      rt_window_max = as.numeric(row$rt_window_max[1]),
      wavelength = wavelength,
      sample_dilution = as.numeric(row$sample_dilution[1])
    )
  })
  purrr::set_names(injections, basename(files))
}

#' Check that every injection in an experiment agrees on shared, method-level fields
#'
#' Duplicated from read_generic_excel_injection.R -- see that file's copy for the
#' canonical version; kept independent here on purpose (see file header).
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
