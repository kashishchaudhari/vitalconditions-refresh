# Module B: tract-level Childcare & Housing Affordability Gap ----------------
#
# Puts supply (licensed child care slots) and affordability (cost of infant
# care vs. family income, renter cost burden) side by side for every census
# tract. It deliberately does NOT combine them into a single score or rank
# neighborhoods: community members should read the measures together.
#
# Supply comes from a CSV with the schema in data/childcare/README.md. No
# public statewide download exists (see docs/assumptions.md), so the file in
# use is a SAMPLE PLACEHOLDER until real data is obtained. Every output row
# says which.

FACILITY_SCHEMA <- c(
  license_number = "character", facility_name = "character", facility_type = "character",
  address = "character", city = "character", zip = "character",
  latitude = "numeric", longitude = "numeric", licensed_capacity = "numeric",
  star_rating = "numeric", serves_infants = "logical", source = "character",
  as_of_date = "character"
)

read_facilities <- function(path) {
  types <- purrr::map(FACILITY_SCHEMA, function(t) switch(t,
    character = readr::col_character(), numeric = readr::col_double(),
    logical = readr::col_logical()))
  readr::read_csv(path, col_types = do.call(readr::cols, c(types, list(.default = readr::col_character()))),
                  comment = "#", na = c("", "NA"), progress = FALSE)
}

facilities_are_sample <- function(path, fac) {
  grepl("SAMPLE", basename(path), fixed = TRUE) || any(grepl("SAMPLE", fac$source, fixed = TRUE))
}

#' Tract polygons (TIGER/Line cartographic boundary) with geometry.
get_county_tract_geometry <- function(year, area) {
  options(tigris_use_cache = TRUE)
  suppressMessages(tigris::tracts(state = area$state_fips, county = area$county_fips,
                                  year = year, cb = TRUE, progress_bar = FALSE)) |>
    dplyr::transmute(geoid = GEOID, tract_name = NAMELSAD)
}

get_county_boundary <- function(year, area) {
  options(tigris_use_cache = TRUE)
  suppressMessages(tigris::counties(state = area$state_fips, year = year, cb = TRUE,
                                    progress_bar = FALSE)) |>
    dplyr::filter(GEOID == area$county_geoid) |>
    dplyr::transmute(geoid = GEOID)
}

#' Context layer: incorporated places (towns, cities) touching the county.
get_municipal_boundaries <- function(year, area, county) {
  options(tigris_use_cache = TRUE)
  pl <- suppressMessages(tigris::places(state = area$state_fips, year = year, cb = TRUE,
                                        progress_bar = FALSE))
  county <- sf::st_transform(county, sf::st_crs(pl))
  pl[lengths(sf::st_intersects(pl, county)) > 0, ] |>
    dplyr::transmute(place_geoid = GEOID, place_name = NAME, place_type = NAMELSAD)
}

latest_tract_rows <- function(csv_path, measure_id, group_name, year) {
  read_output_csv(csv_path) |>
    dplyr::filter(geography == "tract", vintage_type == "acs5", year == !!year,
                  measure == measure_id, group == group_name) |>
    dplyr::select(geoid, estimate, moe, reliability_flag)
}

#' Build the tract table. All inputs are files written earlier in the pipeline.
build_affordability_gap <- function(tracts_sf, facilities_path, demand_csv, mfi_csv,
                                    burden_csv, acs5_year, childcare_cfg, pipeline_cfg) {
  crs <- childcare_cfg$projected_crs
  fac <- read_facilities(facilities_path)
  sample <- facilities_are_sample(facilities_path, fac)
  rel <- pipeline_cfg$reliability

  kids <- latest_tract_rows(demand_csv, "children_under_5", "All children", acs5_year)
  work <- latest_tract_rows(demand_csv, "pct_under_6_all_parents_working", "All children", acs5_year)
  mfi <- latest_tract_rows(mfi_csv, "median_family_income", "All families", acs5_year)
  rcb <- latest_tract_rows(burden_csv, "pct_cost_burdened", "Renter households", acs5_year)

  tr <- sf::st_transform(tracts_sf, crs)
  pts <- sf::st_as_sf(fac, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) |>
    sf::st_transform(crs)

  # Slots inside each tract.
  hit <- sf::st_intersects(tr, pts)
  slots_in <- purrr::map_dbl(hit, ~ sum(fac$licensed_capacity[.x], na.rm = TRUE))
  n_in <- lengths(hit)
  infant_in <- purrr::map_dbl(hit, ~ sum(fac$serves_infants[.x] %in% TRUE))

  # Slots and children within a straight-line buffer of each tract's interior
  # point: a rough "nearby supply vs nearby demand" ratio. Not drive time.
  buf_m <- childcare_cfg$buffer_miles * 1609.344
  centers <- sf::st_point_on_surface(sf::st_geometry(tr))
  near_fac <- sf::st_is_within_distance(centers, pts, dist = buf_m)
  near_tr <- sf::st_is_within_distance(centers, centers, dist = buf_m)
  k <- kids[match(tr$geoid, kids$geoid), ]

  monthly <- childcare_cfg$market_rate$monthly_dollars
  annual <- 12 * monthly
  th <- childcare_cfg$thresholds

  out <- tibble::tibble(
    geoid = tr$geoid,
    tract_name = tr$tract_name,
    acs_period = acs_period_label("acs5", acs5_year),
    children_under_5 = k$estimate,
    children_under_5_moe = k$moe,
    children_under_5_flag = k$reliability_flag,
    facilities_in_tract = n_in,
    facilities_serving_infants_in_tract = infant_in,
    licensed_slots_in_tract = slots_in,
    licensed_slots_within_buffer = purrr::map_dbl(near_fac, ~ sum(fac$licensed_capacity[.x], na.rm = TRUE)),
    children_under_5_within_buffer = purrr::map_dbl(near_tr, ~ if (anyNA(k$estimate[.x])) NA_real_ else sum(k$estimate[.x])),
    children_under_5_within_buffer_moe = purrr::map_dbl(near_tr, ~ if (anyNA(k$estimate[.x])) NA_real_
                                                        else tidycensus::moe_sum(k$moe[.x], k$estimate[.x]))
  ) |>
    dplyr::mutate(
      slots_per_100_children = dplyr::if_else(children_under_5 > 0, licensed_slots_in_tract / children_under_5 * 100, NA_real_),
      slots_per_100_children_moe = dplyr::if_else(!is.na(slots_per_100_children),
        tidycensus::moe_ratio(licensed_slots_in_tract, children_under_5, 0, children_under_5_moe) * 100, NA_real_),
      slots_per_100_children_buffer = dplyr::if_else(children_under_5_within_buffer > 0,
        licensed_slots_within_buffer / children_under_5_within_buffer * 100, NA_real_),
      slots_per_100_children_buffer_moe = dplyr::if_else(!is.na(slots_per_100_children_buffer),
        tidycensus::moe_ratio(licensed_slots_within_buffer, children_under_5_within_buffer, 0,
                              children_under_5_within_buffer_moe) * 100, NA_real_)
    )

  flag <- function(est, moe, base = NA_real_) {
    add_reliability(tibble::tibble(estimate = est, moe = moe, base = base), rel)$reliability_flag
  }
  out <- out |>
    dplyr::mutate(
      slots_per_100_children_flag = flag(slots_per_100_children, slots_per_100_children_moe, children_under_5),
      slots_per_100_children_buffer_flag = flag(slots_per_100_children_buffer, slots_per_100_children_buffer_moe,
                                                children_under_5_within_buffer),
      pct_under_6_all_parents_working = work$estimate[match(geoid, work$geoid)],
      pct_under_6_all_parents_working_moe = work$moe[match(geoid, work$geoid)],
      pct_under_6_all_parents_working_flag = work$reliability_flag[match(geoid, work$geoid)],
      median_family_income = mfi$estimate[match(geoid, mfi$geoid)],
      median_family_income_moe = mfi$moe[match(geoid, mfi$geoid)],
      median_family_income_flag = mfi$reliability_flag[match(geoid, mfi$geoid)],
      annual_infant_care_cost = annual,
      infant_care_cost_pct_of_income = dplyr::if_else(median_family_income > 0,
        annual / median_family_income * 100, NA_real_),
      infant_care_cost_pct_of_income_moe = dplyr::if_else(!is.na(infant_care_cost_pct_of_income),
        tidycensus::moe_ratio(annual, median_family_income, 0, median_family_income_moe) * 100, NA_real_),
      infant_care_cost_pct_of_income_flag = flag(infant_care_cost_pct_of_income, infant_care_cost_pct_of_income_moe),
      renter_cost_burden_pct = rcb$estimate[match(geoid, rcb$geoid)],
      renter_cost_burden_pct_moe = rcb$moe[match(geoid, rcb$geoid)],
      renter_cost_burden_pct_flag = rcb$reliability_flag[match(geoid, rcb$geoid)],
      supply_category = dplyr::case_when(
        slots_per_100_children_buffer_flag == "suppress" | is.na(slots_per_100_children_buffer) ~ "Too uncertain to say",
        slots_per_100_children_buffer < th$low_supply_slots_per_100 ~ "Fewer than 1 licensed slot per 3 young children nearby",
        TRUE ~ "At least 1 licensed slot per 3 young children nearby"),
      cost_category = dplyr::case_when(
        infant_care_cost_pct_of_income_flag == "suppress" | is.na(infant_care_cost_pct_of_income) ~ "Too uncertain to say",
        infant_care_cost_pct_of_income > th$affordable_pct_of_income ~
          paste0("Infant care costs more than ", th$affordable_pct_of_income, "% of median family income"),
        TRUE ~ paste0("Infant care costs ", th$affordable_pct_of_income, "% or less of median family income")),
      gap_category = dplyr::case_when(
        supply_category == "Too uncertain to say" | cost_category == "Too uncertain to say" ~ "Too uncertain to say",
        startsWith(supply_category, "Fewer") & startsWith(cost_category, "Infant care costs more") ~ "Low supply and high cost",
        startsWith(supply_category, "Fewer") ~ "Low supply",
        startsWith(cost_category, "Infant care costs more") ~ "High cost",
        TRUE ~ "Neither low supply nor high cost"),
      data_status = if (sample) "SAMPLE: supply figures use placeholder facilities, not real data" else "Real facility data",
      notes = paste0(
        if (sample) "SUPPLY IS PLACEHOLDER SAMPLE DATA. " else "",
        "Slots are total licensed capacity for all ages. Nearby = within ", childcare_cfg$buffer_miles,
        " miles (straight line) of the tract's interior point. Cost uses ", childcare_cfg$market_rate$label, ".")
    )
  out
}

#' Simplified, valid, EPSG:4326 tract polygons joined to the tract table.
build_affordability_geo <- function(tracts_sf, gap_tbl, childcare_cfg) {
  g <- sf::st_transform(tracts_sf, childcare_cfg$projected_crs) |>
    sf::st_simplify(preserveTopology = TRUE, dTolerance = childcare_cfg$simplify_meters) |>
    sf::st_make_valid() |>
    sf::st_transform(4326)
  dplyr::left_join(dplyr::select(g, geoid), gap_tbl, by = "geoid")
}

write_affordability_outputs <- function(gap_tbl, gap_geo, facilities_path, municipal, pipeline_cfg) {
  geo_dir <- file.path(dirname(pipeline_cfg$paths$tableau_dir), "geo")
  dir.create(geo_dir, recursive = TRUE, showWarnings = FALSE)
  p_csv <- file.path(pipeline_cfg$paths$tableau_dir, "affordability_gap_tracts.csv")
  p_geo <- file.path(geo_dir, "affordability_gap.geojson")
  p_fac <- file.path(geo_dir, "childcare_facilities.geojson")
  p_mun <- file.path(geo_dir, "municipal_boundaries.geojson")
  readr::write_csv(gap_tbl, p_csv, na = "")
  for (p in c(p_geo, p_fac, p_mun)) if (file.exists(p)) file.remove(p)
  sf::st_write(gap_geo, p_geo, driver = "GeoJSON", quiet = TRUE)
  fac <- read_facilities(facilities_path)
  sf::st_write(sf::st_as_sf(fac, coords = c("longitude", "latitude"), crs = 4326),
               p_fac, driver = "GeoJSON", quiet = TRUE)
  sf::st_write(sf::st_transform(municipal, 4326), p_mun, driver = "GeoJSON", quiet = TRUE)
  c(tract_csv = p_csv, geojson = p_geo, facilities = p_fac, municipal = p_mun)
}

# Validation for Module B -------------------------------------------------------

check_affordability <- function(paths, facilities_path, tract_geoids, county_sf, tracts_sf,
                                demand_csv, mfi_csv, acs5_year, childcare_cfg, pipeline_cfg) {
  id <- "affordability_gap"
  pick <- function(pattern) unname(paths[grepl(pattern, paths, fixed = TRUE)][1])
  tbl <- readr::read_csv(pick("affordability_gap_tracts.csv"),
                         col_types = readr::cols(geoid = "c", .default = "?"), progress = FALSE)
  geo <- sf::st_read(pick("affordability_gap.geojson"), quiet = TRUE)
  fac <- read_facilities(facilities_path)
  res <- list()

  # Every tract present, once, in both files, and they join 1:1.
  all_ids <- union(tract_geoids, union(tbl$geoid, geo$geoid))
  u <- tibble::tibble(geoid = all_ids,
                      n_csv = purrr::map_int(all_ids, ~ sum(tbl$geoid == .x)),
                      n_geo = purrr::map_int(all_ids, ~ sum(geo$geoid == .x)),
                      in_tigris = all_ids %in% tract_geoids) |>
    dplyr::mutate(pass = in_tigris & n_csv == 1 & n_geo == 1)
  res[[1]] <- check_result(paste0(id, "__tracts_join_1_to_1"), "completeness", id,
    sprintf("Affordability gap: every Forsyth tract (%d, from TIGER/Line) appears exactly once in the tract CSV and the GeoJSON, and the two join 1:1.",
            length(tract_geoids)), u)

  # Geometry rules.
  crs_ok <- isTRUE(sf::st_crs(geo)$epsg == 4326) || identical(sf::st_crs(geo), sf::st_crs(4326))
  u <- tibble::tibble(geoid = geo$geoid,
                      valid = as.logical(sf::st_is_valid(geo)),
                      not_empty = !sf::st_is_empty(geo),
                      polygon = as.character(sf::st_geometry_type(geo)) %in% c("POLYGON", "MULTIPOLYGON"),
                      epsg_4326 = crs_ok) |>
    dplyr::mutate(pass = valid & not_empty & polygon & epsg_4326)
  res[[2]] <- check_result(paste0(id, "__geometry_valid"), "rules", id,
    "Affordability gap GeoJSON: every geometry is a valid, non-empty polygon in EPSG:4326.", u)

  # Facility file: schema and values.
  miss <- setdiff(names(FACILITY_SCHEMA), names(fac))
  cnty <- sf::st_transform(county_sf, 4326)
  pts <- sf::st_as_sf(dplyr::filter(fac, !is.na(latitude), !is.na(longitude)),
                      coords = c("longitude", "latitude"), crs = 4326)
  inside <- lengths(sf::st_intersects(pts, cnty)) > 0
  u <- fac |>
    dplyr::mutate(
      has_coords = !is.na(latitude) & !is.na(longitude),
      inside_county = has_coords & (license_number %in% pts$license_number[inside]),
      capacity_ok = !is.na(licensed_capacity) & licensed_capacity >= 0 & licensed_capacity == round(licensed_capacity),
      star_ok = is.na(star_rating) | star_rating %in% 1:5,
      license_unique = !duplicated(license_number) & !duplicated(license_number, fromLast = TRUE),
      schema_ok = length(miss) == 0,
      pass = has_coords & inside_county & capacity_ok & star_ok & license_unique & schema_ok) |>
    dplyr::select(license_number, facility_name, has_coords, inside_county, capacity_ok,
                  star_ok, license_unique, schema_ok, pass)
  res[[3]] <- check_result(paste0(id, "__facility_file"), "rules", id,
    sprintf("Child care facility file (%s): has every required column, coordinates inside Forsyth County, whole-number capacity >= 0, star rating 1-5 or blank, unique license numbers.%s",
            basename(facilities_path), if (facilities_are_sample(facilities_path, fac)) " NOTE: this is the SAMPLE placeholder file." else ""),
    u)

  # Recompute supply and cost from scratch and compare to the CSV. The
  # point-in-polygon join here uses full-resolution TIGER boundaries in
  # lon/lat on the sphere (s2), a different method from the build step
  # (planar, NC State Plane). The simplified GeoJSON is for display only.
  full <- sf::st_transform(tracts_sf, 4326)
  hit <- sf::st_intersects(full, pts)
  annual <- 12 * childcare_cfg$market_rate$monthly_dollars
  kids <- latest_tract_rows(demand_csv, "children_under_5", "All children", acs5_year)
  mfi <- latest_tract_rows(mfi_csv, "median_family_income", "All families", acs5_year)
  rc <- tibble::tibble(geoid = full$geoid,
                       exp_slots = purrr::map_dbl(hit, ~ sum(pts$licensed_capacity[.x], na.rm = TRUE))) |>
    dplyr::left_join(dplyr::select(kids, geoid, exp_kids = estimate), by = "geoid") |>
    dplyr::left_join(dplyr::select(mfi, geoid, exp_mfi = estimate), by = "geoid") |>
    dplyr::left_join(dplyr::select(tbl, geoid, licensed_slots_in_tract, children_under_5,
                                   slots_per_100_children, median_family_income,
                                   infant_care_cost_pct_of_income), by = "geoid") |>
    dplyr::mutate(
      exp_ratio = ifelse(exp_kids > 0, exp_slots / exp_kids * 100, NA_real_),
      exp_cost = ifelse(exp_mfi > 0, annual / exp_mfi * 100, NA_real_),
      pass = licensed_slots_in_tract == exp_slots &
        same_value(children_under_5, exp_kids) & same_value(median_family_income, exp_mfi) &
        near_value(slots_per_100_children, exp_ratio, 1e-6) &
        near_value(infant_care_cost_pct_of_income, exp_cost, 1e-6))
  res[[4]] <- check_result(paste0(id, "__recompute"), "derived", id,
    "Affordability gap: slots per tract (re-counted by a separate point-in-polygon join on the published GeoJSON), children under 5 and median family income (equal to the indicator outputs), slots per 100 children and cost as % of income all match.",
    rc)

  # Rules: flags present, no composite score or rank, no negative values.
  forbidden <- grep("score|rank|index|vulnerab", names(tbl), ignore.case = TRUE, value = TRUE)
  flag_cols <- grep("_flag$", names(tbl), value = TRUE)
  num_cols <- names(tbl)[vapply(tbl, is.numeric, logical(1))]
  u <- tibble::tibble(
    rule = c("no composite score or rank column",
             paste0("flag column has no blanks: ", flag_cols),
             paste0("not negative: ", num_cols),
             "data_status says whether supply is sample or real"),
    pass = c(length(forbidden) == 0,
             vapply(flag_cols, function(cn) !anyNA(tbl[[cn]]) && all(tbl[[cn]] %in% RELIABILITY_LEVELS), logical(1)),
             vapply(num_cols, function(cn) all(is.na(tbl[[cn]]) | tbl[[cn]] >= 0), logical(1)),
             all(!is.na(tbl$data_status)))
  )
  res[[5]] <- check_result(paste0(id, "__rules"), "rules", id,
    "Affordability gap rules: every reliability flag filled, no negative values, a data_status on every row, and no composite score or ranking column (the module shows measures side by side on purpose).",
    u)
  res
}
