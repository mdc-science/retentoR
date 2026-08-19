# run_example.R
#
# Runs the standard-curve and purity workflows against REAL Shimadzu LabSolutions .txt
# exports (not fabricated, unlike every other examples/ folder) -- a 2025.07.03 HPLC-DAD
# run of a peptide, 3 standard levels (8.875/17.75/35.5 ug, a clean 2x dilution series),
# 1 blank, and 2 replicate injections of one real sample.
#
# The only change from the original raw export files: every mention of the real project
# codename and the real standard compound's internal lab code has been replaced with
# "Compound1"/"Compound1-Std" throughout (Sample Name/ID fields, and the Windows file
# paths LabSolutions embeds in its own header) -- nothing about the actual chromatogram
# data, peak table, or injection volume was touched. See CLAUDE.md for exactly what was
# substituted and why, and examples/example_run_shimadzu/ for a similarly-shaped but
# fully fabricated dataset if you'd rather not use real data as a reference.
#
# target_rt/rt_window_min/rt_window_max in injection_metadata.csv are an interpretation,
# not something recorded in the original experiment: peak #7/8 at r_time ~15.2-15.5 min
# is unambiguously the analyte of interest (its area scales ~linearly with the known 2x
# standard-concentration series: ~1.24M -> ~2.48M -> ~4.95M), and 8-25 min was chosen to
# bracket it while excluding early solvent-front peaks (<5 min) and late minor peaks
# (>26 min) -- adjust if you know the real intended window.

library(here)
library(tidyverse)

experiment_dir <- here("examples", "example_run_shimadzu_real", "experimental_data", "001_compound1_batch1")
wavelength <- 280   # this run only has one PDA channel, so this is technically optional
                     # (would be auto-detected), but set explicitly for clarity

source(here("process_shimadzu_std_curve.R"))
source(here("process_shimadzu_purity.R"))
source(here("plot_chromatograms.R"))

out_dir <- file.path(experiment_dir, "processed_data", "Compound1")

p_combined <- plot_chromatograms(file.path(experiment_dir, "raw_data"), combined = TRUE, wavelength = wavelength, annotate_purity_top_n = 3)
ggsave(file.path(out_dir, "quicklook_combined.pdf"), p_combined, width = 10, height = 6)

p_facets <- plot_chromatograms(file.path(experiment_dir, "raw_data"), combined = FALSE, wavelength = wavelength)
ggsave(file.path(out_dir, "quicklook_facets.pdf"), p_facets, width = 10, height = 6)

message("Real-data Shimadzu example run complete. Outputs in: ", out_dir)
