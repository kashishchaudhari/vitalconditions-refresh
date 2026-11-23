# Verified facts and assumptions

Checked on 2026-11-23 while building milestone 1. **Verified** means it was
checked against the source named. **Assumed** means it was not, and should be
confirmed before anyone relies on it.

## ACS vintages

| Item | Status | Evidence |
|---|---|---|
| Latest ACS 1-year = **2025** | Verified | `https://api.census.gov/data/2025/acs/acs1.json` returns 200, and `2026` returns 404. Census release schedule page: 2025 1-year released Oct 29, 2026 (https://www.census.gov/programs-surveys/acs/news/data-releases/2025/release-schedule.html). |
| Latest ACS 5-year = **2020-2024** | Verified | `.../2024/acs/acs5.json` returns 200 and `.../2025/acs/acs5.json` returns 404. The 2021-2025 5-year release date is listed as TBD on the schedule page. |
| No standard 2020 ACS 1-year | Verified | `.../2020/acs/acs1.json` returns 404. The pipeline also excludes any 2020 1-year row from trends if one ever appears. |
| 1-year and 5-year exist back to 2009 for B25003 and B25003A-I at county level | Verified | Every year from 2009 on was pulled without error (except 2020 1-year). |
| Vintages are not hard-coded | Design | `detect_acs_vintages()` checks every year from `start_year` to the current year on each run. |
| 1-year race-iterated tables are filtered for small groups | Verified | 1-year `B25003E` (NHPI) comes back `null` in 2009 and 2025, and `B25003C` (AIAN) in 2025. They are kept as rows with `reliability_flag = suppress`, not dropped. |
| MOE published as missing (Census annotation codes) means "no sampling error" (controlled count) | Assumed | Such rows are flagged `reliable` with a note. None occur in the milestone 1 indicator. |

## Geography

| Item | Status | Evidence |
|---|---|---|
| Forsyth County has **95** census tracts in the 2020 tract vintage | Verified | Counted at run time from TIGER/Line 2024 cartographic boundary file (`tigris`), and it matches the 95 tracts in the 2020 tract-to-PUMA file. The pipeline never hard-codes this. |
| Forsyth PUMAs (2020 definitions): **01801, 01802, 01803** (30, 31 and 34 tracts) | Verified | https://www2.census.gov/geo/docs/maps-data/data/rel2020/2020_Census_Tract_to_2020_PUMA.txt, filtered to state 37, county 067. |
| Forsyth PUMAs (2010 definitions): **01801, 01802, 01803** (28, 31 and 34 tracts, 93 tracts total) | Verified | https://www2.census.gov/geo/docs/maps-data/data/rel/2010_Census_Tract_to_2010_PUMA.txt |
| The three PUMAs cover **exactly** Forsyth County in both vintages | Verified | No other NC county has tracts in 01801-01803 in either file. **This differs from BUILD_PROMPT.md**, which says the PUMAs approximate the county. Geographically they match it. PUMS estimates still differ from published county tables because of sampling and disclosure-avoidance noise. Milestone 3 docs will say that, not that the geography is approximate. |
| PUMA names | Not verified | The 2020 PUMA names PDF could not be read as text. To confirm in milestone 3. |
| PUMS years and PUMA vintage: 1-year PUMS 2022+ and 5-year PUMS 2022+ use 2020 PUMAs | Assumed (standard Census practice) | To confirm in milestone 3. Because the codes are the same, a code-only join would hide the boundary change, so comparisons across it will be flagged. |

## FFTemplates (`forsythfuture/FFTemplates`)

| Item | Status | Evidence |
|---|---|---|
| Package contents | Verified | GitHub API: the repo has **no `R/` folder**, `NAMESPACE` is `exportPattern("^[[:alpha:]]+")`, and the only templates are R Markdown templates in `inst/rmarkdown/templates/` (`data_request_template`, `pdf_template`, `gitbook_template`). DESCRIPTION: version 0.3.0, licence CC0. |
| ggplot2 theme or colour-scale functions | Verified: **none exist** | Nothing is exported, so the report (milestone 5) will use a neutral ggplot2 theme with a TODO. Colours or fonts could be borrowed from the templates' CSS if Forsyth Futures wants that. |
| Quarto templates | Verified: none | Only R Markdown templates. |
| Activity | Verified | Not archived. Last push Aug 14, 2023. |

## Child care data (Module B, milestone 4)

| Item | Status | Evidence |
|---|---|---|
| Public downloadable statewide facility file (with coordinates) from NC DCDEE | **Not found** | The DCDEE Child Care Facility Search (https://ncchildcare.ncdhhs.gov/childcaresearch) works. For Forsyth it returned **151 facilities in 16 pages** with columns License Number, Facility Name, Address and Facility Type. There is **no CSV/Excel export** (only a Print button) and no coordinates. Capacity, star rating and ages served are on each facility's detail page. |
| DCDEE "Child Care Statistic Report" | Verified: statewide aggregate only | https://ncchildcare.ncdhhs.gov/County/Child-Care-Snapshot/Child-Care-Statistic-Report lists only an April 2018 statewide summary PDF. County-level data goes through a DCDEE Data Request Portal (Qualtrics form). |
| NC OneMap / ArcGIS Online statewide child care layer | Not found | An ArcGIS Online search for DCDEE / NC child care found only third-party layers: Buncombe County centers (2024), UNC student projects, and an NC Pre-K locations layer for 2025-26. None is an authoritative statewide licensed-facility file. HIFLD's hub URL returned 404. |
| Plan | Design | Per the spec, Module B will **accept a CSV with a documented schema** (license number, name, address, lat/long or geocodable address, capacity, star rating, ages served). One public route to fill it is a DCDEE data request. Scraping the search tool was not attempted and may conflict with its terms. **Needs a decision.** |
| NC child care market rates | Source verified, figure not extracted | Market Rates page (https://ncchildcare.ncdhhs.gov/Home/DCDEE-Sections/Subsidy-Services/Market-Rates) lists county rate tables effective Oct 1, 2026. The 2025 Market Rate Survey report is on https://ncchildcare.ncdhhs.gov/Provider/Child-Care-Subsidy/Market-Rate-Study. The Forsyth infant, 5-star center figure still needs to be read from the PDF (milestone 4). |

## Legacy vintages and reference figures

| Item | Status | Evidence |
|---|---|---|
| Legacy vintage of each indicator | **Assumed** | Taken from BUILD_PROMPT.md ("economy and housing tables stop at 2021"; Child Housing Cost Burden on 2015-2019 PUMS). Each registry entry records `verified: false` until someone checks the live legacy page. |
| `config/legacy_reference.csv` | Empty (headers + TODO) | No published figures were captured. The legacy check reports this as a **warning**, not a pass. |

## Design choices that go beyond the spec

- **Extra output columns.** The spec's schema is
  `indicator_id, vital_condition, geography, geoid, year, vintage_type, group, estimate, moe, se, cv, reliability_flag, notes`.
  The outputs keep those and add `geo_name, acs_period, measure, measure_label, unit, include_in_trend, source_table, source_variables, geo_vintage`.
  `measure` is needed because one indicator publishes several numbers (counts and a rate). The others make every number traceable to its table, variables and vintage, as the engineering rules require.
- **Percentages** are stored on a 0-100 scale. Their MOE is in percentage points (`tidycensus::moe_prop`, which falls back to `moe_ratio` when the proportion formula is undefined).
- **Small-base rule.** A percentage whose denominator is below `min_denominator` (default 50, in `config/pipeline.yml`) is suppressed. The value 50 is a judgement call. Zero estimates are suppressed because their CV is undefined.
- **Tract data** uses only the newest 5-year vintage (2020 tract boundaries). County data uses every vintage, 1-year and 5-year.
- **"Source" for validation** is the exact tidycensus response saved to `data/cache/acs/` at pull time. Every directly-sourced output value is compared to it exactly. Separately, a random sample (5%, at least 25 rows) is **re-pulled live** through an independent curl + jsonlite client and must match exactly.
- **Hand-edited outputs.** If someone edits an output CSV by hand, `targets` notices the file changed and rebuilds it from source, which repairs it. Validation catches errors that come from code or source changes. The self-tests in `tests/testthat/test-validation-selftest.R` corrupt outputs on purpose (dropped tract, dropped group, altered estimate, altered MOE, altered percentage, wrong flag, broken owner+renter total, a 2020 1-year row in the trend file) and confirm that the matching check fails.
