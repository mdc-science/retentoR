# Changelog

All notable changes to this workflow are documented here. Versions correspond to DOI-citable releases.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

## [1.4.0] - 2026-09-15

DOI: [10.5281/zenodo.22772295](https://doi.org/10.5281/zenodo.22772295) (concept DOI, resolves to latest version: [10.5281/zenodo.21997256](https://doi.org/10.5281/zenodo.21997256)).

### Added
- `examples/example_run_shimadzu_real_2/` — a second, independent real (anonymized) HPLC-DAD dataset: a genuine standard curve (8 levels, ~2x dilution series, 2 replicates each) plus 2 replicate injections each of two extraction samples. Anonymized like `example_run_shimadzu_real/`: the real compound name and the operator's name were replaced throughout with `Compound1`/`Analyst1`. Unlike `example_run_shimadzu_real/`, STD and SMP injections here use different injection volumes (50 µL vs 10 µL), exercising the `volume_adjustment` code path in `process_shimadzu_std_curve.R` for the first time against real data — which is what surfaced the two bugs below.

### Fixed
- `read_shimadzu_injection.R`'s peak-table and chromatogram parsing called `readr::read_tsv()` on a collapsed single-line string without wrapping it in `I()`; readr's heuristic treats a no-newline string as a file path rather than literal data, so any injection with exactly one peak (or, for the chromatogram block, a single time point) errored out instead of parsing. Every fabricated fixture in this repo has multiple peaks per file, so this was never caught until real single-peak data was used.
- `parse_shimadzu_txt()` returned a columnless 0-row tibble for an injection with zero detected peaks (e.g. a blank with no peaks at all), which crashed downstream `dplyr::filter(r_time >= ...)` calls. Fixed by forcing the empty-peaks case to the expected typed shape (`peak_id`/`r_time`/`peak_area`/`wavelength`).
- `process_shimadzu_std_curve.R`/`process_generic_excel_std_curve.R`: sample peak areas were scaled by `volume_adjustment` **before** being passed to `predict(std_curve, ...)`, then `extrapolated` was judged against that scaled value. Since `std_curve` has a nonzero intercept, `predict()` isn't proportional, so pre-scaling silently scaled the intercept too (no physical basis), and `extrapolated` ended up flagging samples based on an inflated proxy rather than on whether the actually-measured peak area fell inside the calibration's tested range. Fixed by interpolating on raw `peak_area` first (exposed as the new `apparent_conc` column, replacing `peak_area_adjusted`) and applying `volume_adjustment` to the resulting concentration afterward (matching how `sample_dilution` was already applied); the "peak area by injection" plot panel was changed the same way, plotting every point at its raw `peak_area`. Concentration values shift negligibly for a small intercept (confirmed against `examples/example_run_generic_excel/`'s `SMP_A3`, ~1.2% here) but can be substantial for a larger one (a synthetic stress-test case with an intercept ~56% of typical signal size was off by 100% under the old order); `extrapolated` can change from `TRUE` to `FALSE` for samples whose *raw* signal was in range but whose volume-scaled proxy wasn't.
- `parse_shimadzu_filename()`/`read_injection()`'s type-detection regex (`read_shimadzu_injection.R`, `read_generic_excel_injection.R`, and the report example's own duplicate) matched `STD_`/`SMP_`/`BLK` as a substring anywhere in the filename (guarded only by a `(^|_)` boundary), so a blank or sample whose free-text suffix happened to mention another type got misread as that type instead — silently for some cases (`BLK_SMP_leftover_01.txt` → `smp`), or with a confusing crash for others (`BLK_STD_grade_ACN_01.txt` → matched as `std`, then errored because it has no `STD_<conc>_<unit>` shape). Fixed by anchoring the match to the start of the filename, allowing only a leading run of numeric/dot segments (a date stamp) before the type token, in all three copies — still supports a date-prefixed filename (e.g. `2025.07.03_BLK_2-propanol_01.txt`) but no longer matches a type token buried in a free-text suffix. Found via a dedicated stress-test pass (8 filename cases), not by any committed fixture.

## [1.3.0] - 2026-08-19

DOI: [10.5281/zenodo.22011495](https://doi.org/10.5281/zenodo.22011495) (concept DOI, resolves to latest version: [10.5281/zenodo.21997256](https://doi.org/10.5281/zenodo.21997256)).

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
