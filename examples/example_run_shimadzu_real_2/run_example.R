# run_example.R
#
# Runs the standard-curve workflow against a second, independent set of REAL Shimadzu
# LabSolutions .txt exports (not fabricated) -- a 2026.01.14/2026.01.19 HPLC-DAD run of
# a small molecule ("Compound1" here; see below), 8 standard levels (0.00878125-1 mM, a
# clean ~2x dilution series) x2 replicates, 2 blanks, and 2 extraction samples (EXT1/
# EXT2) x2 replicates each. Single peak per injection at r_time ~2.9 min (0 peaks for
# blanks) -- purity analysis doesn't apply to this method, so only the std-curve
# workflow + a quick-look chromatogram plot are run, unlike example_run_shimadzu_real/.
#
# Anonymized like example_run_shimadzu_real/: the real compound name and the operator's
# name (both found only in the Windows file paths LabSolutions embeds in its own header
# -- Data File/Method File/Batch File lines) were replaced with "Compound1"/"Analyst1"
# throughout, confirmed with a case-insensitive grep for both strings across every
# committed file. Nothing about the actual chromatogram trace, peak table, or injection
# volume was altered.
#
# target_rt/rt_window_min/rt_window_max in injection_metadata.csv reflect the single
# real peak present in every injection (~2.88-2.93 min); 2.5-3.3 brackets it with margin.
# sample_dilution (5 * (1000/7) ~= 714.29) is the real extraction/dilution factor used
# for EXT1/EXT2, applied to both.
#
# STD injection_volume = 50 uL, SMP injection_volume = 10 uL (from each file's own
# "Injection Volume" line) -- a real-world volume mismatch between standards and
# samples that example_run_shimadzu_real/ doesn't exercise (there volume_adjustment=1
# throughout), so this is useful coverage for that code path in
# process_shimadzu_std_curve.R.

library(here)
library(tidyverse)

experiment_dir <- here("examples", "example_run_shimadzu_real_2", "experimental_data", "001_compound1_stdcurve")
wavelength <- 315  # single PDA channel, set explicitly for clarity

source(here("process_shimadzu_std_curve.R"))
source(here("plot_chromatograms.R"))

out_dir <- file.path(experiment_dir, "processed_data", "Compound1")

p_combined <- plot_chromatograms(file.path(experiment_dir, "raw_data"), combined = TRUE, wavelength = wavelength)
ggsave(file.path(out_dir, "quicklook_combined.pdf"), p_combined, width = 10, height = 6)

message("Second real-data Shimadzu example run complete. Outputs in: ", out_dir)
