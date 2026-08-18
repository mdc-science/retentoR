# run_example.R
#
# Runs the standard-curve and purity workflows against fabricated native Shimadzu
# LabSolutions .txt exports, plus two quick-look chromatogram plots. Every injection
# has two detector channels (254 nm, the one actually used below, and a 280 nm "decoy"
# with deliberately different values, to exercise wavelength-based channel selection).

library(here)
library(tidyverse)

experiment_dir <- here("examples", "example_run_shimadzu", "experimental_data", "001_fabricated_pep_shimadzu")
wavelength <- 254

source(here("process_shimadzu_std_curve.R"))
source(here("process_shimadzu_purity.R"))
source(here("plot_chromatograms.R"))

out_dir <- file.path(experiment_dir, "processed_data", "PEP")

# plot_chromatograms() only knows the generic-Excel workbook format today (see
# CLAUDE.md) -- it doesn't yet dispatch on file extension to pick a Shimadzu reader.
# Build its chromatogram traces manually here instead of extending that script, to keep
# this example scoped to what's actually been ported so far.
chrom_df <- purrr::imap_dfr(injections, function(inj, fname) {
  inj$chromatogram %>% mutate(file = inj$base_name)
})
file_levels <- unique(chrom_df$file)
shift_map <- tibble(file = file_levels, shift_value = seq(0, by = 0.01, length.out = length(file_levels)))
chrom_df <- chrom_df %>% left_join(shift_map, by = "file") %>% mutate(signal_shifted = signal + shift_value)

p_combined <- ggplot(chrom_df, aes(time, signal_shifted, color = factor(file, levels = file_levels))) +
  geom_line(linewidth = 0.4) +
  labs(title = "HPLC-DAD Chromatograms (Shimadzu, 254 nm)", x = "Time (min)", y = "Signal (shifted)", color = "Injection") +
  theme_few()
ggsave(file.path(out_dir, "quicklook_combined.pdf"), p_combined, width = 10, height = 6)

message("Shimadzu example run complete. Outputs in: ", out_dir)
