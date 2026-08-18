# run_example.R
#
# Runs process_generic_excel_purity.R against the fabricated synthesis-batch data built
# by build_fabricated_data.R, plus quick-look chromatogram plots with peak purity labeled
# directly on the trace (relevant here, unlike the standard-curve example). Run
# build_fabricated_data.R first if experimental_data/001_fabricated_synthesis/ doesn't
# exist yet.

library(here)
library(tidyverse)

experiment_dir <- here("examples", "example_run_generic_excel_purity", "experimental_data", "001_fabricated_synthesis")

source(here("process_generic_excel_purity.R"))
source(here("plot_chromatograms.R"))

out_dir <- file.path(experiment_dir, "processed_data", "Compound1")

p_combined <- plot_chromatograms(file.path(experiment_dir, "raw_data"), combined = TRUE, annotate_purity_top_n = 3)
ggsave(file.path(out_dir, "quicklook_combined.pdf"), p_combined, width = 10, height = 6)

p_facets <- plot_chromatograms(file.path(experiment_dir, "raw_data"), combined = FALSE)
ggsave(file.path(out_dir, "quicklook_facets.pdf"), p_facets, width = 10, height = 6)

message("Purity example run complete. Outputs in: ", out_dir)
