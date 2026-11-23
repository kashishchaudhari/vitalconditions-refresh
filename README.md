# vitalconditions-refresh

A reproducible R pipeline that refreshes public indicators for Forsyth County, NC, maps them to the **Seven Vital Conditions for Wellbeing and Justice**, flags statistical reliability (margin of error and coefficient of variation), checks every output against its source, and exports files ready for Tableau Public.

> **Independent, unofficial prototype.** This project is not affiliated with or endorsed by Forsyth Futures. It uses only open public data (U.S. Census ACS and TIGER/Line) and is offered as a **draft public resource**, not a finished community narrative.

**Live site:** https://vitalconditions-refresh.vercel.app (interactive explorer and tract map)

## Status

All six milestones in [`BUILD_PROMPT.md`](BUILD_PROMPT.md) are built: 10 ACS indicators plus one PUMS indicator across five Vital Conditions, a tract-level childcare and housing affordability module, a blocking validation stage, a Quarto report and website, and a GitHub Actions workflow. Two things are still open: the **childcare supply data is a SAMPLE placeholder** (see [`data/childcare/README.md`](data/childcare/README.md)), and the legacy reference figures have not been entered. [`docs/assumptions.md`](docs/assumptions.md) lists what was verified and what was assumed.

| Vital Condition | Indicators |
|---|---|
| Humane Housing | Homeownership by race; by age of householder; housing cost burden (renters and owners); **Child Housing Cost Burden (PUMS)** |
| Meaningful Work & Wealth | Median household income; income quintiles; labor force participation, employment and unemployment; median family income |
| Basic Needs for Health & Safety | Poverty by race, children and older adults |
| Reliable Transportation | Households without a vehicle |
| Lifelong Learning | Young children and children whose parents all work (childcare demand) |

## What it does

1. Asks the Census API which ACS years exist (no year is hard-coded) and pulls every year from 2009 on, for the county (1-year and 5-year) and every census tract (newest 5-year). It also pulls PUMS microdata, with replicate weights, for the three PUMAs that make up Forsyth County.
2. Builds counts and percentages, with margins of error, for each indicator in `config/indicators.yml`.
3. Tags every number `reliable` (CV under 15%), `use_with_caution` (15-30%) or `suppress` (over 30%, zero, unpublished, or a base under 50). The thresholds are in `config/pipeline.yml`.
4. Leaves 2020 ACS 1-year data out of trends (pandemic non-response bias) and says why in the `notes` column.
5. Writes long-format CSVs to `outputs/tableau/`, a staleness report, and the childcare tract layer to `outputs/geo/`.
6. **Validates** the outputs against the Census source and stops if anything fails (see below).
7. Only if validation passed: renders `reports/refresh_summary.html` and the website in `_site/`.

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
| `outputs/tableau/staleness_report.csv` | Legacy vintage vs newest vintage, per indicator |
| `outputs/tableau/affordability_gap_tracts.csv` | Childcare supply, cost of care and renter cost burden, one row per tract |
| `outputs/geo/affordability_gap.geojson` | Same, with simplified tract boundaries (EPSG:4326) |
| `outputs/geo/childcare_facilities.geojson`, `municipal_boundaries.geojson` | Facility points (SAMPLE for now) and town boundaries for context |
| `reports/refresh_summary.html` | Staleness table, trend charts by Vital Condition, tract maps |
| `_site/` | The website (home, summary, validation, downloads, limitations) |
| `outputs/validation/validation_report.html` | Every validation check, with the failing rows if any |
| `outputs/validation/validation_summary.json` | Pass, warn and fail counts per check |

Every row has the same columns: `indicator_id, vital_condition, geography, geoid, geo_name, year, vintage_type, acs_period, group, measure, measure_label, unit, estimate, moe, se, cv, reliability_flag, include_in_trend, source_table, source_variables, geo_vintage, notes`. Percentages are on a 0-100 scale.

## Adding a new ACS indicator (edit only the YAML)

Open `config/indicators.yml`, copy the `homeownership_by_race` entry, and change:

- `id`, `name`, `vital_condition`, `universe`, `notes`
- `groups`: one line per group, naming the ACS table that holds it (for race-iterated tables, `B25003A`, `B25003B`, and so on)
- `components`: the variable numbers inside each table (for example `owner: ["002"]`). List several numbers to add them together.
- `measures`: what to publish. Use `type: count` with one component, `type: value` (with `unit: dollars` or `percent`) for numbers Census publishes directly such as medians, or `type: percent` with a `numerator` and `denominator`.
- `first_year` (optional): the earliest year to pull, for tables that start later or were renumbered.
- `checks` (optional): parts that should add up to a total, and mutually exclusive groups that should sum to the overall group.

Set `status: active` and run `targets::tar_make()`. The new indicator gets its own pull, output file and full set of validation checks automatically.

## Annual refresh

Run `targets::tar_make()` after each Census release: 1-year data comes out each September or October, 5-year data each December. The pipeline finds the new year by itself. Then check the validation report. If anything failed, the run stops with a message naming the check. Nothing is published until it passes.

## Validation (source-to-target)

"Source" is what the Census API returned. "Target" is the files in `outputs/`. The validation stage, built with [`pointblank`](https://rstudio.github.io/pointblank/), checks:

- **Completeness:** one row for every year, place, group and measure the registry implies, and every Forsyth tract (counted from TIGER/Line, not hard-coded).
- **Source match:** every directly-sourced estimate and MOE is identical to the saved Census response.
- **Variable labels:** every variable means the same thing in every year pulled. This catches the Census Bureau renumbering a table, which happened to S1903 in 2017 and S2301 in 2015.
- **Independent re-pull:** a random 5% sample (at least 25 rows) is fetched again through a separate code path and must match exactly.
- **Recomputation:** every percentage, MOE, SE, CV and reliability flag is recomputed from its parts.
- **Internal consistency:** owners plus renters equal all households, and race groups sum to the total within MOE.
- **Rules:** schema, value ranges, required fields, and no 2020 1-year data in trends.
- **PUMS benchmark:** weighted PUMS totals (persons, households, children) match the published ACS totals for the same PUMAs within ±2%.
- **Geometry:** the tract GeoJSON is valid, in EPSG:4326, has every tract once, and joins 1:1 to the tract CSV. Facility points fall inside the county.
- **Staleness:** every indicator reaches the newest available vintage.
- **Legacy comparison** (warnings only): against figures Forsyth Futures already published, listed in `config/legacy_reference.csv`. This file is empty for now (TODO).

Any **fail** stops `tar_make()` with an error. Tolerances are in `config/validation.yml`.

## Loading into Tableau Public

Use `outputs/tableau/all_indicators.csv` (or `trends_county.csv` for line charts) as a text-file data source, and `outputs/geo/affordability_gap.geojson` as a spatial file. Filter on `reliability_flag` to hide `suppress` rows, and use it as a shape to style `use_with_caution` points. Field mapping, a suggested layout and refresh steps are in [`docs/tableau_build.md`](docs/tableau_build.md).

## Hosting

GitHub Actions runs the pipeline monthly, or when you start it manually, and publishes the site to GitHub Pages only if validation passes. Pull requests are validated but never deployed. A Vercel deploy is available and off by default. Setup steps are in [`docs/deployment.md`](docs/deployment.md).

## Data and limits

Only open public data is used: no student-level, clinical, voucher-holder or other restricted records. Read [`DATA_EQUITY_AND_LIMITATIONS.md`](DATA_EQUITY_AND_LIMITATIONS.md) for who federal data misses and how to read the numbers.

## License

MIT. See [LICENSE](LICENSE).
