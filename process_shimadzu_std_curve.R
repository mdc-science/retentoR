# process_shimadzu_std_curve.R
#
# Fits a standard curve from STD injections' peak area at `target_rt`, back-calculates
# SMP concentrations, and writes a summary PDF + CSV outputs, from native Shimadzu
# LabSolutions .txt exports (see read_shimadzu_injection.R for the format and why a
# companion metadata CSV is needed).
#
# Caller must define, before sourcing:
#   experiment_dir <- here("experimental_data", "001_my_experiment")
# ...a folder containing:
#   raw_data/                  one .txt per injection (STD_/SMP_/BLK_ filename prefix)
#   injection_metadata.csv     one row per injection: filename, analyte, injection_date,
#                               target_rt, rt_window_min, rt_window_max, sample_dilution
# Optionally define `wavelength` before sourcing, if any injection has more than one
# detector channel (otherwise required per-file, see read_shimadzu_injection.R). Every
# injection must share one `analyte`, `injection_date`, `target_rt`, `rt_window_min`,
# `rt_window_max` (conditions never vary within an experiment, see the metadata CSV
# note above).
#
# Writes, to experiment_dir/processed_data/<analyte>/:
#   <date>_<analyte>_summary_results.pdf          chromatograms + signal + std curve + calc values
#   <date>_<analyte>_levels.csv                    back-calculated sample concentrations (if any SMP)
#   <date>_<analyte>_analytical_performance.csv    slope, intercept, R2, LoD, LoQ
#
# Every STD injection must share one injection_volume (parsed from each .txt's own
# "Injection Volume" line, not the metadata CSV — see read_shimadzu_injection.R). Each
# SMP's peak area is scaled by std_injection_volume / its own injection_volume before
# back-calculation, so a sample injected at a different volume than the standards still
# gets a correct predicted_conc (assumes peak area is linear in injected volume).
#
# Everything from here down (fits, plots, CSV outputs) is intentionally identical to
# process_generic_excel_std_curve.R -- the only difference between the two scripts is
# how `injections` gets built above. If you fix a bug in the analysis/plotting logic,
# fix it in both scripts (this repo duplicates rather than shares per-format process
# scripts, matching plateReadeR's convention -- see CLAUDE.md).

library(here)
library(tidyverse)
library(scales)
library(conflicted)
library(ggthemes)
library(ggpmisc)
library(ggrepel)
library(patchwork)
library(RColorBrewer)
conflicts_prefer(here::here)
conflicts_prefer(dplyr::filter)
conflicts_prefer(ggplot2::annotate)

source(here("read_shimadzu_injection.R"))

if (!exists("experiment_dir")) {
  stop("Define `experiment_dir` (path to the experiment folder) before sourcing process_shimadzu_std_curve.R")
}
if (!exists("wavelength")) wavelength <- NULL

raw_dir <- here(experiment_dir, "raw_data")
metadata_file <- here(experiment_dir, "injection_metadata.csv")
injections <- read_shimadzu_experiment(raw_dir, metadata_file, wavelength = wavelength)
shared_meta <- check_shared_meta(injections)
analyte <- shared_meta$analyte
injection_date <- shared_meta$injection_date
target_rt <- as.numeric(shared_meta$target_rt)
rt_window_min <- as.numeric(shared_meta$rt_window_min)
rt_window_max <- as.numeric(shared_meta$rt_window_max)

out_dir <- here(experiment_dir, "processed_data", analyte)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# ---- Peak area at target_rt for every injection (closest peak within the rt window) ----
# Restricted to the injection's own chromatogram wavelength, not just the rt window --
# a multi-channel export's combined peak table spans several detector channels, and
# pooling peak areas measured at different wavelengths into one "total area" isn't
# chemically meaningful (different molar absorptivity per wavelength).
target_peak <- function(inj) {
  win <- inj$peaks %>% dplyr::filter(wavelength == inj$wavelength, r_time >= rt_window_min, r_time <= rt_window_max)
  if (nrow(win) == 0) {
    return(tibble(peak_id = NA_integer_, r_time = NA_real_, peak_area = NA_real_))
  }
  win[which.min(abs(win$r_time - target_rt)), c("peak_id", "r_time", "peak_area")]
}

injection_summary <- purrr::map_dfr(injections, function(inj) {
  tp <- target_peak(inj)
  tibble(
    sample_id = inj$base_name,
    type = inj$type,
    std_conc = inj$std_conc,
    std_conc_unit = inj$std_conc_unit,
    sample_dilution = if (is.null(inj$meta$sample_dilution) || is.na(inj$meta$sample_dilution)) 1 else inj$meta$sample_dilution,
    injection_volume = inj$meta$injection_volume,
    peak_id = tp$peak_id,
    r_time = tp$r_time,
    peak_area = tp$peak_area
  )
})

df_std <- injection_summary %>% dplyr::filter(type == "std")
df_smp <- injection_summary %>% dplyr::filter(type == "smp")
has_samples <- nrow(df_smp) > 0
conc_unit <- df_std$std_conc_unit[1]

if (nrow(df_std) < 2) {
  stop("Need at least two STD injections with a peak inside the rt window to fit a standard curve.")
}

# All STD injections must share one injection_volume — it's the calibration curve's
# reference volume, against which every sample's peak area gets scaled below so that a
# sample injected at a different volume than the standards still back-calculates
# correctly (peak area is assumed linear in injected volume, standard for HPLC-DAD
# within the linear range).
std_injection_volume <- unique(df_std$injection_volume)
if (length(std_injection_volume) != 1 || is.na(std_injection_volume)) {
  stop(
    "All STD injections must share one injection_volume (the calibration reference volume), found: ",
    paste(std_injection_volume, collapse = ", ")
  )
}
if (has_samples && any(is.na(df_smp$injection_volume))) {
  stop("Every SMP injection needs an injection_volume (used to scale its peak area to the STD reference volume).")
}

# ---- Fits ----
# Back-calculation model (concentration as a function of peak area)
std_curve <- lm(std_conc ~ peak_area, data = df_std)
# Used only for its residual SE, to compute LoD/LoQ in concentration units
lm_lod <- lm(peak_area ~ std_conc, data = df_std)
sy_x <- summary(lm_lod)$sigma
slope_lod <- coef(lm_lod)[["std_conc"]]
LOD <- 3.3 * sy_x / slope_lod
LOQ <- 10 * sy_x / slope_lod
LOD_area <- as.numeric(predict(lm_lod, newdata = tibble(std_conc = LOD)))
LOQ_area <- as.numeric(predict(lm_lod, newdata = tibble(std_conc = LOQ)))

std_min_y <- min(df_std$peak_area, na.rm = TRUE)
std_max_y <- max(df_std$peak_area, na.rm = TRUE)

# ---- Back-calculate sample concentrations ----
# Each sample's peak area is scaled to what it would have been at std_injection_volume
# before it's compared against the curve, so differing STD/SMP injection volumes don't
# bias predicted_conc (see the injection_volume check above).
if (has_samples) {
  df_smp <- df_smp %>%
    dplyr::mutate(
      volume_adjustment = std_injection_volume / injection_volume,
      peak_area_adjusted = peak_area * volume_adjustment,
      predicted_conc = predict(std_curve, newdata = tibble(peak_area = peak_area_adjusted)),
      final_conc = predicted_conc * sample_dilution,
      extrapolated = peak_area_adjusted < std_min_y * 1.1 | peak_area_adjusted > std_max_y
    )
}

# ---- Shared visual language (mirrors plateReadeR's plotting style) ----
# No assay_metadata-equivalent file to source a per-assay palette from here, so these
# are fixed module-level constants rather than user-configurable, unlike plateReadeR's
# assay_metadata$color_low/color_high.
color_low <- "gray85"
color_high <- "royalblue4"

theme_summary <- theme_few(base_size = 8) +
  theme(
    axis.text.x         = element_text(color = "gray15"),
    axis.text.y         = element_text(color = "gray15"),
    axis.title.x        = element_text(face = "bold"),
    axis.title.y        = element_text(face = "bold"),
    axis.line           = element_line(linewidth = 0),
    panel.border        = element_rect(linewidth = 0.4, color = "gray15"),
    axis.ticks.length.x = unit(0.5, "mm"),
    axis.ticks.length.y = unit(0.5, "mm")
  )

remove_titles <- function(p) {
  if (inherits(p, "gg")) p + labs(title = NULL, subtitle = NULL) else p
}

# ---- Chromatogram panels ----
chrom_df_for <- function(types) {
  purrr::imap_dfr(injections, function(inj, fname) {
    if (!(inj$type %in% types)) return(NULL)
    inj$chromatogram %>% dplyr::mutate(file = inj$base_name)
  })
}

shift_chromatograms <- function(df, shift = 0.01) {
  file_levels <- unique(df$file)
  shift_map <- tibble(file = file_levels, shift_value = seq(0, by = shift, length.out = length(file_levels)))
  df %>% dplyr::left_join(shift_map, by = "file") %>% dplyr::mutate(signal_shifted = signal + shift_value)
}

plot_chrom_group <- function(df, title) {
  file_levels <- unique(df$file)
  colors <- colorRampPalette(brewer.pal(9, "Spectral"))(length(file_levels))
  ggplot(df, aes(time, signal_shifted, color = factor(file, levels = file_levels))) +
    geom_line(linewidth = 0.4) +
    scale_color_manual(values = colors) +
    labs(title = title, x = "Time (min)", y = "Signal (shifted)", color = NULL) +
    theme_summary +
    theme(legend.position = "bottom", legend.text = element_text(size = 6))
}

p_chrom_std_blk <- plot_chrom_group(shift_chromatograms(chrom_df_for(c("std", "blk"))), "Blanks & Standards")
p_chrom_smp <- if (has_samples) {
  plot_chrom_group(shift_chromatograms(chrom_df_for("smp")), "Samples")
} else {
  patchwork::plot_spacer()
}

# ---- Peak area vs sample_id, with LoD/LoQ + STD-range reference lines ----
# SMP points plot at their volume-adjusted peak area (see back-calculation above), so
# they're on the same basis as the STD-range/LoD/LoQ reference lines below — a sample
# injected at a smaller volume than the standards shouldn't visually read as "below LoD"
# once that's corrected for.
injection_summary_plot <- injection_summary %>%
  dplyr::left_join(
    if (has_samples) dplyr::select(df_smp, sample_id, peak_area_adjusted) else tibble(sample_id = character(), peak_area_adjusted = double()),
    by = "sample_id"
  ) %>%
  dplyr::mutate(peak_area_plot = dplyr::coalesce(peak_area_adjusted, peak_area))

p_signal <- ggplot(injection_summary_plot, aes(x = sample_id, y = peak_area_plot)) +
  geom_point(
    aes(fill = peak_area_plot),
    shape = 21, size = 2.5, stroke = 0.25, alpha = 1, color = "black"
  ) +
  scale_fill_gradient(low = color_low, high = color_high) +
  geom_point(
    data = subset(injection_summary_plot, peak_area_plot < LOD_area | peak_area_plot > std_max_y),
    shape = 21, size = 2.5, stroke = 0.25,
    fill = "gray85", color = "gray85", alpha = 1
  ) +
  geom_hline(
    yintercept = c(std_max_y, std_min_y),
    linetype = "dashed", linewidth = 0.25, alpha = 0.5
  ) +
  geom_hline(yintercept = LOD_area, linetype = "dashed", linewidth = 0.25, color = "firebrick") +
  geom_hline(yintercept = LOQ_area, linetype = "dashed", linewidth = 0.25, color = "royalblue4") +
  annotate("text", x = 0.5, y = LOD_area, label = "Linear LoD",
           hjust = 0, vjust = -0.5, color = "firebrick", size = 2, check_overlap = TRUE) +
  annotate("text", x = 0.5, y = LOQ_area, label = "Linear LoQ",
           hjust = 0, vjust = -0.5, color = "royalblue4", size = 2, check_overlap = TRUE) +
  labs(title = "Peak area by injection", subtitle = paste(injection_date, "- Peak area"), x = "Injection", y = "Peak area") +
  theme_summary +
  theme(legend.position = "none", axis.text.x = element_text(angle = 90, hjust = 0.5, vjust = 0.5))

# ---- Standard curve ----
# Averaged per concentration, purely for the smooth/equation display — std_curve (above)
# is what's actually used for back-calculation, kept intentionally separate.
df_std_avg <- df_std %>%
  dplyr::group_by(std_conc) %>%
  dplyr::summarise(peak_area = mean(peak_area, na.rm = TRUE), .groups = "drop")

p_std_curve <- ggplot(df_std, aes(x = std_conc, y = peak_area)) +
  geom_smooth(
    data = df_std_avg,
    aes(x = std_conc, y = peak_area),
    formula = y ~ x, method = "lm", se = TRUE,
    colour = scales::alpha("black", 0.75), linewidth = 0.25, linetype = "dashed",
    fill = "gray85", inherit.aes = FALSE
  ) +
  geom_point(
    aes(fill = peak_area),
    shape = 21, size = 4, stroke = 0.25, alpha = 0.75, color = "black"
  ) +
  scale_fill_gradient(low = color_low, high = color_high) +
  ggpmisc::stat_poly_eq(
    data = df_std_avg, formula = y ~ x, geom = "text_npc",
    aes(x = std_conc, y = peak_area, label = after_stat(rr.label)),
    label.y = 0.95, size = 5, vjust = 0.5, rr.digits = 4, inherit.aes = FALSE
  ) +
  ggpmisc::stat_poly_eq(
    data = df_std_avg, formula = y ~ x, geom = "text_npc",
    aes(x = std_conc, y = peak_area, label = after_stat(eq.label)),
    label.y = 0.05, label.x = 0.95, size = 5, vjust = 0.5, inherit.aes = FALSE
  ) +
  annotate("text_npc", npcx = 0.05, npcy = 0.88,
           label = paste("LoD =", round(LOD, 4), conc_unit), check_overlap = TRUE, size = 5, vjust = 0.5) +
  annotate("text_npc", npcx = 0.05, npcy = 0.81,
           label = paste("LoQ =", round(LOQ, 4), conc_unit), check_overlap = TRUE, size = 5, vjust = 0.5) +
  labs(
    title = "Standard curve", subtitle = paste(injection_date, "- Standard curve"),
    x = paste0("Concentration (", conc_unit, ")"), y = "Peak area"
  ) +
  theme_summary +
  theme(legend.position = "none")

# ---- Calculated sample values ----
p_calc_value <- if (has_samples) {
  ggplot(df_smp, aes(x = fct_reorder(sample_id, final_conc, .fun = mean), y = final_conc, fill = final_conc)) +
    geom_point(color = "black", size = 2.5, shape = 21, alpha = 0.85, stroke = 0.25) +
    scale_fill_gradient(low = "royalblue", high = "tomato") +
    stat_summary(
      fun = mean, geom = "point", shape = 23, size = 2, alpha = 0.5,
      color = "gray15", fill = "gold", position = position_nudge(x = 0.15, y = 0)
    ) +
    geom_point(
      data = dplyr::filter(df_smp, extrapolated),
      shape = 24, size = 3, stroke = 0.7, fill = "orange", color = "darkorange"
    ) +
    ggrepel::geom_text_repel(
      data = dplyr::filter(df_smp, extrapolated),
      aes(label = sample_id), size = 2, color = "darkorange", min.segment.length = 0
    ) +
    labs(
      title = "Calculated sample concentrations", subtitle = paste(injection_date, "-", analyte, "values across samples"),
      x = "Sample", y = paste0(analyte, " (", conc_unit, ")")
    ) +
    theme_summary +
    theme(legend.position = "none", axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))
} else {
  patchwork::plot_spacer()
}

# ---- Assemble summary figure ----
p_summary <- (remove_titles(p_chrom_std_blk) | remove_titles(p_chrom_smp)) /
  (remove_titles(p_signal) | remove_titles(p_std_curve) | remove_titles(p_calc_value)) +
  patchwork::plot_annotation(
    title = paste(analyte, "assay"),
    subtitle = paste(injection_date, "- Summary results"),
    caption = raw_dir
  )

ggsave(
  file.path(out_dir, paste0(injection_date, "_", analyte, "_summary_results.pdf")),
  p_summary, width = 14, height = 9
)

# ---- CSV outputs ----
analytical_performance <- tibble(
  analyte = analyte,
  target_rt = target_rt,
  n_std = nrow(df_std),
  slope = coef(std_curve)[["peak_area"]],
  intercept = coef(std_curve)[["(Intercept)"]],
  r_squared = summary(lm(peak_area ~ std_conc, data = df_std))$r.squared,
  lod = LOD,
  loq = LOQ
)
write_csv(analytical_performance, file.path(out_dir, paste0(injection_date, "_", analyte, "_analytical_performance.csv")))

if (has_samples) {
  levels_out <- df_smp %>%
    dplyr::select(
      sample_id, peak_id, r_time, peak_area, injection_volume, volume_adjustment,
      peak_area_adjusted, sample_dilution, predicted_conc, final_conc, extrapolated
    )
  write_csv(levels_out, file.path(out_dir, paste0(injection_date, "_", analyte, "_levels.csv")))
}

message(
  "Standard curve analysis complete for ", analyte, ": ",
  nrow(df_std), " standards, ", nrow(df_smp), " samples. LoD = ", round(LOD, 4),
  " ", conc_unit, ", LoQ = ", round(LOQ, 4), " ", conc_unit
)
