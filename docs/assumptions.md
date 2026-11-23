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
| The three PUMAs cover **exactly** Forsyth County in both vintages | Verified | No other NC county has tracts in 01801-01803 in either file. **This differs from the original assumption** that the PUMAs only approximate the county. Geographically they match it. PUMS estimates still differ from published county tables because of sampling and disclosure-avoidance noise. Milestone 3 docs will say that, not that the geography is approximate. |
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
| Plan | Design | Per the spec, Module B will **accept a CSV with a documented schema** (license number, name, address, lat/long or geocodable address, capacity, star rating, ages served). One public route to fill it is a DCDEE data request. Scraping the search tool was not attempted and may conflict with its terms. **Decided:** use a SAMPLE placeholder for now (see below). |
| NC child care market rate for Forsyth | **Verified: $1,400/month** | From "Subsidized Child Care Market Rates for Child Care Centers, Effective October 1, 2026" (`Centers_Market_Rates_FINAL_9-17-2026-003.pdf`, linked from https://ncchildcare.ncdhhs.gov/Home/DCDEE-Sections/Subsidy-Services/Market-Rates). Forsyth row, Centers, Infant-Toddler: 1-star $433, 2-star $454, 3-star $1,127, 4-star $1,150, **5-star $1,400**. The module uses the 5-star rate (`config/pipeline.yml`, `childcare.market_rate`). **Caveat:** these are subsidy reimbursement rates. For 3-5 stars they are the highest of a 2021 statewide floor, the 2023 county market rate and the current rate, not a survey of prices every family pays. The Oct 1, 2023 table showed $1,036 for 5-star infant care. |
| "Low supply" threshold (fewer than 1 slot per 3 children = 33.3 per 100) | Assumed, common definition | The "child care desert" definition popularised by the Center for American Progress. Configurable. |
| "Affordable" threshold (7% of family income) | Assumed, common definition | The U.S. HHS benchmark from the 2016 CCDF rule. Configurable. Because $16,800 a year is above 7% of almost any tract's median family income, nearly every tract is "high cost". That is a real finding, not a bug. |

## Table and variable choices (milestone 2)

| Item | Status | Evidence |
|---|---|---|
| Subject tables renumber variables over time | **Verified** | Labels for every variable in every year from 2009 to 2025 were downloaded from the Census API `groups/<table>.json`. **S1903** moved median income from `C02` to `C03` in 2017 (`S1903_C02_001` became "percent distribution"). **S2301** `C02_001` was "in labor force" (a count) up to 2014 and "labor force participation rate" from 2015. Pulling one variable ID for every year would have mixed different things. |
| Median household income uses **B19013 (+A-I)** instead of S1903 | Design (verified equivalent concept) | B19013 publishes the same medians and its variable IDs never changed from 2009 to 2025. |
| Labor force uses **S2301 from 2015 on** (`first_year: 2015`) | Verified | Race rows `C0x_012`-`C0x_020`, men and women 20-64 (`022`, `023`) and women with children under 6 only (`025`) have stable labels from 2015 to 2025. Earlier years are left out rather than mixed in. |
| All B tables used (B25003, B19013, B19080, B25007, B25070, B25091, B08201, B17001, B09001, B23008, B19113) have identical labels in every year | **Verified**, and re-checked automatically on every run | Ignoring punctuation and the dollar-year in income labels. New validation check `<indicator>__variable_labels`. |
| B19080 and B08201 have no 2009 5-year release; B23025 starts 2011 | Verified (API 404) | `first_year: {acs5: 2010}` set for B19080 and B08201. B23025 is not used. |
| Missing MOE now flags `use_with_caution` (not `reliable`) | Design change | Medians above $250,000 are top-coded and published without a MOE. Treating them as reliable would overstate certainty. |

## PUMS (milestone 3)

| Item | Status | Evidence |
|---|---|---|
| Latest PUMS: 1-year **2024**, 5-year **2020-2024** | Verified | `.../2024/acs/acs1/pums.json` and `.../acs5/pums.json` return 200, and 2025 returns 404. The 2025 1-year PUMS is not out yet, although the 2025 1-year tables are. The pipeline detects "latest" at run time. |
| Vintages built: 5-year 2015-2019 (matches legacy), 5-year 2020-2024, 1-year 2024 | Design | `config/pipeline.yml` `pums:`. |
| Household-type variable renamed `TYPE` (to 2019) to `TYPEHUGQ` (2020 on) | Verified | `tidycensus::pums_variables`. The code picks the right name by year. |
| Cost burden for children: renters use `GRPIP`, owners `OCPIP`; blank means not computed (no income / no cash rent) | Verified (PUMS data dictionary via `pums_variables`) | Children in "occupied without payment of rent" homes (`TEN = 4`) are excluded, as in published tables. |
| Standard errors: 80 person replicate weights, successive-difference replication (`scale = 4/80`, `mse = TRUE`) | Census-documented method | Recomputed independently in validation with plain sums. |
| Race groups for PUMS combine AIAN, NHPI, other and multiracial (non-Hispanic) into one group | Design | Keeps the five groups mutually exclusive and large enough to estimate. Each is still flagged. |
| PUMS sample-size rule: suppress when the denominator has fewer than 30 sample cases | Assumed (judgement) | `pums.min_sample_cases`. |

## Childcare module decisions (your answers, 2026-11-23)

- **Extra output columns:** kept.
- **Facility data:** build with a clearly labelled SAMPLE placeholder (`data/childcare/facilities_SAMPLE.csv`, fake points) until real data is obtained. Every Module B output carries `data_status = SAMPLE...`.
- **Hand-edited outputs:** the pipeline rebuilding them from source is acceptable.
- "Nearby" supply uses a straight-line buffer (default 2 miles) around each tract's interior point. Drive-time catchments would need a routing service and are not implemented.
- Licensed capacity counts all ages, so slots per 100 children under 5 overstates infant and toddler supply. `serves_infants` is carried for future use.
- Context layer: TIGER/Line incorporated places (towns and cities) stand in for MapForsyth municipal limits. HOLC redlining boundaries were not added. Both are optional in the spec.

## Legacy vintages and reference figures

| Item | Status | Evidence |
|---|---|---|
| Legacy vintage of each indicator | **Assumed** | Taken from the project brief (housing and economy indicators on 2021 data; Child Housing Cost Burden on 2015-2019 PUMS). Each registry entry records `verified: false` until someone checks the live legacy page. |
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
