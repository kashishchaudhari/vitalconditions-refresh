# Turning raw ACS rows into the long Tableau schema --------------------------

#' Output schema: column name -> type. Validation checks outputs against this.
OUTPUT_SCHEMA <- c(
  indicator_id     = "character",
  vital_condition  = "character",
  geography        = "character",
  geoid            = "character",
  geo_name         = "character",
  year             = "integer",
  vintage_type     = "character",
  acs_period       = "character",
  group            = "character",
  measure          = "character",
  measure_label    = "character",
  unit             = "character",
  estimate         = "numeric",
  moe              = "numeric",
  se               = "numeric",
  cv               = "numeric",
  reliability_flag = "character",
  include_in_trend = "logical",
  source_table     = "character",
  source_variables = "character",
  geo_vintage      = "character",
  notes            = "character"
)

TREND_NOTE_2020 <- paste(
  "The 2020 ACS 1-year standard release does not exist (pandemic non-response bias);",
  "1-year trends skip 2020."
)

#' Combine the variables behind each component (summing where a component has
#' several variables) for every group, geography and vintage.
build_components <- function(spec, raw) {
  vars <- indicator_variables(spec)
  raw |>
    dplyr::inner_join(vars, by = "variable", relationship = "many-to-many") |>
    dplyr::group_by(survey, year, geography, GEOID, NAME, group, table, component) |>
    # MOE first: summarise() evaluates in order, and moe_sum() needs the
    # individual estimates (it counts only the largest MOE among zeros).
    dplyr::summarise(
      moe = if (dplyr::n() == 1) moe[1] else if (anyNA(estimate)) NA_real_
            else tidycensus::moe_sum(moe, estimate),
      estimate = if (anyNA(estimate)) NA_real_ else sum(estimate),
      source_variables = paste(sort(variable), collapse = "+"),
      .groups = "drop"
    )
}

#' Build the published measures (counts and percentages) from components.
build_measures <- function(spec, comps) {
  key <- c("survey", "year", "geography", "GEOID", "NAME", "group", "table")
  purrr::map_dfr(spec$measures, function(m) {
    note <- m$note %||% NA_character_
    if (m$type %in% c("count", "value")) {
      comps |>
        dplyr::filter(component == m$component) |>
        dplyr::transmute(dplyr::across(dplyr::all_of(key)), estimate, moe,
                         base = NA_real_, source_variables,
                         measure = m$id, measure_label = m$label,
                         unit = if (m$type == "count") "count" else m$unit,
                         measure_note = note)
    } else {
      num <- dplyr::filter(comps, component == m$numerator)
      den <- dplyr::filter(comps, component == m$denominator)
      dplyr::inner_join(num, den, by = key, suffix = c("_num", "_den")) |>
        dplyr::transmute(
          dplyr::across(dplyr::all_of(key)),
          estimate = dplyr::if_else(!is.na(estimate_den) & estimate_den > 0,
                                    estimate_num / estimate_den * 100, NA_real_),
          moe = dplyr::if_else(
            !is.na(estimate),
            tidycensus::moe_prop(estimate_num, estimate_den, moe_num, moe_den) * 100,
            NA_real_),
          base = estimate_den,
          source_variables = paste0("(", source_variables_num, ") / (",
                                    source_variables_den, ")"),
          measure = m$id, measure_label = m$label, unit = "percent",
          measure_note = note
        )
    }
  })
}

#' Full long table for one indicator, in OUTPUT_SCHEMA order.
build_indicator_table <- function(spec, raw, pipeline_cfg) {
  comps <- build_components(spec, raw)
  meas <- build_measures(spec, comps)
  group_order <- purrr::map_chr(spec$groups, "group")
  measure_order <- purrr::map_chr(spec$measures, "id")

  out <- meas |>
    add_reliability(pipeline_cfg$reliability, pipeline_cfg$acs$moe_level) |>
    dplyr::mutate(
      indicator_id = spec$id,
      vital_condition = spec$vital_condition,
      geoid = GEOID,
      geo_name = NAME,
      year = as.integer(year),
      vintage_type = survey,
      acs_period = acs_period_label(survey, year),
      include_in_trend = include_in_trend(survey, year),
      source_table = table,
      geo_vintage = dplyr::if_else(geography == "tract", tract_boundary_vintage(year),
                                   "county (boundary unchanged)"),
      trend_note = dplyr::case_when(
        survey == "acs1" & year == 2020 ~ "Excluded from trends: 2020 ACS 1-year (pandemic non-response bias).",
        survey == "acs1" & year %in% c(2019, 2021) ~ TREND_NOTE_2020,
        TRUE ~ NA_character_
      ),
      notes = paste_notes(reliability_note, measure_note, trend_note)
    ) |>
    dplyr::arrange(geography, vintage_type, year, geoid,
                   match(group, group_order), match(measure, measure_order))

  out[, names(OUTPUT_SCHEMA)]
}

paste_notes <- function(...) {
  parts <- list(...)
  purrr::pmap_chr(parts, function(...) {
    x <- c(...)
    x <- x[!is.na(x) & nzchar(x)]
    if (length(x)) paste(x, collapse = " ") else NA_character_
  })
}
