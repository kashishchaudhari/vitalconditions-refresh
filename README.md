# vitalconditions-refresh

A reproducible R pipeline that refreshes public indicators for Forsyth County, NC, maps them to the **Seven Vital Conditions for Wellbeing and Justice**, flags statistical reliability (margin of error and coefficient of variation), checks every output against its source, and exports files ready for Tableau Public.

> **Independent, unofficial prototype.** This project is not affiliated with or endorsed by Forsyth Futures. It uses only open public data (U.S. Census ACS and TIGER/Line) and is offered as a **draft public resource**, not a finished community narrative.

## Status

**Milestone 1 of 6 is done:** scaffold, indicator registry, and one indicator (homeownership by race and ethnicity) built end to end with its validation checks. The other indicators are listed in the registry as `planned`. See [`BUILD_PROMPT.md`](BUILD_PROMPT.md) for the full plan and [`docs/assumptions.md`](docs/assumptions.md) for what was verified and what was assumed.

## What it does

1. Asks the Census API which ACS years exist (no year is hard-coded) and pulls every year from 2009 on, for the county (1-year and 5-year) and every census tract (newest 5-year).
2. Builds counts and percentages, with margins of error, for each indicator in `config/indicators.yml`.
3. Tags every number `reliable` (CV under 15%), `use_with_caution` (15-30%) or `suppress` (over 30%, zero, unpublished, or a base under 50). The thresholds are in `config/pipeline.yml`.
4. Leaves 2020 ACS 1-year data out of trends (pandemic non-response bias) and says why in the `notes` column.
5. Writes long-format CSVs to `outputs/tableau/`.
6. **Validates** the outputs against the Census source and stops if anything fails (see below).

## 5-minute quickstart

You need R 4.4 or newer (plus Rtools on Windows) and a free Census API key (https://api.census.gov/data/key_signup.html).

1. Save the key as an environment variable named `CENSUS_API_KEY`. On Windows, open *Edit environment variables for your account*. On Mac/Linux, add `CENSUS_API_KEY=yourkey` to `~/.Renviron`. Never put the key in this folder.
2. Open R in this folder and install the locked package versions:
   ```r
   renv::restore()
   ```
3. Run everything:
   ```r
   targets::tar_make()      # or, from a terminal:  Rscript run_pipeline.R
   ```
   The first run takes a few minutes. Later runs only redo what changed, and Census responses are cached in `data/cache/`.
4. Look at `outputs/tableau/` for the data and `outputs/validation/validation_report.html` for the checks.

Run the tests (no key or internet needed): `Rscript tests/testthat.R`.

## Outputs

| File | What it holds |
|---|---|
| `outputs/tableau/<indicator_id>.csv` | Every row for one indicator: county and tracts, all years |
| `outputs/tableau/all_indicators.csv` | All indicators stacked in one file |
| `outputs/tableau/trends_county.csv` | County rows safe to use in trend charts (no 2020 1-year) |
| `outputs/validation/validation_report.html` | Every validation check, with the failing rows if any |
| `outputs/validation/validation_summary.json` | Pass, warn and fail counts per check |

Every row has the same columns: `indicator_id, vital_condition, geography, geoid, geo_name, year, vintage_type, acs_period, group, measure, measure_label, unit, estimate, moe, se, cv, reliability_flag, include_in_trend, source_table, source_variables, geo_vintage, notes`. Percentages are on a 0-100 scale.

## Adding a new ACS indicator (edit only the YAML)

Open `config/indicators.yml`, copy the `homeownership_by_race` entry, and change:

- `id`, `name`, `vital_condition`, `universe`, `notes`
- `groups`: one line per group, naming the ACS table that holds it (for race-iterated tables, `B25003A`, `B25003B`, and so on)
- `components`: the variable numbers inside each table (for example `owner: ["002"]`). List several numbers to add them together.
- `measures`: what to publish. Use `type: count` with one component, or `type: percent` with a `numerator` and `denominator`.
- `checks` (optional): parts that should add up to a total, and mutually exclusive groups that should sum to the overall group.

Set `status: active` and run `targets::tar_make()`. The new indicator gets its own pull, output file and full set of validation checks automatically.

## Annual refresh

Run `targets::tar_make()` after each Census release: 1-year data comes out each September or October, 5-year data each December. The pipeline finds the new year by itself. Then check the validation report. If anything failed, the run stops with a message naming the check. Nothing is published until it passes.

## Validation (source-to-target)

"Source" is what the Census API returned. "Target" is the files in `outputs/`. The validation stage, built with [`pointblank`](https://rstudio.github.io/pointblank/), checks:

- **Completeness:** one row for every year, place, group and measure the registry implies, and every Forsyth tract (counted from TIGER/Line, not hard-coded).
- **Source match:** every directly-sourced estimate and MOE is identical to the saved Census response.
- **Independent re-pull:** a random 5% sample (at least 25 rows) is fetched again through a separate code path and must match exactly.
- **Recomputation:** every percentage, MOE, SE, CV and reliability flag is recomputed from its parts.
- **Internal consistency:** owners plus renters equal all households, and race groups sum to the total within MOE.
- **Rules:** schema, value ranges, required fields, and no 2020 1-year data in trends.
- **Legacy comparison** (warnings only): against figures Forsyth Futures already published, listed in `config/legacy_reference.csv`. This file is empty for now (TODO).

Any **fail** stops `tar_make()` with an error. Tolerances are in `config/validation.yml`.

## Loading into Tableau Public

Use `outputs/tableau/all_indicators.csv` (or `trends_county.csv` for line charts) as a text-file data source. Filter on `reliability_flag` to hide `suppress` rows, and use it as a colour or shape to style `use_with_caution` points. A fuller guide is planned for `docs/tableau_build.md` (milestone 5).

## Data and limits

Only open public data is used: no student-level, clinical, voucher-holder or other restricted records. Federal surveys miss some people, including unhoused and doubled-up families, and small groups are often too uncertain to report. A full limitations page is planned (milestone 5).

## License

MIT. See [LICENSE](LICENSE).
