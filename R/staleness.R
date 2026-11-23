# Staleness report -------------------------------------------------------------
#
# One row per active indicator: what the legacy site shows, the newest
# vintage now available, and how many years newer the refresh is.

build_staleness_report <- function(registry, all_out, vintages) {
  ids <- unique(all_out$indicator_id)
  latest1 <- latest_vintage(vintages, "acs1")
  latest5 <- latest_vintage(vintages, "acs5")
  purrr::map_dfr(ids, function(id) {
    spec <- registry[[id]]
    lv <- spec$legacy_vintage %||% list()
    d <- dplyr::filter(all_out, indicator_id == id)
    newest <- function(s) {
      y <- d$year[d$vintage_type == s]
      if (length(y)) max(y) else NA_integer_
    }
    new1 <- newest("acs1"); new5 <- newest("acs5")
    legacy_year <- as.integer(lv$year %||% NA)
    legacy_survey <- lv$survey %||% NA_character_
    refreshed_year <- switch(legacy_survey %||% "none", acs1 = new1, acs5 = new5,
                             max(c(new1, new5), na.rm = TRUE))
    suffix <- if (identical(spec$source, "pums")) " PUMS" else ""
    refreshed_label <- if (identical(legacy_survey, "acs5") || is.na(new1))
      paste0(acs_period_label("acs5", new5), " ACS 5-year", suffix)
    else paste0(new1, " ACS 1-year", suffix)
    flags <- table(factor(d$reliability_flag, levels = RELIABILITY_LEVELS))
    tibble::tibble(
      indicator_id = id,
      indicator_name = spec$name,
      vital_condition = spec$vital_condition,
      legacy_vintage = lv$label %||% "unknown",
      legacy_year = legacy_year,
      legacy_vintage_verified = isTRUE(lv$verified),
      refreshed_vintage = refreshed_label,
      latest_available_acs1 = latest1,
      latest_available_acs5 = acs_period_label("acs5", latest5),
      newest_in_output_acs1 = new1,
      newest_in_output_acs5 = new5,
      years_newer = if (is.na(legacy_year)) NA_integer_ else as.integer(refreshed_year - legacy_year),
      earliest_year = min(d$year),
      n_rows = nrow(d),
      pct_reliable = round(100 * flags[["reliable"]] / nrow(d), 1),
      pct_use_with_caution = round(100 * flags[["use_with_caution"]] / nrow(d), 1),
      pct_suppress = round(100 * flags[["suppress"]] / nrow(d), 1),
      status = dplyr::case_when(
        is.na(legacy_year) ~ paste0("New or legacy vintage unknown; now ", refreshed_label),
        refreshed_year > legacy_year ~ paste0("Refreshed: ", lv$label, " -> ", refreshed_label),
        TRUE ~ "Not newer than legacy"
      ),
      notes = if (isTRUE(lv$verified)) NA_character_ else
        "Legacy vintage taken from the project brief; not yet checked against the live legacy page."
    )
  })
}

write_staleness_report <- function(registry, indicator_paths, vintages, pipeline_cfg) {
  all_out <- purrr::map_dfr(unname(indicator_paths), read_output_csv)
  rep <- build_staleness_report(registry, all_out, vintages)
  path <- file.path(pipeline_cfg$paths$tableau_dir, "staleness_report.csv")
  readr::write_csv(rep, path, na = "")
  path
}

#' Validation: one row per active indicator, and each indicator's output
#' reaches the newest vintage available for every survey it uses.
check_staleness <- function(staleness_path, registry, active_ids, vintages, pums_vintages = NULL) {
  rep <- readr::read_csv(staleness_path, show_col_types = FALSE, progress = FALSE)
  latest1 <- latest_vintage(vintages, "acs1")
  latest5 <- latest_vintage(vintages, "acs5")
  is_pums <- function(id) identical(registry[[id]]$source, "pums")
  exp1 <- function(id) if (is_pums(id)) max(pums_vintages$year[pums_vintages$survey == "acs1"]) else latest1
  exp5 <- function(id) if (is_pums(id)) max(pums_vintages$year[pums_vintages$survey == "acs5"]) else latest5
  units <- tibble::tibble(indicator_id = active_ids) |>
    dplyr::left_join(dplyr::mutate(rep, in_report = TRUE), by = "indicator_id") |>
    dplyr::mutate(
      uses_acs1 = purrr::map_lgl(indicator_id, ~ "acs1" %in% registry[[.x]]$surveys),
      uses_acs5 = purrr::map_lgl(indicator_id, ~ "acs5" %in% registry[[.x]]$surveys),
      expected_acs1 = purrr::map_dbl(indicator_id, exp1),
      expected_acs5 = purrr::map_dbl(indicator_id, exp5),
      pass = !is.na(in_report) &
        (!uses_acs1 | newest_in_output_acs1 == expected_acs1) &
        (!uses_acs5 | newest_in_output_acs5 == expected_acs5) &
        (is.na(years_newer) | years_newer >= 0)
    ) |>
    dplyr::select(indicator_id, uses_acs1, newest_in_output_acs1, expected_acs1, uses_acs5,
                  newest_in_output_acs5, expected_acs5, years_newer, pass)
  units <- dplyr::bind_rows(units, tibble::tibble(
    indicator_id = setdiff(rep$indicator_id, active_ids), pass = rep(FALSE, length(setdiff(rep$indicator_id, active_ids)))))
  check_result("staleness_report", "completeness", "all",
               sprintf("Staleness report: one row per active indicator (%d), each refreshed to the newest available vintage (ACS tables: 1-year %d, 5-year %s; PUMS: newest PUMS release).",
                       length(active_ids), latest1, acs_period_label("acs5", latest5)),
               units)
}
