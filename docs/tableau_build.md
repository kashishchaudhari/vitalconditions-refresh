# Building the Tableau Public dashboard

Tableau Public cannot pull data on a schedule from GitHub, so refreshing the dashboard is a short manual step after each pipeline run.

## 1. Get the files

Download them from the published site's **Data downloads** page, or take them from `outputs/` after `tar_make()`:

| File | Use it for |
|---|---|
| `all_indicators.csv` | The main data source (long format, every indicator) |
| `trends_county.csv` | Line charts (no 2020 1-year rows) |
| `staleness_report.csv` | A "what's new" table |
| `affordability_gap.geojson` | The tract map (spatial file) |

## 2. Field mapping

| Field | Tableau type | Role | Notes |
|---|---|---|---|
| `indicator_id` | String | Dimension | Machine name. Use `measure_label` for display. |
| `vital_condition` | String | Dimension | One of the Seven Vital Conditions. Use it as the top-level filter. |
| `geography` | String | Dimension | `county`, `tract`, or `county_pums` |
| `geoid` | String | Dimension | **Set as String**, or leading zeros are lost. Joins to the GeoJSON `geoid`. |
| `geo_name` | String | Dimension | |
| `year` | Number (whole) | Dimension (discrete) or continuous date part | End year of the ACS period |
| `vintage_type` | String | Dimension | `acs1` or `acs5`. Never mix the two in one trend line. |
| `acs_period` | String | Dimension | e.g. `2020-2024` |
| `group` | String | Dimension | The demographic dropdown (race and ethnicity, age, tenure, sex) |
| `measure` / `measure_label` | String | Dimension | Filter to one measure per chart |
| `unit` | String | Dimension | `count`, `percent`, `dollars` |
| `estimate` | Number (decimal) | Measure | Percentages are 0-100 |
| `moe` | Number (decimal) | Measure | 90% margin of error. Error bars are estimate ± moe. |
| `se`, `cv` | Number (decimal) | Measure | Tooltip |
| `reliability_flag` | String | Dimension | `reliable`, `use_with_caution`, `suppress` |
| `include_in_trend` | Boolean | Dimension | Filter to TRUE on trend charts |
| `source_table`, `source_variables` | String | Dimension | Tooltip, for transparency |
| `notes` | String | Dimension | Tooltip |

Suggested calculated field, **Shown value**, so suppressed points disappear but stay in the data:

```
IF [reliability_flag] = "suppress" THEN NULL ELSE [estimate] END
```

Use `reliability_flag` on **Shape** (filled for reliable, open for caution), or on Opacity.

## 3. Suggested one-page layout

This mirrors the dropdown filters Forsyth Family Power already uses.

```
+------------------------------------------------------------------+
| Title · "Draft public resource" note · unofficial-prototype note |
+------------------------------------------------------------------+
| [Vital Condition ▼] [Indicator ▼] [Group ▼] [1-year | 5-year]    |
+-----------------------------------+------------------------------+
| Trend line (trends_county.csv)    | Latest value card            |
|  x = year, y = Shown value        |  estimate ± moe, flag text   |
|  shape = reliability_flag         |  "legacy showed: <vintage>"  |
|  band = estimate ± moe            |  (from staleness_report)     |
+-----------------------------------+------------------------------+
| Group comparison, latest year: horizontal bars with error bars,  |
| sorted by group order (not by value), suppressed groups listed as |
| "too few responses" rather than dropped                           |
+------------------------------------------------------------------+
| Tract map (affordability_gap.geojson): one measure at a time,    |
| chosen by a parameter, never a combined score. Grey = too        |
| uncertain. "SAMPLE DATA" banner while the supply file is a        |
| placeholder.                                                      |
+------------------------------------------------------------------+
| Footer: source tables, run date, link to limitations page        |
+------------------------------------------------------------------+
```

Filters:
- **Vital Condition** filters **Indicator** (relevant values only).
- **Group** single-select, defaulting to the all-people or all-households group.
- **Survey** (`vintage_type`) single-select: 1-year for recent county trends, 5-year for smaller groups.

## 4. Refresh steps (about 10 minutes, once a year or after each release)

1. Run the pipeline (or the GitHub Actions workflow) and confirm validation passed.
2. Download the new CSV and GeoJSON files.
3. In Tableau Desktop or the Tableau Public app, open the workbook and choose **Data → Replace Data Source** (or **Edit Connection**) for each file.
4. Check that the new year appears and that the staleness table changed.
5. **File → Save to Tableau Public.**
