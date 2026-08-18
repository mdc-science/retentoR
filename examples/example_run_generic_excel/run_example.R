# run_example.R
#
# Runs the full generic-Excel workflow against the fabricated data built by
# build_fabricated_data.R: standard curve, purity, and two quick-look chromatogram
# plots. Run build_fabricated_data.R first if experimental_data/001_fabricated_pep/
# doesn't exist yet.

library(here)
library(tidyverse)

experiment_dir <- here("examples", "example_run_generic_excel", "experimental_data", "001_fabricated_pep")

source(here("process_generic_excel_std_curve.R"))
source(here("process_generic_excel_purity.R"))
source(here("plot_chromatograms.R"))

out_dir <- file.path(experiment_dir, "processed_data", "PEP")

# No annotate_purity_top_n here — this experiment is a standard curve run, where peak
# purity isn't a meaningful readout. That argument is for purity-method quick-looks.
p_combined <- plot_chromatograms(file.path(experiment_dir, "raw_data"), combined = TRUE)
ggsave(file.path(out_dir, "quicklook_combined.pdf"), p_combined, width = 10, height = 6)

p_facets <- plot_chromatograms(file.path(experiment_dir, "raw_data"), combined = FALSE)
ggsave(file.path(out_dir, "quicklook_facets.pdf"), p_facets, width = 10, height = 6)

message("Example run complete. Outputs in: ", out_dir)
