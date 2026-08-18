# Changelog

All notable changes to this workflow are documented here. Versions correspond to DOI-citable releases.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-08-18

DOI: [10.5281/zenodo.21998479](https://doi.org/10.5281/zenodo.21998479) (concept DOI, resolves to latest version: [10.5281/zenodo.21997256](https://doi.org/10.5281/zenodo.21997256)).

### Added
- `read_shimadzu_injection.R` — reader for native Shimadzu LabSolutions ASCII (`.txt`) chromatogram exports (single- and multi-channel), returning the same per-injection shape `read_generic_excel_injection.R` does. Since a raw export carries no analyte name, target retention time, purity window, or sample dilution (domain knowledge, not instrument output), those come from a companion per-experiment `injection_metadata.csv`, one row per injection.
- `process_shimadzu_purity.R` and `process_shimadzu_std_curve.R` — Shimadzu counterparts of the generic-Excel analysis scripts; everything past reading `injections` is intentionally identical between the two formats.
- `examples/example_run_shimadzu/` — fabricated multi-channel `.txt` fixtures (a 254 nm channel actually used, plus a 280 nm "decoy" channel with deliberately different values, to exercise wavelength-based channel selection) demonstrating both analyses end to end.

### Fixed
- `process_generic_excel_purity.R` and `process_generic_excel_std_curve.R` filtered peaks by retention-time window only, never by `wavelength` — so a `Peak Areas` sheet spanning multiple detector channels (explicitly a supported layout, see the format documentation) would have its peak areas silently pooled across wavelengths, which isn't chemically meaningful. Both scripts' peak-window filters now also require `wavelength == inj$wavelength`. Confirmed a no-op against the existing single-wavelength `v1.0.0` examples (byte-identical CSV output); caught during development by the new Shimadzu example's deliberate second channel.

### Changed
- Deliberately did **not** port `legacy/`'s unverified `1e6`/`1e3` intensity-scaling divisor into the new Shimadzu reader — purity and standard-curve/LoD/LoQ math is unit-agnostic as long as every injection in one experiment is on the same raw scale, which they inherently are.

## [1.0.0] - 2026-08-18

DOI: [10.5281/zenodo.21997257](https://doi.org/10.5281/zenodo.21997257) (concept DOI, resolves to latest version: [10.5281/zenodo.21997256](https://doi.org/10.5281/zenodo.21997256)).

### Added
- `process_generic_excel_purity.R` and `process_generic_excel_std_curve.R` — purity and standard-curve analyses for HPLC-DAD chromatogram data, from a generic, instrument-agnostic Excel input format (see `README.md`).
- `plot_chromatograms.R` — standalone quick-look chromatogram plotting, a single workbook or a whole folder, overlaid or faceted, with optional top-N peak purity labels.
- `read_generic_excel_injection.R` — shared per-injection workbook parser used by all three scripts above.
- Three runnable examples: a standard-curve run (`examples/example_run_generic_excel/`), a purity-only run with no calibration curve (`examples/example_run_generic_excel_purity/`), and a narrative per-sample R Markdown report (`examples/example_run_generic_excel_report/`), fully self-contained.
