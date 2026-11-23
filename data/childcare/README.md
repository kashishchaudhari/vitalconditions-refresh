# Child care facility data (Module B supply side)

## Status: placeholder

`facilities_SAMPLE.csv` is **fake**. It holds 150 random points inside Forsyth County with made-up capacities, so the childcare module can be built and tested. Every output built from it is labelled `SAMPLE` in its `data_status` column, in its notes, and on the website.

## Why there is no real file yet

NC DCDEE offers no public bulk download of licensed facilities (checked 2026-11-23; see `docs/assumptions.md`). The Child Care Facility Search (https://ncchildcare.ncdhhs.gov/childcaresearch) lists 151 Forsyth facilities. It shows name, address, license number and type, but it has no export and no coordinates. Capacity and star rating are only on each facility's own page.

Ways to get real data:

1. **DCDEE data request** (recommended): use the Data Request Portal linked from https://ncchildcare.ncdhhs.gov/County/Child-Care-Snapshot/Child-Care-Statistic-Report and ask for licensed facilities in Forsyth County with license number, name, address, type, licensed capacity, star rating and ages served.
2. Compile it by hand from the search tool, one facility page at a time.

## Schema (one row per licensed facility)

| Column | Type | Notes |
|---|---|---|
| `license_number` | text | Unique. |
| `facility_name` | text | |
| `facility_type` | text | e.g. `Center`, `Family Child Care Home` |
| `address`, `city`, `zip` | text | |
| `latitude`, `longitude` | number | WGS84 (EPSG:4326). Geocode addresses first if the source has none. The U.S. Census Geocoder is free: https://geocoding.geo.census.gov/ |
| `licensed_capacity` | whole number | Total licensed slots, all ages |
| `star_rating` | 1-5 or blank | NC star-rated license |
| `serves_infants` | TRUE/FALSE | Serves children under 12 months |
| `source` | text | Where the row came from. Must not contain the word `SAMPLE` for real data. |
| `as_of_date` | YYYY-MM-DD | When the data was current |

Lines starting with `#` are ignored.

## Switching to real data

Save the file (for example `data/childcare/facilities.csv`), set `childcare.facilities_csv` in `config/pipeline.yml` to its path, and run `targets::tar_make()`. Validation checks the schema, that every point is inside the county, and that capacities and star ratings are valid.

Do not commit files that contain information about individual children or families. Facility-level licensing data is public, but check the terms of whatever source you use.
