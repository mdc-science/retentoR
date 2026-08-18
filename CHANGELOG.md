# Changelog

All notable changes to this workflow are documented here. Versions correspond to DOI-citable releases.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-08-18

DOI: [10.5281/zenodo.21997257](https://doi.org/10.5281/zenodo.21997257) (concept DOI, resolves to latest version: [10.5281/zenodo.21997256](https://doi.org/10.5281/zenodo.21997256)).

### Added
- `process_generic_excel_purity.R` and `process_generic_excel_std_curve.R` — purity and standard-curve analyses for HPLC-DAD chromatogram data, from a generic, instrument-agnostic Excel input format (see `README.md`).
- `plot_chromatograms.R` — standalone quick-look chromatogram plotting, a single workbook or a whole folder, overlaid or faceted, with optional top-N peak purity labels.
- `read_generic_excel_injection.R` — shared per-injection workbook parser used by all three scripts above.
- Three runnable examples: a standard-curve run (`examples/example_run_generic_excel/`), a purity-only run with no calibration curve (`examples/example_run_generic_excel_purity/`), and a narrative per-sample R Markdown report (`examples/example_run_generic_excel_report/`), fully self-contained.
