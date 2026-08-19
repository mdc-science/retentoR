# run_example.R
#
# Runs the standard-curve and purity workflows against fabricated native Shimadzu
# LabSolutions .txt exports, plus two quick-look chromatogram plots via
# plot_chromatograms() (which dispatches on file extension, so this is the same call as
# for the generic-Excel examples, just pointed at a folder of .txt files). Every
# injection has two detector channels (254 nm, the one actually used below via
# `wavelength`, and a 280 nm "decoy" with deliberately different values, to exercise
# wavelength-based channel selection).

library(here)
library(tidyverse)

experiment_dir <- here("examples", "example_run_shimadzu", "experimental_data", "001_fabricated_pep_shimadzu")
wavelength <- 254

source(here("process_shimadzu_std_curve.R"))
source(here("process_shimadzu_purity.R"))
source(here("plot_chromatograms.R"))

out_dir <- file.path(experiment_dir, "processed_data", "PEP")

p_combined <- plot_chromatograms(file.path(experiment_dir, "raw_data"), combined = TRUE, wavelength = wavelength, annotate_purity_top_n = 2)
ggsave(file.path(out_dir, "quicklook_combined.pdf"), p_combined, width = 10, height = 6)

p_facets <- plot_chromatograms(file.path(experiment_dir, "raw_data"), combined = FALSE, wavelength = wavelength)
ggsave(file.path(out_dir, "quicklook_facets.pdf"), p_facets, width = 10, height = 6)

message("Shimadzu example run complete. Outputs in: ", out_dir)
