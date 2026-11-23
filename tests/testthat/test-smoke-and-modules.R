# Smoke test: the build -> write -> validate -> report -> gate chain runs end to
# end on cached (fixture) data with no Census API key and no network.

test_that("pipeline stages run offline on a cached sample and the gate passes", {
  withr::local_envvar(CENSUS_API_KEY = "")
  r <- fixture_run()
  r$cfg$pipeline$paths$validation_dir <- tempfile("validation_")
  out <- read_output_csv(r$path)
  trend_path <- file.path(dirname(r$path), "trends_county.csv")
  readr::write_csv(dplyr::filter(out, geography == "county", include_in_trend), trend_path, na = "")
  legacy <- check_legacy(out, read_legacy_reference(file.path(root, "config", "legacy_reference.csv")),
                         r$cfg$validation)
  rep <- write_validation_report(r$checks, list(r$path, trend_path), legacy, r$cfg$validation,
                                 r$cfg$pipeline, fixture_vintages())
  expect_true(file.exists(rep$html))
  expect_true(file.exists(rep$json))
  expect_equal(rep$counts$fail, 0L)
  expect_true(suppressMessages(validation_gate(rep)))
  # The empty legacy reference is reported as a warning, not hidden.
  expect_gte(rep$counts$warn, 1L)
})

# PUMS -------------------------------------------------------------------------

fixture_pums <- function(n = 600, seed = 2) {
  set.seed(seed)
  d <- tibble::tibble(
    survey = "acs5", year = 2024L, SERIALNO = sprintf("H%04d", ceiling(seq_len(n) / 3)),
    SPORDER = rep(1:3, length.out = n), PUMA = sample(c("01801", "01802", "01803"), n, TRUE),
    AGEP = sample(0:80, n, TRUE), TEN = sample(1:4, n, TRUE, prob = c(.3, .3, .35, .05)),
    GRPIP = sample(c(0, 10:101), n, TRUE), OCPIP = sample(c(0, 5:101), n, TRUE),
    HISP = sample(c(1, 2), n, TRUE, prob = c(.85, .15)), RAC1P = sample(1:9, n, TRUE),
    HHTYPE = sample(c(1, 2), n, TRUE, prob = c(.95, .05)),
    WGTP = sample(20:60, n, TRUE), PWGTP = sample(20:60, n, TRUE)
  )
  for (i in 1:80) d[[paste0("PWGTP", i)]] <- pmax(0, d$PWGTP + sample(-8:8, n, TRUE))
  d
}

test_that("srvyr replicate-weight estimates match the independent plain-sum recomputation", {
  cfg <- fixture_cfgs()
  spec <- read_registry(file.path(root, "config", "indicators.yml"))[["child_housing_cost_burden"]]
  pums <- fixture_pums()
  tbl <- build_child_burden_table(estimate_child_burden(pums, cfg$pipeline, spec), spec, cfg$pipeline)
  chk <- check_pums_recompute(spec, tbl, pums)
  expect_equal(failed_units(chk), 0)
  bad <- tbl; bad$estimate[3] <- bad$estimate[3] * 1.01
  expect_gt(failed_units(check_pums_recompute(spec, bad, pums)), 0)
  # Groups and tenure sum to all children; burden50 <= burden30 <= computed.
  cons <- check_pums_consistency(spec, tbl, cfg$validation)
  for (ch in cons) expect_equal(failed_units(ch), 0, label = ch$check_id)
})

test_that("PUMS benchmark passes within tolerance and fails outside it", {
  cfg <- fixture_cfgs()
  pums <- fixture_pums()
  tot <- pums |> dplyr::group_by(PUMA) |>
    dplyr::summarise(B01003_001 = sum(PWGTP), B11001_001 = sum(WGTP[SPORDER == 1 & HHTYPE == 1]),
                     B09001_001 = sum(PWGTP[AGEP < 18])) |>
    tidyr::pivot_longer(-PUMA, names_to = "variable", values_to = "estimate") |>
    dplyr::mutate(GEOID = paste0("37", PUMA), vintage_type = "acs5", year = 2024L)
  expect_equal(failed_units(check_pums_benchmark(pums, tot, cfg$validation)), 0)
  off <- dplyr::mutate(tot, estimate = ifelse(variable == "B01003_001", estimate * 1.05, estimate))
  expect_equal(failed_units(check_pums_benchmark(pums, off, cfg$validation)), 3)
})

# Module B (childcare) ---------------------------------------------------------

fixture_geo <- function() {
  sq <- function(x0, y0) sf::st_polygon(list(rbind(c(x0, y0), c(x0 + .05, y0), c(x0 + .05, y0 + .05),
                                                   c(x0, y0 + .05), c(x0, y0))))
  tr <- sf::st_sf(geoid = c("37067000100", "37067000200", "37067000301"),
                  tract_name = c("Census Tract 1", "Census Tract 2", "Census Tract 3.01"),
                  geometry = sf::st_sfc(sq(-80.30, 36.05), sq(-80.25, 36.05), sq(-80.30, 36.10), crs = 4326))
  county <- sf::st_sf(geoid = "37067", geometry = sf::st_union(tr))
  list(tracts = tr, county = county)
}

fixture_tract_csv <- function(measure, group, values, moes, dir) {
  g <- fixture_tracts()$geoid
  d <- tibble::tibble(
    indicator_id = "x", vital_condition = "Humane Housing", geography = "tract", geoid = g,
    geo_name = g, year = 2024L, vintage_type = "acs5", acs_period = "2020-2024", group = group,
    measure = measure, measure_label = measure, unit = "count", estimate = values, moe = moes,
    se = moes / 1.645, cv = moes / 1.645 / values * 100, reliability_flag = "reliable",
    include_in_trend = TRUE, source_table = "T", source_variables = "T_001",
    geo_vintage = "2020 census tracts", notes = NA_character_)
  p <- tempfile(paste0(measure, "_"), dir, fileext = ".csv"); readr::write_csv(d, p, na = ""); p
}

fixture_affordability <- function(fac_edit = identity) {
  cfg <- fixture_cfgs()
  cfg$pipeline$paths$tableau_dir <- tempfile("tab_"); dir.create(cfg$pipeline$paths$tableau_dir)
  dir <- cfg$pipeline$paths$tableau_dir
  g <- fixture_geo()
  fac <- tibble::tibble(
    license_number = c("SAMPLE-1", "SAMPLE-2", "SAMPLE-3"), facility_name = "f", facility_type = "Center",
    address = "a", city = "c", zip = NA_character_,
    latitude = c(36.07, 36.075, 36.12), longitude = c(-80.28, -80.22, -80.27),
    licensed_capacity = c(40, 60, 25), star_rating = c(5, 4, NA), serves_infants = c(TRUE, FALSE, TRUE),
    source = "SAMPLE test", as_of_date = "2026-11-23")
  fac <- fac_edit(fac)
  fp <- tempfile("facilities_SAMPLE_", fileext = ".csv"); readr::write_csv(fac, fp, na = "")
  kids <- fixture_tract_csv("children_under_5", "All children", c(200, 150, 90), c(40, 35, 30), dir)
  work <- fixture_tract_csv("pct_under_6_all_parents_working", "All children", c(70, 60, 65), c(8, 9, 10), dir)
  dem <- tempfile("demand_", dir, ".csv"); readr::write_csv(dplyr::bind_rows(read_output_csv(kids), read_output_csv(work)), dem, na = "")
  mfi <- fixture_tract_csv("median_family_income", "All families", c(60000, 85000, 120000), c(6000, 9000, 15000), dir)
  rcb <- fixture_tract_csv("pct_cost_burdened", "Renter households", c(45, 38, 30), c(6, 7, 8), dir)
  gap <- build_affordability_gap(g$tracts, fp, dem, mfi, rcb, 2024L, cfg$pipeline$childcare, cfg$pipeline)
  geo <- build_affordability_geo(g$tracts, gap, cfg$pipeline$childcare)
  files <- write_affordability_outputs(gap, geo, fp, g$county, cfg$pipeline)
  list(cfg = cfg, g = g, fp = fp, dem = dem, mfi = mfi, files = files, gap = gap)
}

run_aff_checks <- function(a) {
  check_affordability(a$files, a$fp, fixture_tracts()$geoid, a$g$county, a$g$tracts, a$dem, a$mfi, 2024L,
                      a$cfg$pipeline$childcare, a$cfg$pipeline)
}

test_that("affordability module builds, is labelled SAMPLE, and passes its checks", {
  a <- fixture_affordability()
  expect_true(all(grepl("SAMPLE", a$gap$data_status)))
  expect_equal(a$gap$licensed_slots_in_tract, c(40, 60, 25))
  expect_equal(a$gap$annual_infant_care_cost[1], 12 * a$cfg$pipeline$childcare$market_rate$monthly_dollars)
  expect_false(any(grepl("score|rank", names(a$gap), ignore.case = TRUE)))
  for (ch in run_aff_checks(a)) expect_equal(failed_units(ch), 0, label = ch$check_id)
})

test_that("a dropped tract in the GeoJSON or a facility outside the county fails", {
  a <- fixture_affordability()
  geo <- sf::st_read(a$files[["geojson"]], quiet = TRUE)
  file.remove(a$files[["geojson"]])
  sf::st_write(geo[-2, ], a$files[["geojson"]], driver = "GeoJSON", quiet = TRUE)
  ch <- run_aff_checks(a)
  expect_gt(failed_units(check_by_suffix(ch, "__tracts_join_1_to_1")), 0)

  b <- fixture_affordability(function(f) { f$latitude[3] <- 35.0; f })   # far outside
  expect_gt(failed_units(check_by_suffix(run_aff_checks(b), "__facility_file")), 0)
})

test_that("an altered slot count in the tract CSV fails the recomputation", {
  a <- fixture_affordability()
  d <- readr::read_csv(a$files[["tract_csv"]], col_types = readr::cols(geoid = "c", .default = "?"))
  d$licensed_slots_in_tract[1] <- d$licensed_slots_in_tract[1] + 10
  readr::write_csv(d, a$files[["tract_csv"]], na = "")
  expect_gt(failed_units(check_by_suffix(run_aff_checks(a), "__recompute")), 0)
})
