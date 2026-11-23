# Source-to-target validation checks (Module C) ------------------------------
#
# Source = what the Census API returned (the cached raw pull, plus an
#          independent re-pull of a random sample).
# Target = the CSVs written to outputs/, read back from disk.
#
# Each check returns a "check result": a list holding a table of the units it
# evaluated with a logical `pass` column (NA = could not be evaluated, e.g. a
# suppressed value). validation_report.R turns these into pointblank agents.

check_result <- function(check_id, category, indicator_id, description, units, note = NA_character_) {
  if (!"pass" %in% names(units)) stop("units must have a `pass` column")
  list(check_id = check_id, category = category, indicator_id = indicator_id,
       description = description, units = units, note = note)
}

OUTPUT_KEY <- c("indicator_id", "geography", "geoid", "year", "vintage_type", "group", "measure")

# 1. Completeness --------------------------------------------------------------

#' Every row the registry implies, given the vintages that exist.
expected_rows <- function(spec, vintages, tract_geoids, pipeline_cfg) {
  plan <- indicator_pull_plan(spec, vintages, pipeline_cfg)
  geos <- purrr::pmap_dfr(plan, function(survey, year, geography) {
    ids <- if (geography == "county") pipeline_cfg$area$county_geoid else tract_geoids
    tibble::tibble(vintage_type = survey, year = as.integer(year), geography = geography, geoid = ids)
  })
  tidyr::expand_grid(
    geos,
    group = purrr::map_chr(spec$groups, "group"),
    measure = purrr::map_chr(spec$measures, "id")
  ) |>
    dplyr::mutate(indicator_id = spec$id)
}

check_completeness_rows <- function(spec, out, expected) {
  actual <- dplyr::count(out, dplyr::across(dplyr::all_of(OUTPUT_KEY)), name = "n_rows")
  units <- dplyr::full_join(
    dplyr::mutate(expected, expected = TRUE), actual, by = OUTPUT_KEY
  ) |>
    dplyr::mutate(
      expected = dplyr::coalesce(expected, FALSE),
      n_rows = dplyr::coalesce(n_rows, 0L),
      problem = dplyr::case_when(
        expected & n_rows == 0 ~ "missing row",
        !expected ~ "unexpected row",
        n_rows > 1 ~ "duplicate row",
        TRUE ~ NA_character_),
      pass = expected & n_rows == 1
    )
  check_result(
    paste0(spec$id, "__completeness_rows"), "completeness", spec$id,
    sprintf("%s: one row for every vintage x geography x group x measure in the registry (%d expected); no group dropped, no extras, no duplicates.",
            spec$name, nrow(expected)),
    units)
}

check_completeness_tracts <- function(spec, out, tract_geoids, tract_year) {
  if (!"tract" %in% spec$geographies) return(NULL)
  got <- unique(out$geoid[out$geography == "tract" & out$year == tract_year &
                            out$vintage_type == "acs5"])
  all <- union(tract_geoids, got)
  units <- tibble::tibble(
    geoid = all,
    in_tigris = all %in% tract_geoids,
    in_output = all %in% got,
    pass = in_tigris & in_output
  )
  check_result(
    paste0(spec$id, "__completeness_tracts"), "completeness", spec$id,
    sprintf("%s: every Forsyth County tract in TIGER/Line %d (%d tracts, counted with tigris) is in the output, and no others.",
            spec$name, tract_year, length(tract_geoids)),
    units)
}

# 2a. Every directly-sourced value equals the raw API pull ------------------

#' Components rebuilt straight from the raw pull (sums use moe_sum).
source_components <- function(spec, raw) {
  vars <- indicator_variables(spec)
  raw |>
    dplyr::inner_join(vars, by = "variable", relationship = "many-to-many") |>
    dplyr::group_by(vintage_type = survey, year = as.integer(year), geography,
                    geoid = GEOID, group, component) |>
    dplyr::summarise(
      n_vars = dplyr::n(),
      src_e = if (anyNA(estimate)) NA_real_ else sum(estimate),
      src_m = if (dplyr::n() == 1) moe[1] else if (anyNA(estimate)) NA_real_
              else tidycensus::moe_sum(moe, estimate),
      .groups = "drop")
}

direct_measures <- function(spec) {
  purrr::map_dfr(purrr::keep(spec$measures, ~ .x$type %in% c("count", "value")),
                 ~ tibble::tibble(measure = .x$id, component = .x$component))
}

check_source_match <- function(spec, out, raw) {
  src <- source_components(spec, raw)
  units <- out |>
    dplyr::inner_join(direct_measures(spec), by = "measure") |>
    dplyr::select(dplyr::all_of(OUTPUT_KEY), component, source_variables, estimate, moe) |>
    dplyr::left_join(src, by = c("vintage_type", "year", "geography", "geoid", "group", "component")) |>
    dplyr::mutate(pass = !is.na(n_vars) &
                    near_value(estimate, src_e, 1e-9) & near_value(moe, src_m, 1e-9))
  check_result(
    paste0(spec$id, "__source_match"), "source_match", spec$id,
    sprintf("%s: every directly-sourced estimate and MOE in the output (%d rows) equals the Census API response saved at pull time (exactly for single variables; sums of several variables within 1e-9).",
            spec$name, nrow(units)),
    units)
}

same_value <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
near_value <- function(a, b, tol) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) <= tol)

#' Rows that are a single Census variable (no sum, no ratio).
is_direct_row <- function(source_variables) !grepl("[+/(]", source_variables)

# 2b. Independent re-pull of a random sample ----------------------------------

reconciliation_seed <- function(csv_path, seed_cfg) {
  if (identical(seed_cfg, "auto")) {
    strtoi(substr(digest::digest(file = csv_path, algo = "md5"), 1, 7), 16L)
  } else {
    as.integer(seed_cfg)
  }
}

sample_for_reconciliation <- function(out, fraction, min_rows, seed) {
  direct <- dplyr::filter(out, is_direct_row(source_variables))
  n <- min(nrow(direct), max(min_rows, ceiling(fraction * nrow(direct))))
  withr::with_seed(seed, dplyr::slice_sample(direct, n = n))
}

check_reconciliation <- function(spec, out, csv_path, validation_cfg, pipeline_cfg,
                                 fetch = direct_acs_fetch) {
  rc <- validation_cfg$reconciliation
  seed <- reconciliation_seed(csv_path, rc$seed)
  smp <- sample_for_reconciliation(out, rc$sample_fraction, rc$min_rows, seed)
  api <- smp |>
    dplyr::distinct(vintage_type, year, geography) |>
    purrr::pmap_dfr(function(vintage_type, year, geography) {
      vars <- unique(smp$source_variables[smp$vintage_type == vintage_type &
                                            smp$year == year & smp$geography == geography])
      fetch(vars, vintage_type, year, geography, pipeline_cfg$area) |>
        dplyr::mutate(vintage_type = vintage_type, year = as.integer(year), geography = geography)
    })
  units <- smp |>
    dplyr::select(dplyr::all_of(OUTPUT_KEY), source_variables, estimate, moe) |>
    dplyr::left_join(api, by = c("vintage_type", "year", "geography", "geoid",
                                 "source_variables" = "variable")) |>
    dplyr::mutate(pass = same_value(estimate, estimate_api) & same_value(moe, moe_api))
  check_result(
    paste0(spec$id, "__reconciliation"), "reconciliation", spec$id,
    sprintf("%s: a random %d-row sample (%.0f%%, min %d, seed %d) re-pulled from the Census API through a separate code path matches the output exactly (estimate and MOE).",
            spec$name, nrow(units), 100 * rc$sample_fraction, rc$min_rows, seed),
    units)
}

# 2c. Derived values recomputed from their parts ------------------------------

#' Independent re-implementation of the ACS proportion MOE formula.
recompute_prop_moe <- function(num, den, moe_num, moe_den) {
  p <- num / den
  rad <- moe_num^2 - p^2 * moe_den^2
  # Census guidance: if the value under the root is not positive, use the
  # ratio formula instead.
  ifelse(!is.na(rad) & rad > 0, sqrt(pmax(rad, 0)), sqrt(moe_num^2 + p^2 * moe_den^2)) / den
}

#' Independent re-implementation of the reliability flag.
recompute_flag <- function(estimate, moe, base, rel) {
  cv <- (moe / 1.645) / estimate * 100
  out <- rep(NA_character_, length(estimate))
  for (i in seq_along(estimate)) {
    out[i] <-
      if (is.na(estimate[i])) "suppress"
      else if (!is.na(base[i]) && base[i] < rel$min_denominator) "suppress"
      else if (estimate[i] == 0) "suppress"
      else if (is.na(moe[i])) "use_with_caution"
      else if (cv[i] < rel$reliable_cv_max) "reliable"
      else if (cv[i] <= rel$caution_cv_max) "use_with_caution"
      else "suppress"
  }
  out
}

check_derived <- function(spec, out, raw, pipeline_cfg, tol) {
  src <- source_components(spec, raw) |>
    dplyr::select(-n_vars) |>
    dplyr::rename(e = src_e, m = src_m)
  pct <- purrr::keep(spec$measures, ~ .x$type == "percent")
  base <- purrr::map_dfr(pct, function(msr) {
    n <- dplyr::filter(src, component == msr$numerator) |> dplyr::select(-component)
    d <- dplyr::filter(src, component == msr$denominator) |> dplyr::select(-component)
    dplyr::inner_join(n, d, by = c("vintage_type", "year", "geography", "geoid", "group"),
                      suffix = c("_n", "_d")) |>
      dplyr::mutate(measure = msr$id,
                    exp_estimate = ifelse(!is.na(e_d) & e_d > 0, e_n / e_d * 100, NA_real_),
                    exp_moe = ifelse(is.na(exp_estimate), NA_real_,
                                     recompute_prop_moe(e_n, e_d, m_n, m_d) * 100),
                    base = e_d)
  })
  if (nrow(base) == 0) {
    base <- tibble::tibble(vintage_type = character(), year = integer(), geography = character(),
                           geoid = character(), group = character(), measure = character(),
                           exp_estimate = numeric(), exp_moe = numeric(), base = numeric())
  }
  rel <- pipeline_cfg$reliability
  near <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) <= tol)
  units <- out |>
    dplyr::left_join(dplyr::select(base, vintage_type, year, geography, geoid, group, measure,
                                   exp_estimate, exp_moe, base),
                     by = c("vintage_type", "year", "geography", "geoid", "group", "measure")) |>
    dplyr::mutate(
      derived = measure %in% purrr::map_chr(pct, "id"),
      exp_estimate = ifelse(derived, exp_estimate, estimate),
      exp_moe = ifelse(derived, exp_moe, moe),
      exp_se = exp_moe / 1.645,
      exp_cv = ifelse(!is.na(exp_estimate) & exp_estimate > 0, exp_se / exp_estimate * 100, NA_real_),
      exp_flag = recompute_flag(exp_estimate, exp_moe, base, rel),
      pass = near(estimate, exp_estimate) & near(moe, exp_moe) & near(se, exp_se) &
        near(cv, exp_cv) & reliability_flag == exp_flag
    ) |>
    dplyr::select(dplyr::all_of(OUTPUT_KEY), unit, estimate, exp_estimate, moe, exp_moe,
                  se, exp_se, cv, exp_cv, reliability_flag, exp_flag, pass)
  check_result(
    paste0(spec$id, "__derived"), "derived", spec$id,
    sprintf("%s: every percentage and its MOE recomputed from the source parts, and every SE, CV and reliability flag recomputed, matches the output (tolerance %g).",
            spec$name, tol),
    units)
}

# 3. Internal consistency -----------------------------------------------------

#' Output count rows, one column per component (estimate) and _moe.
component_wide <- function(spec, out) {
  out |>
    dplyr::inner_join(direct_measures(spec), by = "measure") |>
    dplyr::select(vintage_type, year, geography, geoid, group, component, estimate, moe)
}

check_consistency <- function(spec, out, validation_cfg) {
  k <- validation_cfg$consistency$moe_multiplier
  comp <- component_wide(spec, out)
  key <- c("vintage_type", "year", "geography", "geoid", "group")
  results <- list()

  # a) parts add up to their total (e.g. owner + renter = all households)
  for (chk in spec$checks$parts_equal_total) {
    parts <- comp |> dplyr::filter(component %in% chk$parts) |>
      dplyr::group_by(dplyr::across(dplyr::all_of(key))) |>
      dplyr::summarise(parts_sum = sum(estimate), parts_moe2 = sum(moe^2), .groups = "drop")
    tot <- comp |> dplyr::filter(component == chk$total) |>
      dplyr::select(dplyr::all_of(key), total = estimate, total_moe = moe)
    u <- dplyr::inner_join(parts, tot, by = key) |>
      dplyr::mutate(diff = parts_sum - total,
                    allowed = k * sqrt(parts_moe2 + total_moe^2),
                    pass = abs(diff) <= allowed)
    results[[length(results) + 1]] <- check_result(
      paste0(spec$id, "__parts_", paste(chk$parts, collapse = "_"), "_equal_", chk$total),
      "consistency", spec$id,
      sprintf("%s: %s add up to %s within %g x combined MOE, for every group, place and year.",
              spec$name, paste(chk$parts, collapse = " + "), chk$total, k),
      u)
  }

  # b) mutually exclusive subgroups add up to the total group
  sg <- spec$checks$subgroups_sum_to_total
  if (!is.null(sg)) {
    key2 <- c("vintage_type", "year", "geography", "geoid", "component")
    parts <- comp |> dplyr::filter(group %in% sg$groups, component %in% sg$components) |>
      dplyr::group_by(dplyr::across(dplyr::all_of(key2))) |>
      dplyr::summarise(n_groups = dplyr::n(), parts_sum = sum(estimate),
                       parts_moe2 = sum(moe^2), .groups = "drop")
    tot <- comp |> dplyr::filter(group == sg$total_group, component %in% sg$components) |>
      dplyr::select(dplyr::all_of(key2), total = estimate, total_moe = moe) |>
      dplyr::mutate(has_total = TRUE)
    u <- dplyr::full_join(parts, tot, by = key2) |>
      dplyr::mutate(diff = parts_sum - total,
                    allowed = k * sqrt(parts_moe2 + total_moe^2),
                    pass = dplyr::case_when(
                      # a subgroup or the total row is missing: fail
                      is.na(n_groups) | n_groups < length(sg$groups) | is.na(has_total) ~ FALSE,
                      # NA (not evaluable) when Census suppressed a value
                      TRUE ~ abs(diff) <= allowed))
    results[[length(results) + 1]] <- check_result(
      paste0(spec$id, "__subgroups_sum_to_total"), "consistency", spec$id,
      sprintf("%s: the %d mutually exclusive groups add up to '%s' within %g x combined MOE (rows with a suppressed group cannot be evaluated).",
              spec$name, length(sg$groups), sg$total_group, k),
      u)
  }

  # c) numerator <= denominator for every percentage
  pct <- purrr::keep(spec$measures, ~ .x$type == "percent")
  if (length(pct)) {
    u <- purrr::map_dfr(pct, function(m) {
      n <- dplyr::filter(comp, component == m$numerator) |> dplyr::select(dplyr::all_of(key), num = estimate)
      d <- dplyr::filter(comp, component == m$denominator) |> dplyr::select(dplyr::all_of(key), den = estimate)
      dplyr::inner_join(n, d, by = key) |> dplyr::mutate(measure = m$id, pass = num <= den)
    })
    results[[length(results) + 1]] <- check_result(
      paste0(spec$id, "__numerator_le_denominator"), "consistency", spec$id,
      sprintf("%s: every percentage's numerator is no larger than its denominator.", spec$name),
      u)
  }

  # d) values that must rise in order (e.g. income quintile upper limits)
  for (chk in spec$checks$ordered) {
    u <- comp |>
      dplyr::filter(component %in% chk$components) |>
      dplyr::mutate(pos = match(component, chk$components)) |>
      dplyr::group_by(dplyr::across(dplyr::all_of(key))) |>
      dplyr::arrange(pos, .by_group = TRUE) |>
      dplyr::summarise(n = dplyr::n(), values = paste(estimate, collapse = " < "),
                       pass = if (n != length(chk$components)) FALSE
                              else if (anyNA(estimate)) NA
                              else all(diff(estimate) > 0),
                       .groups = "drop")
    results[[length(results) + 1]] <- check_result(
      paste0(spec$id, "__ordered_", paste(chk$components, collapse = "_")),
      "consistency", spec$id,
      sprintf("%s: %s rise in that order for every place and year.",
              spec$name, paste(chk$components, collapse = " < ")),
      u)
  }
  results
}

# 5. Legacy reconciliation (warnings only) -----------------------------------

read_legacy_reference <- function(path) {
  readr::read_csv(path, comment = "#", na = "", progress = FALSE,
                  col_types = readr::cols(year = readr::col_integer(),
                                          legacy_value = readr::col_double(),
                                          .default = readr::col_character()))
}

check_legacy <- function(all_out, legacy, validation_cfg) {
  tol <- validation_cfg$legacy$relative_tolerance
  u <- legacy |>
    dplyr::left_join(dplyr::select(all_out, dplyr::all_of(OUTPUT_KEY), estimate), by = OUTPUT_KEY) |>
    dplyr::mutate(rel_diff = abs(estimate - legacy_value) / abs(legacy_value),
                  pass = !is.na(rel_diff) & rel_diff <= tol)
  note <- if (nrow(legacy) == 0)
    "No legacy figures loaded yet: config/legacy_reference.csv has only headers (TODO)." else NA_character_
  check_result("legacy_reconciliation", "legacy", "all",
               sprintf("Refreshed values within %.0f%% of figures previously published by Forsyth Futures / Forsyth Family Power (differences are warnings; see the explanation column).", 100 * tol),
               u, note = note)
}

# Everything for one indicator -------------------------------------------------

run_indicator_checks <- function(spec, csv_path, raw, labels, vintages, tracts, pipeline_cfg,
                                 validation_cfg, fetch = direct_acs_fetch) {
  out <- read_output_csv(csv_path)
  tract_year <- latest_vintage(vintages, "acs5")
  expected <- expected_rows(spec, vintages, tracts$geoid, pipeline_cfg)
  c(
    list(
      check_completeness_rows(spec, out, expected),
      check_completeness_tracts(spec, out, tracts$geoid, tract_year),
      check_source_match(spec, out, raw),
      check_label_consistency(spec, labels, vintages, pipeline_cfg),
      check_reconciliation(spec, out, csv_path, validation_cfg, pipeline_cfg, fetch = fetch),
      check_derived(spec, out, raw, pipeline_cfg, validation_cfg$derived$tolerance)
    ),
    check_consistency(spec, out, validation_cfg)
  ) |>
    purrr::compact()
}
