# retentoR

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21997256.svg)](https://doi.org/10.5281/zenodo.21997256)

**Author:** Daniel Moreira ([danielcarmor@gmail.com](mailto:danielcarmor@gmail.com))  
**Institution:** i3S – Instituto de Investigação e Inovação em Saúde, Porto, Portugal  
**Language:** R

---

## Overview

An R workflow for processing HPLC(-DAD) chromatogram data. Given a chromatogram (time vs. signal) and its peak table for each injection, the workflow supports two analyses:

1. **Purity** — for one injection, express each peak in a retention-time window as a percentage of the total peak area in that window.
2. **Standard curve** — fit a calibration curve from a series of standard injections' peak area at a target retention time, back-calculate sample concentrations (correcting for injection volume and dilution), compute LoD/LoQ, and export a multi-panel summary figure.

A third, standalone script draws quick-look chromatogram plots (single file or a whole folder, mixing both formats freely, overlaid or faceted) without running either analysis.

The scripts are `source()`d, not installed as a package — see [`examples/`](examples/) for runnable, fully self-contained demonstrations of each.

Two raw-data formats are supported, documented in full below: a plain Excel workbook per injection (instrument-agnostic — fill it in from any integration software's export), and native Shimadzu LabSolutions `.txt` exports directly.

---

## File structure

```
retentoR/
├── read_generic_excel_injection.R        # generic-Excel workbook parser
├── process_generic_excel_purity.R        # purity analysis, generic-Excel input
├── process_generic_excel_std_curve.R     # standard curve + back-calculation + summary PDF, generic-Excel input
├── read_shimadzu_injection.R             # Shimadzu LabSolutions .txt parser
├── process_shimadzu_purity.R             # purity analysis, Shimadzu input
├── process_shimadzu_std_curve.R          # standard curve + back-calculation + summary PDF, Shimadzu input
├── plot_chromatograms.R                  # quick-look chromatogram plotting, standalone, both input formats
└── examples/
    ├── example_run_generic_excel/            # standard-curve example (fabricated "PEP" standards + samples)
    ├── example_run_generic_excel_purity/     # purity-only example (fabricated synthesis batches, no standards)
    ├── example_run_generic_excel_report/     # narrative per-sample R Markdown report, fully self-contained
    └── example_run_shimadzu/                 # same "PEP" scenario, as native Shimadzu .txt exports
```

Each analysis exists as two scripts — one per input format — that share everything except how the raw file gets parsed: `process_generic_excel_purity.R`/`process_shimadzu_purity.R`, and `process_generic_excel_std_curve.R`/`process_shimadzu_std_curve.R`.

---

## Directory layout for an experiment

Every analysis is run against one **experiment folder**, containing a `raw_data/` subfolder of injection workbooks (below) and, optionally, a `method.xlsx`:

```
experimental_data/
  001_my_experiment/
    method.xlsx                    # optional, not read by any script — provenance only
    raw_data/
      STD_1_uM.xlsx
      STD_5_uM.xlsx
      STD_10_uM.xlsx
      SMP_A1.xlsx
      BLK_01.xlsx
    processed_data/                # created by the scripts; not something you write
      <analyte>/
        ...
```

`raw_data/` is scanned for **every** `.xlsx` file it contains and each one is treated as an injection workbook — so `method.xlsx` must live one level up, at the experiment root, not inside `raw_data/`.

To run an analysis, point a calling script at the experiment folder and source the relevant script:

```r
library(here)
experiment_dir <- here("experimental_data", "001_my_experiment")
source(here("process_generic_excel_std_curve.R"))   # or process_generic_excel_purity.R
```

Both scripts leave their results in `experimental_data/001_my_experiment/processed_data/<analyte>/` (see [Outputs](#outputs) below). `plot_chromatograms.R` doesn't need an experiment folder at all — point it at a single file (`.xlsx` or `.txt`) or any folder of them, and it dispatches per file on extension automatically (see its own header comment for the full argument list, including `wavelength` for disambiguating a multi-channel Shimadzu `.txt` file).

---

## Raw data format: what goes where

### Filename → injection type

Each workbook's **filename** (not its contents) tells the parser what kind of injection it is:

| Filename pattern | Meaning | What gets parsed out |
|---|---|---|
| `STD_<conc>_<unit>...xlsx` | Standard | `<conc>` (numeric) and `<unit>` — e.g. `STD_10_uM.xlsx` → 10 µM |
| `SMP_<id>...xlsx` | Sample | `<id>` — e.g. `SMP_A1.xlsx` → sample id `A1` |
| `BLK...xlsx` | Blank | nothing further; any suffix is ignored |

Anything after the parsed portion (extra suffixes, replicate numbers, etc.) is free text and safely ignored, as long as the file still starts with `STD_`, `SMP_`, or `BLK`.

### Inside the workbook: three required sheets

**`Chromatogram`** — the raw trace for this injection.

- Cell **A1** must read `Wavelength(nm): <value>` (e.g. `Wavelength(nm): 254`) — this is the only place the detection wavelength for the *trace* is recorded.
- Row 2 is a normal header row: `time`, `signal`.
- Row 3 onward is one row per time point.

|  | A | B |
|---|---|---|
| 1 | `Wavelength(nm): 254` | *(blank)* |
| 2 | `time` | `signal` |
| 3 | `0.00` | `30.1` |
| 4 | `0.05` | `30.4` |
| … | … | … |

`time` is in minutes; `signal` is whatever unit your detector reports (absorbance units, mAU, etc. — the workflow doesn't convert units, it just uses them consistently).

**`Peak Areas`** — this injection's peak table, one row per detected peak, ordinary header row:

| peak_id | r_time | peak_area | wavelength |
|---|---|---|---|
| 1 | 7.2 | 1245 | 254 |
| 2 | 12.5 | 88231 | 254 |

- `peak_id` — an integer identifying the peak within this injection (elution order is the natural choice). Used to reference a specific peak later, e.g. when `plot_chromatograms()` labels a peak on the trace.
- `r_time` — retention time (min) of the peak apex.
- `peak_area` — the integrated peak area, in whatever units your integration software reports. Only ratios and relative comparisons within one experiment matter, so as long as it's consistent across all your injections, the absolute unit doesn't matter.
- `wavelength` — the detection wavelength (nm) for *that peak*. This is a column here (unlike the `Chromatogram` sheet's single wavelength) because one peak table can, in principle, combine peaks picked at different wavelengths/channels.

**`Metadata`** — exactly one header row and one data row, describing this specific injection:

| analyte | injection_date | injection_volume | sample_dilution | target_rt | rt_window_min | rt_window_max |
|---|---|---|---|---|---|---|
| PEP | 2026.08.17 | 10 | 5 | 15.2 | 8 | 25 |

| Column | Meaning |
|---|---|
| `analyte` | Short label for what's being measured (e.g. `PEP`, `Compound1`). Names the output subfolder/files. **Must be identical across every injection in one experiment.** |
| `injection_date` | Date string used in output filenames (any consistent format, e.g. `2026.08.17`). **Must be identical across every injection in one experiment.** |
| `injection_volume` | Volume injected (µL) for *this* run. Every `STD` injection in an experiment must share the same value — it's the calibration curve's reference volume. `SMP` injections may use a different volume; the standard-curve script automatically scales their peak area to match the STD reference volume before back-calculating (see `process_generic_excel_std_curve.R`'s header comment). |
| `sample_dilution` | Dilution factor applied to this sample (e.g. `5` for a 1:5 dilution). Multiplied onto the back-calculated concentration. Use `1` if undiluted; irrelevant for `STD`/`BLK` rows. |
| `target_rt` | Retention time (min) of the peak of interest — the analyte's own peak. Both analyses center on whichever peak in the `Peak Areas` table falls closest to this value. **Must be identical across every injection in one experiment.** |
| `rt_window_min`, `rt_window_max` | Retention-time bounds (min) defining which peaks count toward the "total area" used for purity, and which peaks are eligible to be matched as the `target_rt` peak. **Must be identical across every injection in one experiment.** |

The fields marked "must be identical" are intentionally duplicated into every injection's own `Metadata` sheet rather than pulled from one shared file, so each workbook is fully self-contained — but that also means the analysis scripts will error out if they disagree across injections in the same experiment, rather than silently picking one.

### `method.xlsx` (optional)

Lives at the experiment root (`experimental_data/001_my_experiment/method.xlsx`), not inside `raw_data/`. Not read by either analysis script — it exists purely as a record of what conditions the run was performed under. Two sheets:

**`Method`** — mobile phase identity + gradient table, same header-cell-then-table pattern as `Chromatogram`:

|  | A | B | C | D | E |
|---|---|---|---|---|---|
| 1 | `Mobile Phase A: 0.1% TFA in water` | `Mobile Phase B: Acetonitrile` | *(blank)* | *(blank)* | *(blank)* |
| 2 | `time` | `%A` | `%B` | `flow_rate` | `temperature` |
| 3 | `0` | `95` | `5` | `1.0` | `25` |
| … | … | … | … | … | … |

**`Column`** — one row describing the analytical column:

| column_name | dimensions | particle_size_um | serial_number |
|---|---|---|---|
| Zorbax SB-C18 | 150 x 4.6 mm | 3.5 | US1234567 |

See [`examples/example_run_generic_excel_report/`](examples/example_run_generic_excel_report/) for a report that actually reads this file (to overlay the gradient on a chromatogram plot and cite the column in its methodology text) — the two analysis scripts don't.

---

## Raw data format: Shimadzu LabSolutions `.txt`

The same two analyses also run directly against a native Shimadzu LabSolutions ASCII export — no manual transcription into Excel needed. `read_shimadzu_injection.R` reads a folder of `.txt` files; `process_shimadzu_purity.R`/`process_shimadzu_std_curve.R` use it the same way the generic-Excel scripts use `read_generic_excel_injection.R`.

**Filename convention is identical** to the generic-Excel format (`STD_<conc>_<unit>.txt`, `SMP_<id>.txt`, `BLK...txt` — see the table above, just with a `.txt` extension).

**What's parsed from the file itself:**

- The chromatogram trace: either a single `R.Time (min)` / `Intensity` table (single-channel export), or one or more `[PDA Multi Chromatogram(ChN)]` blocks, each with its own `Wavelength(nm)` line and its own data table (multi-channel export — most DAD software exports this way even for a single wavelength of interest).
- The peak table(s): one or more `[Peak Table(PDA-ChN)]` blocks, each channel's peaks tagged with that channel's wavelength and combined into one table — same idea as the generic-Excel format's multi-wavelength `Peak Areas` sheet.
- `injection_volume`, from the file's own `Injection Volume` line.

**What a raw export does *not* carry** — because it's domain knowledge, not instrument output — is an analyte name, target retention time, purity window, or sample dilution. Those come from a companion CSV, `injection_metadata.csv`, placed at the experiment root (sibling to `raw_data/`, same reasoning as `method.xlsx` above — never inside `raw_data/`, or it'll be mistaken for an injection file):

| filename | analyte | injection_date | target_rt | rt_window_min | rt_window_max | sample_dilution |
|---|---|---|---|---|---|---|
| STD_10_uM.txt | PEP | 2026.08.19 | 15.2 | 8 | 25 | 1 |
| SMP_A1.txt | PEP | 2026.08.19 | 15.2 | 8 | 25 | 5 |

One row per injection file; this plays the same role the generic-Excel format's `Metadata` sheet plays, just out-of-band since a raw instrument export can't carry extra sheets. `analyte`/`injection_date`/`target_rt`/`rt_window_min`/`rt_window_max` must still be identical across every row for one experiment; `sample_dilution` is the one column expected to vary per sample.

If any injection has more than one detector channel, pass which wavelength to use as its `chromatogram`:

```r
library(here)
experiment_dir <- here("experimental_data", "001_my_experiment")
wavelength <- 254   # only needed if a file has more than one channel
source(here("process_shimadzu_std_curve.R"))   # or process_shimadzu_purity.R
```

Directory layout matches the generic-Excel format, just with `.txt` files and this CSV instead of `.xlsx` workbooks:

```
experimental_data/
  001_my_experiment/
    injection_metadata.csv
    raw_data/
      STD_1_uM.txt
      STD_10_uM.txt
      SMP_A1.txt
      BLK_01.txt
    processed_data/
```

**Unit note**: exported intensity is used as-is, with no scaling applied. Purity (%) and the standard-curve fit/LoD/LoQ are unit-agnostic as long as every injection in one experiment is on the same raw scale, which they inherently are (same instrument, same method) — so absolute intensity units don't matter here any more than they do for the generic-Excel format's `signal`/`peak_area` columns.

---

## Outputs

All four analysis scripts write into `experimental_data/<experiment>/processed_data/<analyte>/`, with `<date>` taken from every injection's `injection_date`. Output naming/content is identical regardless of which input format produced `injections` — `process_shimadzu_std_curve.R` and `process_shimadzu_purity.R` write exactly what's described below.

**`process_generic_excel_std_curve.R` / `process_shimadzu_std_curve.R`**

| File | Contents |
|---|---|
| `<date>_<analyte>_summary_results.pdf` | Multi-panel figure: blank/standard chromatograms, sample chromatograms, peak area by injection (with LoD/LoQ/STD-range reference lines), the standard curve, and calculated sample concentrations |
| `<date>_<analyte>_levels.csv` | Back-calculated concentration per sample, with volume/dilution corrections and an `extrapolated` flag — only written if any `SMP` injections exist |
| `<date>_<analyte>_analytical_performance.csv` | Fit slope/intercept/R², LoD, LoQ |

**`process_generic_excel_purity.R` / `process_shimadzu_purity.R`**

| File | Contents |
|---|---|
| `<date>_<analyte>_purity.csv` | Every peak's % of the window's total area, one row per peak per injection |
| `<date>_<analyte>_purity_summary.csv` | One row per injection: the purity of just the `target_rt` peak |

`plot_chromatograms.R` doesn't write any file itself — it returns a `ggplot` object for you to `ggsave()` (see any `run_example.R` for the pattern).

---

## Status

`v1.1.0` released and archived on Zenodo (see DOI badge above). No package, no automated test suite — each `examples/` subfolder running or knitting without error is the correctness check.
