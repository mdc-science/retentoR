# retentoR

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21997256.svg)](https://doi.org/10.5281/zenodo.21997256)

**Author:** Daniel Moreira ([danielcarmor@gmail.com](mailto:danielcarmor@gmail.com))  
**Institution:** i3S – Instituto de Investigação e Inovação em Saúde, Porto, Portugal  
**Language:** R

---

## Overview

An R workflow for processing HPLC(-DAD) chromatogram data. Given a chromatogram (time vs. signal) and its peak table for each injection, in a simple instrument-agnostic Excel format, the workflow supports two analyses:

1. **Purity** — for one injection, express each peak in a retention-time window as a percentage of the total peak area in that window.
2. **Standard curve** — fit a calibration curve from a series of standard injections' peak area at a target retention time, back-calculate sample concentrations (correcting for injection volume and dilution), compute LoD/LoQ, and export a multi-panel summary figure.

A third, standalone script draws quick-look chromatogram plots (single file or a whole folder, overlaid or faceted) without running either analysis.

The scripts are `source()`d, not installed as a package — see [`examples/`](examples/) for runnable, fully self-contained demonstrations of each.

This repo currently supports one raw-data format: a plain Excel workbook per injection (see the sheet layout in each example). Parsing native Shimadzu LabSolutions `.txt` exports directly is planned but not yet implemented.

---

## File structure

```
retentoR/
├── read_generic_excel_injection.R        # shared workbook parser, sourced by the three scripts below
├── process_generic_excel_purity.R        # purity analysis
├── process_generic_excel_std_curve.R     # standard curve + back-calculation + summary PDF
├── plot_chromatograms.R                  # quick-look chromatogram plotting, standalone
└── examples/
    ├── example_run_generic_excel/            # standard-curve example (fabricated "PEP" standards + samples)
    ├── example_run_generic_excel_purity/     # purity-only example (fabricated synthesis batches, no standards)
    └── example_run_generic_excel_report/     # narrative per-sample R Markdown report, fully self-contained
```

## Input format

Each injection is one `.xlsx` workbook, named with a `STD_<conc>_<unit>`, `SMP_<id>`, or `BLK` prefix, with three sheets:

- **Chromatogram** — cell A1 reads `Wavelength(nm): <value>`; below it, columns `time`, `signal`.
- **Peak Areas** — columns `peak_id`, `r_time`, `peak_area`, `wavelength` (one row per peak).
- **Metadata** — one row: `analyte`, `injection_date`, `injection_volume`, `sample_dilution`, `target_rt`, `rt_window_min`, `rt_window_max`.

An optional `method.xlsx` per experiment (not read by the analysis scripts, provenance only) records the LC gradient and column.

See any folder under `examples/` for concrete, runnable workbooks in this format.

## Status

`v1.0.0` released and archived on Zenodo (see DOI badge above). No package, no automated test suite — each `examples/` subfolder running or knitting without error is the correctness check.
