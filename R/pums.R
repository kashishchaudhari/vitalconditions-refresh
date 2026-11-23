# PUMS: Child Housing Cost Burden (milestone 3) -------------------------------
#
# Share of children (under 18, living in households) whose household pays 30%
# or more, and 50% or more, of its income on housing. Built from ACS Public
# Use Microdata Sample (PUMS) person records for the PUMAs covering Forsyth
# County, with the 80 person replicate weights for standard errors
# (successive-difference replication, as the Census Bureau documents).
#
# Forsyth County's PUMAs (01801, 01802, 01803) cover exactly the county in both
# the 2010 and 2020 PUMA definitions. See docs/assumptions.md.

PUMS_PERSON_VARS <- c("AGEP", "TEN", "GRPIP", "OCPIP", "HISP", "RAC1P", "SPORDER")

pums_dataset_exists <- function(year, survey) {
  url <- sprintf("https://api.census.gov/data/%d/acs/%s/pums.json", year, survey)
  curl::curl_fetch_memory(url)$status_code == 200
}

#' Resolve the PUMS vintages to build from config/pipeline.yml. "latest" is
#' found by asking the Census API, counting down from the current year.
detect_pums_vintages <- function(pipeline_cfg, through_year = as.integer(format(Sys.Date(), "%Y"))) {
  cfg <- pipeline_cfg$pums
  latest <- function(survey) {
    for (y in through_year:(through_year - 5)) if (pums_dataset_exists(y, survey)) return(y)
    stop("No ", survey, " PUMS release found in the last 5 years.", call. = FALSE)
  }
  resolve <- function(years, survey) {
    years <- unlist(years)
    out <- unique(as.integer(ifelse(years == "latest", latest(survey), years)))
    out <- out[!(survey == "acs1" & out == 2020)]   # no standard 2020 1-year
    for (y in out) if (!pums_dataset_exists(y, survey)) {
      stop("PUMS ", survey, " ", y, " is not on the Census API.", call. = FALSE)
    }
    tibble::tibble(survey = survey, year = out)
  }
  dplyr::bind_rows(resolve(cfg$acs5_years, "acs5"), resolve(cfg$acs1_years, "acs1")) |>
    dplyr::arrange(survey, year)
}

#' PUMA definition used by a PUMS release (2020 PUMAs from 2022 data on).
puma_vintage <- function(survey, year) {
  ifelse(year >= 2022, "2020 PUMAs", "2010 PUMAs")
}

pums_hh_type_var <- function(year) if (year >= 2020) "TYPEHUGQ" else "TYPE"

#' Pull (or read the cached) person records for the county's PUMAs.
pull_pums_cached <- function(survey, year, pipeline_cfg) {
  area <- pipeline_cfg$area
  pumas <- unlist(pipeline_cfg$pums$pumas)
  dir <- file.path(dirname(pipeline_cfg$paths$cache_dir), "pums")
  path <- file.path(dir, sprintf("pums_%s_%d_%s.rds", survey, year, paste(pumas, collapse = "-")))
  if (file.exists(path)) return(readRDS(path))
  if (!census_key_available()) stop("CENSUS_API_KEY is needed to download PUMS.", call. = FALSE)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  d <- suppressMessages(tidycensus::get_pums(
    variables = c(PUMS_PERSON_VARS, pums_hh_type_var(year)),
    state = area$state_fips, puma = pumas, year = year, survey = survey,
    rep_weights = "person", recode = FALSE
  ))
  d <- dplyr::rename(d, HHTYPE = dplyr::all_of(pums_hh_type_var(year)))
  d <- dplyr::mutate(d, dplyr::across(c(AGEP, TEN, GRPIP, OCPIP, HISP, RAC1P, SPORDER, HHTYPE,
                                        WGTP, PWGTP, dplyr::matches("^PWGTP[0-9]+$")),
                                      ~ suppressWarnings(as.numeric(.x))))
  saveRDS(d, path)
  d
}

pull_pums_all <- function(pums_vintages, pipeline_cfg) {
  purrr::pmap_dfr(pums_vintages, function(survey, year) {
    pull_pums_cached(survey, year, pipeline_cfg) |>
      dplyr::mutate(survey = survey, year = as.integer(year), .before = 1)
  })
}

#' Child-level flags: one row per child under 18 living in a household.
child_burden_records <- function(pums) {
  pums |>
    dplyr::filter(AGEP < 18, HHTYPE == 1) |>
    dplyr::mutate(
      tenure = dplyr::case_when(TEN %in% c(1, 2) ~ "owner", TEN == 3 ~ "renter", TRUE ~ "other"),
      # GRPIP / OCPIP are blank when cost as a share of income cannot be
      # computed (no household income, or no cash rent); tidycensus reads
      # blanks as 0 or NA depending on the year, so both mean "not computed".
      cost_share = dplyr::case_when(
        tenure == "renter" & GRPIP > 0 ~ GRPIP,
        tenure == "owner" & OCPIP > 0 ~ OCPIP,
        TRUE ~ NA_real_),
      computed = !is.na(cost_share),
      burden30 = computed & cost_share >= 30,
      burden50 = computed & cost_share >= 50,
      race_eth = dplyr::case_when(
        HISP != 1 ~ "Hispanic or Latino (any race)",
        RAC1P == 1 ~ "White, not Hispanic or Latino",
        RAC1P == 2 ~ "Black or African American, not Hispanic or Latino",
        RAC1P == 6 ~ "Asian, not Hispanic or Latino",
        TRUE ~ "All other races or two or more races, not Hispanic or Latino")
    )
}

PUMS_GROUPS <- list(
  "All children"                                                   = quote(TRUE),
  "Hispanic or Latino (any race)"                                  = quote(race_eth == "Hispanic or Latino (any race)"),
  "White, not Hispanic or Latino"                                  = quote(race_eth == "White, not Hispanic or Latino"),
  "Black or African American, not Hispanic or Latino"              = quote(race_eth == "Black or African American, not Hispanic or Latino"),
  "Asian, not Hispanic or Latino"                                  = quote(race_eth == "Asian, not Hispanic or Latino"),
  "All other races or two or more races, not Hispanic or Latino"  = quote(race_eth == "All other races or two or more races, not Hispanic or Latino"),
  "Children in renter households"                                  = quote(tenure == "renter"),
  "Children in owner households"                                   = quote(tenure == "owner")
)

PUMS_MEASURES <- tibble::tribble(
  ~measure,                        ~measure_label,                                                                   ~unit,     ~num,       ~den,
  "children_cost_computed",        "Children in households where housing cost as a share of income can be computed", "count",   "computed", NA,
  "children_cost_burdened",        "Children in households paying 30% or more of income on housing",                 "count",   "burden30", NA,
  "children_severely_burdened",    "Children in households paying 50% or more of income on housing",                 "count",   "burden50", NA,
  "pct_children_cost_burdened",    "% of children in households paying 30% or more of income on housing",           "percent", "burden30", "computed",
  "pct_children_severely_burdened","% of children in households paying 50% or more of income on housing",           "percent", "burden50", "computed"
)

#' Estimates with replicate-weight standard errors, via srvyr.
estimate_child_burden <- function(pums, pipeline_cfg, spec) {
  kids <- child_burden_records(pums)
  purrr::map_dfr(split(kids, list(kids$survey, kids$year), drop = TRUE), function(d) {
    svy <- srvyr::as_survey_rep(
      d, weights = PWGTP, repweights = dplyr::matches("^PWGTP[0-9]+$"),
      type = "successive-difference", mse = TRUE
    )
    purrr::imap_dfr(PUMS_GROUPS, function(cond, group) {
      in_g <- eval(cond, d)
      in_g <- if (length(in_g) == 1) rep(in_g, nrow(d)) else in_g
      s <- svy |> srvyr::mutate(g = in_g)
      n_den <- sum(in_g & d$computed)
      purrr::pmap_dfr(PUMS_MEASURES, function(measure, measure_label, unit, num, den) {
        if (unit == "count") {
          r <- s |> srvyr::summarise(v = srvyr::survey_total(as.numeric(g & .data[[num]]), vartype = "se"))
        } else {
          r <- s |> srvyr::summarise(v = srvyr::survey_ratio(as.numeric(g & .data[[num]]),
                                                             as.numeric(g & .data[[den]]), vartype = "se"))
          r$v <- r$v * 100; r$v_se <- r$v_se * 100
        }
        tibble::tibble(vintage_type = d$survey[1], year = d$year[1], group = group,
                       measure = measure, measure_label = measure_label, unit = unit,
                       estimate = r$v, se_rep = r$v_se, n_cases = n_den)
      })
    })
  })
}

build_child_burden_table <- function(est, spec, pipeline_cfg) {
  rel <- pipeline_cfg$reliability
  rel$min_denominator <- pipeline_cfg$pums$min_sample_cases
  area <- pipeline_cfg$area
  group_order <- names(PUMS_GROUPS)
  est |>
    dplyr::mutate(
      estimate = dplyr::if_else(is.nan(estimate), NA_real_, estimate),
      moe = 1.645 * se_rep,
      base = n_cases
    ) |>
    add_reliability(rel) |>
    dplyr::mutate(
      indicator_id = spec$id,
      vital_condition = spec$vital_condition,
      geography = "county_pums",
      geoid = area$county_geoid,
      geo_name = paste0(area$county_name, " (PUMAs ", paste(unlist(pipeline_cfg$pums$pumas), collapse = ", "), ")"),
      year = as.integer(year),
      acs_period = acs_period_label(vintage_type, year),
      include_in_trend = include_in_trend(vintage_type, year),
      source_table = paste0("ACS ", ifelse(vintage_type == "acs5", "5-year", "1-year"), " PUMS person file"),
      source_variables = "AGEP<18, TYPE/TYPEHUGQ=1, TEN, GRPIP (renters) / OCPIP (owners), HISP, RAC1P; PWGTP + PWGTP1-80",
      geo_vintage = paste0(puma_vintage(vintage_type, year), " 01801-01803 (cover all of Forsyth County)"),
      pums_note = "PUMS estimates differ slightly from published ACS tables because of sampling and disclosure-avoidance noise.",
      notes = paste_notes(reliability_note, pums_note)
    ) |>
    dplyr::arrange(vintage_type, year, match(group, group_order), match(measure, PUMS_MEASURES$measure)) |>
    (\(x) x[, names(OUTPUT_SCHEMA)])()
}

# Validation for PUMS outputs -------------------------------------------------

#' Independent recomputation with plain weighted sums (no survey package):
#' estimate = sum(PWGTP * x); SE = sqrt(4/80 * sum_r (est_r - est)^2).
recompute_child_burden <- function(pums) {
  kids <- child_burden_records(pums)
  repcols <- grep("^PWGTP[0-9]+$", names(kids), value = TRUE)
  purrr::map_dfr(split(kids, list(kids$survey, kids$year), drop = TRUE), function(d) {
    W <- as.matrix(d[, repcols])
    purrr::imap_dfr(PUMS_GROUPS, function(cond, group) {
      g <- eval(cond, d); g <- if (length(g) == 1) rep(g, nrow(d)) else g
      purrr::pmap_dfr(PUMS_MEASURES, function(measure, measure_label, unit, num, den) {
        x <- as.numeric(g & d[[num]])
        est <- sum(d$PWGTP * x); reps <- colSums(W * x)
        if (unit == "percent") {
          y <- as.numeric(g & d[[den]])
          dn <- sum(d$PWGTP * y); repd <- colSums(W * y)
          est_r <- if (dn > 0) est / dn * 100 else NA_real_
          reps <- ifelse(repd > 0, reps / repd * 100, NA_real_)
          est <- est_r
        }
        se <- sqrt(4 / length(repcols) * sum((reps - est)^2))
        tibble::tibble(vintage_type = d$survey[1], year = as.integer(d$year[1]), group = group,
                       measure = measure, exp_estimate = est, exp_moe = 1.645 * se)
      })
    })
  })
}

check_pums_recompute <- function(spec, out, pums, tol_rel = 1e-6) {
  exp <- recompute_child_burden(pums)
  units <- out |>
    dplyr::select(dplyr::all_of(OUTPUT_KEY), estimate, moe) |>
    dplyr::full_join(exp, by = c("vintage_type", "year", "group", "measure")) |>
    dplyr::mutate(
      pass = near_value(estimate, exp_estimate, tol_rel * pmax(1, abs(exp_estimate))) &
        near_value(moe, exp_moe, tol_rel * pmax(1, abs(exp_moe)))
    )
  check_result(
    paste0(spec$id, "__source_match"), "source_match", spec$id,
    sprintf("%s: every estimate and MOE recomputed from the cached PUMS microdata with plain weighted sums and the replicate-weight formula (no survey package) matches the output.",
            spec$name),
    units)
}

#' Weighted PUMS totals vs published ACS totals for the same PUMAs and year.
pull_pums_benchmark_published <- function(pums_vintages, pipeline_cfg) {
  pumas <- unlist(pipeline_cfg$pums$pumas)
  purrr::pmap_dfr(pums_vintages, function(survey, year) {
    d <- pull_acs_cached(c("B01003_001", "B11001_001", "B09001_001"), survey, year,
                         "public use microdata area",
                         list(state_fips = pipeline_cfg$area$state_fips, county_fips = NULL),
                         pipeline_cfg$paths$cache_dir)
    d |>
      dplyr::filter(substr(GEOID, 3, 7) %in% pumas) |>
      dplyr::mutate(vintage_type = survey, year = as.integer(year))
  })
}

check_pums_benchmark <- function(pums, published, validation_cfg) {
  tol <- validation_cfg$pums$relative_tolerance
  pumas <- unique(substr(published$GEOID, 3, 7))
  wt <- pums |>
    dplyr::group_by(vintage_type = survey, year, puma = PUMA) |>
    dplyr::summarise(
      persons = sum(PWGTP),
      households = sum(WGTP[SPORDER == 1 & HHTYPE == 1]),
      children_under_18 = sum(PWGTP[AGEP < 18]),
      .groups = "drop") |>
    tidyr::pivot_longer(c(persons, households, children_under_18), names_to = "total", values_to = "pums_weighted")
  pub <- published |>
    dplyr::transmute(vintage_type, year, puma = substr(GEOID, 3, 7),
                     total = dplyr::recode(variable, B01003_001 = "persons", B11001_001 = "households",
                                           B09001_001 = "children_under_18"),
                     published = estimate)
  units <- dplyr::full_join(wt, pub, by = c("vintage_type", "year", "puma", "total")) |>
    dplyr::mutate(rel_diff = (pums_weighted - published) / published,
                  pass = !is.na(rel_diff) & abs(rel_diff) <= tol)
  check_result(
    "child_housing_cost_burden__pums_benchmark", "consistency", "child_housing_cost_burden",
    sprintf("PUMS benchmark: weighted PUMS totals (persons, households, children under 18) for each Forsyth PUMA match the published ACS totals for the same PUMA and year within %.0f%% (published tables: B01003, B11001, B09001).",
            100 * tol),
    units)
}

#' Expected rows: every PUMS vintage x group x measure.
check_pums_completeness <- function(spec, out, pums_vintages, pipeline_cfg) {
  expected <- tidyr::expand_grid(
    dplyr::transmute(pums_vintages, vintage_type = survey, year = as.integer(year)),
    group = names(PUMS_GROUPS), measure = PUMS_MEASURES$measure
  ) |>
    dplyr::mutate(indicator_id = spec$id, geography = "county_pums",
                  geoid = pipeline_cfg$area$county_geoid)
  check_completeness_rows(spec, out, expected)
}

#' Consistency: race groups and tenure groups each sum to all children;
#' numerator <= denominator.
check_pums_consistency <- function(spec, out, validation_cfg) {
  k <- validation_cfg$consistency$moe_multiplier
  cnt <- dplyr::filter(out, unit == "count")
  key <- c("vintage_type", "year", "measure")
  sets <- list(
    race = names(PUMS_GROUPS)[2:6],
    tenure = c("Children in renter households", "Children in owner households")
  )
  res <- purrr::imap(sets, function(groups, nm) {
    parts <- cnt |> dplyr::filter(group %in% groups) |>
      dplyr::group_by(dplyr::across(dplyr::all_of(key))) |>
      dplyr::summarise(n_groups = dplyr::n(), parts_sum = sum(estimate), parts_moe2 = sum(moe^2), .groups = "drop")
    tot <- cnt |> dplyr::filter(group == "All children") |>
      dplyr::select(dplyr::all_of(key), total = estimate, total_moe = moe)
    u <- dplyr::full_join(parts, tot, by = key) |>
      dplyr::mutate(diff = parts_sum - total, allowed = k * sqrt(parts_moe2 + total_moe^2),
                    pass = dplyr::if_else(is.na(n_groups) | n_groups < length(groups), FALSE,
                                          abs(diff) <= pmax(allowed, 1e-6 * abs(total))))
    check_result(paste0(spec$id, "__", nm, "_groups_sum_to_all"), "consistency", spec$id,
                 sprintf("%s: the %s groups add up to all children (they are mutually exclusive and, for tenure, children in households where cost can be computed are all owners or renters).",
                         spec$name, nm), u)
  })
  w <- cnt |> dplyr::select(vintage_type, year, group, measure, estimate) |>
    tidyr::pivot_wider(names_from = measure, values_from = estimate) |>
    dplyr::mutate(pass = children_severely_burdened <= children_cost_burdened &
                    children_cost_burdened <= children_cost_computed)
  c(unname(res), list(check_result(
    paste0(spec$id, "__numerator_le_denominator"), "consistency", spec$id,
    sprintf("%s: severely burdened <= burdened <= all children with computed cost, for every group and year.", spec$name),
    w)))
}

run_pums_checks <- function(spec, csv_path, pums, pums_vintages, published, pipeline_cfg, validation_cfg) {
  out <- read_output_csv(csv_path)
  c(
    list(
      check_pums_completeness(spec, out, pums_vintages, pipeline_cfg),
      check_pums_recompute(spec, out, pums),
      check_pums_benchmark(pums, published, validation_cfg)
    ),
    check_pums_consistency(spec, out, validation_cfg)
  )
}
