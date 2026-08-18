# plot_chromatograms.R
#
# Quick-look plotting for one or more generic-Excel injection workbooks (see CLAUDE.md,
# "Generic Excel input format"). Unlike process_generic_excel_*.R, this doesn't fit
# anything or write output files — it just draws the traces so you can eyeball them.
#
# Source this file, then call:
#   plot_chromatograms(path, combined = TRUE, shift = 0.01, annotate_purity_top_n = NULL)
#
#   path                    a single .xlsx file, or a folder containing several
#   combined                TRUE  = one panel, all traces vertically shifted & overlaid
#                           FALSE = one facet per file, no shift (each keeps its own y-scale)
#   shift                   vertical offset between traces when combined = TRUE
#   annotate_purity_top_n   if set to N, label the top N peaks (by peak_area, as a % of
#                           that injection's total peak area) directly on the trace, at
#                           their retention time. Not restricted to any rt window — this
#                           is a quick-look label, not the formal purity calculation done
#                           by process_generic_excel_purity.R.

library(here)
library(tidyverse)
library(readxl)
library(conflicted)
library(ggthemes)
library(ggrepel)
library(RColorBrewer)
conflicts_prefer(here::here)
conflicts_prefer(dplyr::filter)

source(here("read_generic_excel_injection.R"))

plot_chromatograms <- function(
    path,
    combined = TRUE,
    shift = 0.01,
    palette = "Spectral",
    annotate_purity_top_n = NULL
) {
  files <- if (dir.exists(path)) {
    list.files(path, pattern = "\\.xlsx$", full.names = TRUE)
  } else if (file.exists(path)) {
    path
  } else {
    stop("Path not found: ", path)
  }
  if (length(files) == 0) stop("No .xlsx files found at: ", path)

  injections <- purrr::map(files, read_injection) %>% purrr::set_names(basename(files))

  chrom_df <- purrr::imap_dfr(injections, function(inj, fname) {
    inj$chromatogram %>% dplyr::mutate(file = inj$base_name)
  })
  file_levels <- unique(chrom_df$file)

  purity_labels <- NULL
  if (!is.null(annotate_purity_top_n)) {
    purity_labels <- purrr::imap_dfr(injections, function(inj, fname) {
      total_area <- sum(inj$peaks$peak_area, na.rm = TRUE)
      top_peaks <- inj$peaks %>%
        dplyr::mutate(purity_pct = 100 * peak_area / total_area) %>%
        dplyr::arrange(dplyr::desc(peak_area)) %>%
        dplyr::slice_head(n = annotate_purity_top_n)
      if (nrow(top_peaks) == 0) return(NULL)
      top_peaks %>%
        dplyr::rowwise() %>%
        dplyr::mutate(
          signal_at_peak = inj$chromatogram$signal[which.min(abs(inj$chromatogram$time - r_time))],
          file = inj$base_name,
          label = paste0(round(purity_pct, 1), "%")
        ) %>%
        dplyr::ungroup()
    })
  }

  if (combined) {
    shift_map <- tibble(file = file_levels, shift_value = seq(0, by = shift, length.out = length(file_levels)))
    chrom_df <- chrom_df %>% dplyr::left_join(shift_map, by = "file") %>% dplyr::mutate(signal_shifted = signal + shift_value)

    n_colors <- length(file_levels)
    available_colors <- RColorBrewer::brewer.pal.info[palette, "maxcolors"]
    base_colors <- RColorBrewer::brewer.pal(min(max(n_colors, 3), available_colors), palette)
    colors <- colorRampPalette(base_colors)(n_colors)

    p <- ggplot(chrom_df, aes(time, signal_shifted, color = factor(file, levels = file_levels))) +
      geom_line(linewidth = 0.4) +
      scale_color_manual(values = colors) +
      labs(title = "HPLC-DAD Chromatograms", x = "Time (min)", y = "Signal (shifted, AU)", color = "Injection") +
      theme_few()

    if (!is.null(purity_labels)) {
      purity_labels <- purity_labels %>%
        dplyr::left_join(shift_map, by = "file") %>%
        dplyr::mutate(signal_shifted = signal_at_peak + shift_value)
      p <- p + ggrepel::geom_label_repel(
        data = purity_labels,
        aes(x = r_time, y = signal_shifted, label = label, color = factor(file, levels = file_levels)),
        size = 3, show.legend = FALSE, seed = 1
      )
    }
  } else {
    p <- ggplot(chrom_df, aes(time, signal)) +
      geom_line(linewidth = 0.4, color = "royalblue4") +
      facet_wrap(~ factor(file, levels = file_levels), scales = "free_y") +
      labs(title = "HPLC-DAD Chromatograms", x = "Time (min)", y = "Signal (AU)") +
      theme_few()

    if (!is.null(purity_labels)) {
      p <- p + ggrepel::geom_label_repel(
        data = purity_labels,
        aes(x = r_time, y = signal_at_peak, label = label),
        size = 3, seed = 1
      )
    }
  }

  p
}
