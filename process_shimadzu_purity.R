# process_shimadzu_purity.R
#
# Computes peak purity (% of total peak area within [rt_window_min, rt_window_max]) for
# every injection in one experiment, from native Shimadzu LabSolutions .txt exports (see
# read_shimadzu_injection.R for the format and why a companion metadata CSV is needed).
#
# Caller must define, before sourcing:
#   experiment_dir <- here("experimental_data", "001_my_experiment")
# ...a folder containing:
#   raw_data/                  one .txt per injection (STD_/SMP_/BLK_ filename prefix)
#   injection_metadata.csv     one row per injection: filename, analyte, injection_date,
#                               target_rt, rt_window_min, rt_window_max, sample_dilution
# Optionally define `wavelength` before sourcing, if any injection has more than one
# detector channel (otherwise required per-file, see read_shimadzu_injection.R).
#
# Writes, to experiment_dir/processed_data/<analyte>/:
#   <date>_<analyte>_purity.csv          one row per peak per injection
#   <date>_<analyte>_purity_summary.csv  one row per injection (purity of the target_rt peak)

library(here)
library(tidyverse)
library(conflicted)
conflicts_prefer(here::here)
conflicts_prefer(dplyr::filter)

source(here("read_shimadzu_injection.R"))

if (!exists("experiment_dir")) {
  stop("Define `experiment_dir` (path to the experiment folder) before sourcing process_shimadzu_purity.R")
}
if (!exists("wavelength")) wavelength <- NULL

raw_dir <- here(experiment_dir, "raw_data")
metadata_file <- here(experiment_dir, "injection_metadata.csv")
injections <- read_shimadzu_experiment(raw_dir, metadata_file, wavelength = wavelength)
shared_meta <- check_shared_meta(injections, fields = c("analyte", "injection_date"))
analyte <- shared_meta$analyte
injection_date <- shared_meta$injection_date

out_dir <- here(experiment_dir, "processed_data", analyte)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# Restricted to the injection's own chromatogram wavelength, not just the rt window --
# a multi-channel export's combined peak table spans several detector channels, and
# pooling peak areas measured at different wavelengths into one "total area" isn't
# chemically meaningful (different molar absorptivity per wavelength).
peaks_in_window <- function(inj) {
  inj$peaks %>%
    dplyr::filter(wavelength == inj$wavelength, r_time >= inj$meta$rt_window_min, r_time <= inj$meta$rt_window_max)
}

# One row per peak per injection
purity_peaks <- purrr::map_dfr(injections, function(inj) {
  win <- peaks_in_window(inj)
  total_area <- sum(win$peak_area, na.rm = TRUE)
  win %>%
    dplyr::mutate(
      purity_pct = 100 * peak_area / total_area,
      sample_id = inj$base_name,
      type = inj$type
    ) %>%
    dplyr::select(sample_id, type, peak_id, r_time, peak_area, wavelength, purity_pct)
})

# One row per injection: purity of the peak closest to target_rt
purity_summary <- purrr::map_dfr(injections, function(inj) {
  win <- peaks_in_window(inj)
  total_area <- sum(win$peak_area, na.rm = TRUE)
  if (nrow(win) == 0) {
    return(tibble::tibble(
      sample_id = inj$base_name, type = inj$type,
      target_peak_id = NA_integer_, target_purity_pct = NA_real_, n_peaks = 0L
    ))
  }
  target <- win[which.min(abs(win$r_time - inj$meta$target_rt)), ]
  tibble::tibble(
    sample_id = inj$base_name,
    type = inj$type,
    target_peak_id = target$peak_id,
    target_purity_pct = 100 * target$peak_area / total_area,
    n_peaks = nrow(win)
  )
})

write_csv(purity_peaks, file.path(out_dir, paste0(injection_date, "_", analyte, "_purity.csv")))
write_csv(purity_summary, file.path(out_dir, paste0(injection_date, "_", analyte, "_purity_summary.csv")))

message("Purity analysis complete: ", length(injections), " injections, analyte '", analyte, "'.")
