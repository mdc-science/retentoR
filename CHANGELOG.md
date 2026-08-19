# Changelog

All notable changes to this workflow are documented here. Versions correspond to DOI-citable releases.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

## [1.3.0] - 2026-08-19

### Added
- `examples/example_run_shimadzu_real/` — real (anonymized) HPLC-DAD data, not fabricated: a genuine 2025.07.03 standard curve (3 levels, clean 2x dilution series) plus 2 replicate injections of one real sample. The real project codename and the real standard's internal lab code were replaced throughout with `Compound1`/`Compound1-Std`; the chromatogram traces, peak tables, and injection volumes are untouched.

### Fixed
- `parse_shimadzu_filename()` (and its duplicated copies in `read_generic_excel_injection.R` and the report example) anchored STD/SMP/BLK type detection to the start of the filename, so a real date-prefixed filename (e.g. `2025.07.03_BLK_2-propanol_01.txt`) failed to parse — every fabricated fixture in this repo happens to put the type token first, so this was never caught until real data was used. Fixed in all three copies with a `(^|_)` boundary check instead of a plain `^` anchor.

### Changed
- `examples/example_run_shimadzu/`'s fabricated `.txt` fixtures now carry the full realistic LabSolutions section structure (32 `ISTD Amount` lines, full 21-column peak table, etc.) instead of the minimal subset the parser actually reads, so the fixture exercises tolerance for realistic surrounding junk. The underlying chromatogram/peak numbers are unchanged (verified byte-for-byte identical before replacing the committed files).

## [1.2.0] - 2026-08-19

DOI: [10.5281/zenodo.22011043](https://doi.org/10.5281/zenodo.22011043) (concept DOI, resolves to latest version: [10.5281/zenodo.21997256](https://doi.org/10.5281/zenodo.21997256)).

### Added
- `plot_chromatograms()` now supports Shimadzu `.txt` exports directly, dispatching per file on extension (`.xlsx` -> generic-Excel reader, `.txt` -> Shimadzu reader via a new `read_any_injection()` helper) — a single call can point at a folder mixing both formats. New `wavelength` argument, passed through to every `.txt` file for multi-channel disambiguation (ignored for `.xlsx`); a multi-channel file given with no `wavelength` now surfaces `read_shimadzu_injection()`'s own clear error instead of guessing.

### Changed
- `read_shimadzu_injection()`'s `analyte`/`injection_date`/`target_rt`/`rt_window_min`/`rt_window_max` arguments now default to `NA`, since `plot_chromatograms()` doesn't need any of them — `process_shimadzu_purity.R`/`process_shimadzu_std_curve.R` still get them enforced via `read_shimadzu_experiment()`'s `metadata_file`, independent of these defaults.

### Fixed
- The same wavelength-pooling bug fixed in `[1.1.0]`'s `process_*.R` scripts also existed in `plot_chromatograms()`'s own `annotate_purity_top_n` label logic (peaks ranked/summed without a `wavelength` filter) — not caught until this script was actually exercised against multi-channel data while wiring up Shimadzu support. Fixed the same way: restricted to `wavelength == inj$wavelength` before computing a total or ranking peaks.

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
