# Validation self-tests: clean fixture outputs pass every check; each
# deliberate corruption makes the right check fail.

test_that("clean outputs pass every check", {
  r <- fixture_run()
  for (chk in r$checks) {
    expect_equal(failed_units(chk), 0, label = chk$check_id)
  }
})

test_that("a dropped tract fails completeness", {
  r <- fixture_run(function(d) dplyr::filter(d, geoid != "37067000200"))
  expect_gt(failed_units(check_by_suffix(r$checks, "__completeness_tracts")), 0)
  expect_gt(failed_units(check_by_suffix(r$checks, "__completeness_rows")), 0)
})

test_that("a dropped group fails completeness", {
  r <- fixture_run(function(d) dplyr::filter(d, !(group == "Asian alone" & year == 2021)))
  expect_gt(failed_units(check_by_suffix(r$checks, "__completeness_rows")), 0)
})

test_that("an altered estimate fails the source match", {
  r <- fixture_run(function(d) {
    i <- which(d$measure == "owner_households" & d$geography == "county")[1]
    d$estimate[i] <- d$estimate[i] + 1
    d
  })
  expect_equal(failed_units(check_by_suffix(r$checks, "__source_match")), 1)
})

test_that("an altered percentage fails the derived recomputation", {
  r <- fixture_run(function(d) {
    i <- which(d$measure == "homeownership_rate")[1]
    d$estimate[i] <- d$estimate[i] + 0.5
    d
  })
  expect_gt(failed_units(check_by_suffix(r$checks, "__derived")), 0)
})

test_that("a wrong reliability flag fails the derived recomputation", {
  r <- fixture_run(function(d) {
    i <- which(d$reliability_flag == "reliable")[1]
    d$reliability_flag[i] <- "suppress"
    d
  })
  expect_gt(failed_units(check_by_suffix(r$checks, "__derived")), 0)
})

test_that("an altered estimate in the re-pull sample fails reconciliation", {
  cfg <- fixture_cfgs()
  cfg$validation$reconciliation$sample_fraction <- 1   # sample every row
  spec <- fixture_spec(); raw <- fixture_raw(spec)
  path <- write_indicator_csv(build_indicator_table(spec, raw, cfg$pipeline), cfg$pipeline)
  d <- read_output_csv(path)
  i <- which(d$measure == "renter_households")[1]
  d$moe[i] <- d$moe[i] + 1
  readr::write_csv(d, path, na = "")
  chk <- check_reconciliation(spec, read_output_csv(path), path, cfg$validation, cfg$pipeline,
                              fetch = fixture_fetch(raw))
  expect_equal(failed_units(chk), 1)
})

test_that("owner + renter not equal to total fails consistency", {
  r <- fixture_run(function(d) {
    i <- which(d$measure == "renter_households" & d$geography == "county")[1]
    d$estimate[i] <- d$estimate[i] * 3
    d
  })
  expect_gt(failed_units(check_by_suffix(r$checks, "__parts_owner_renter_equal_total")), 0)
  expect_gt(failed_units(check_by_suffix(r$checks, "__subgroups_sum_to_total")), 0)
})

test_that("a 2020 ACS 1-year value in the trend file fails the rules", {
  cfg <- fixture_cfgs()
  spec <- fixture_spec(); raw <- fixture_raw(spec)
  tbl <- build_indicator_table(spec, raw, cfg$pipeline)
  bad <- dplyr::filter(tbl, vintage_type == "acs1", year == 2021) |>
    dplyr::mutate(year = 2020L)                       # include_in_trend left TRUE
  trend <- dplyr::bind_rows(dplyr::filter(tbl, geography == "county"), bad)
  ag <- rules_agent(trend, "trends_county.csv", cfg$validation, trend_file = TRUE)
  expect_false(pointblank::all_passed(ag))
  clean <- rules_agent(dplyr::filter(tbl, geography == "county"), "trends_county.csv",
                       cfg$validation, trend_file = TRUE)
  expect_true(pointblank::all_passed(clean))
})

test_that("the gate stops the pipeline on any failure", {
  ok <- list(summary = tibble::tibble(check_id = "a", step = "s", n_failed = 0L, status = "pass"),
             counts = list(pass = 1, warn = 0, fail = 0), html = "x")
  expect_true(suppressMessages(validation_gate(ok)))
  bad <- ok; bad$summary$status <- "fail"; bad$summary$n_failed <- 3L
  expect_error(validation_gate(bad), "Publishing is blocked")
})
