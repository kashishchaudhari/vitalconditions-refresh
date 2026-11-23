rel <- list(reliable_cv_max = 15, caution_cv_max = 30, min_denominator = 50)

test_that("CV and reliability flags follow the configured thresholds", {
  # SE = MOE / 1.645, so MOE = 1.645 * SE gives an exact CV.
  df <- tibble::tibble(
    estimate = c(100, 100, 100, 100, 100, 0, NA, 40, 100),
    moe      = 1.645 * c(10, 14.9, 15, 30, 30.1, 5, NA, 1, NA),
    base     = c(NA, NA, NA, NA, NA, NA, NA, 30, NA)
  )
  out <- add_reliability(df, rel)
  expect_equal(out$se[1], 10)
  expect_equal(out$cv[1:5], c(10, 14.9, 15, 30, 30.1))
  expect_equal(out$reliability_flag, c(
    "reliable", "reliable", "use_with_caution", "use_with_caution", "suppress",
    "suppress",  # zero estimate
    "suppress",  # not published
    "suppress",  # base below min_denominator
    "use_with_caution"   # no MOE published (top-coded or controlled)
  ))
  expect_true(all(!is.na(out$reliability_flag)))
})

test_that("thresholds come from config, not code", {
  df <- tibble::tibble(estimate = 100, moe = 1.645 * 12)
  expect_equal(add_reliability(df, rel)$reliability_flag, "reliable")
  expect_equal(add_reliability(df, modifyList(rel, list(reliable_cv_max = 10)))$reliability_flag,
               "use_with_caution")
})

test_that("2020 ACS 1-year is excluded from trends, other years are not", {
  expect_false(include_in_trend("acs1", 2020))
  expect_true(include_in_trend("acs1", 2019))
  expect_true(include_in_trend("acs5", 2020))
})

test_that("built table has the output schema and a flag on every row", {
  r <- fixture_run()
  out <- read_output_csv(r$path)
  expect_identical(names(out), names(OUTPUT_SCHEMA))
  expect_false(anyNA(out$reliability_flag))
  expect_false(any(out$vintage_type == "acs1" & out$year == 2020))
})

test_that("summed components use moe_sum on the individual estimates (zero rule)", {
  # Regression test: MOE must be computed before the estimate is summed.
  spec <- list(groups = list(list(group = "All", table = "B99999")),
               components = list(both = c("001", "002", "003")))
  raw <- tibble::tibble(survey = "acs5", year = 2024L, geography = "tract", GEOID = "1", NAME = "x",
                        variable = c("B99999_001", "B99999_002", "B99999_003"),
                        estimate = c(10, 0, 0), moe = c(5, 12, 20))
  comp <- build_components(spec, raw)
  expect_equal(comp$estimate, 10)
  expect_equal(comp$moe, tidycensus::moe_sum(c(5, 12, 20), c(10, 0, 0)))   # sqrt(5^2 + 20^2)
  expect_equal(comp$moe, sqrt(5^2 + 20^2))
})
