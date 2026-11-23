# Detecting which ACS vintages exist ---------------------------------------
#
# The Census API publishes a metadata document per dataset, for example
# https://api.census.gov/data/2025/acs/acs1.json. It answers 200 when the
# vintage exists and 404 when it does not. We ask for every year from the
# configured start year up to the current year, so new releases are picked up
# on the next run without editing code.

census_dataset_status <- function(year, survey) {
  url <- sprintf("https://api.census.gov/data/%d/acs/%s.json", year, survey)
  res <- tryCatch(curl::curl_fetch_memory(url), error = function(e) e)
  if (inherits(res, "error")) {
    stop("Could not reach the Census API (", conditionMessage(res), ").", call. = FALSE)
  }
  res$status_code
}

detect_acs_vintages <- function(pipeline_cfg, through_year = as.integer(format(Sys.Date(), "%Y"))) {
  start <- pipeline_cfg$acs$start_year
  grid <- tidyr::expand_grid(survey = pipeline_cfg$acs$surveys, year = start:through_year)
  grid$status <- purrr::map2_int(grid$year, grid$survey, census_dataset_status)
  bad <- grid$status != 200 & grid$status != 404
  if (any(bad)) {
    stop("Unexpected Census API status when checking vintages: ",
         paste(sprintf("%s %d -> %d", grid$survey[bad], grid$year[bad], grid$status[bad]),
               collapse = "; "), call. = FALSE)
  }
  grid |>
    dplyr::mutate(
      available = status == 200,
      note = dplyr::case_when(
        survey == "acs1" & year == 2020 & !available ~
          "No standard 2020 ACS 1-year release (pandemic data-collection problems); only experimental estimates exist.",
        !available ~ "Not released yet.",
        TRUE ~ NA_character_
      )
    ) |>
    dplyr::select(survey, year, available, note)
}

latest_vintage <- function(vintages, survey) {
  max(vintages$year[vintages$survey == survey & vintages$available])
}

#' Label like "2025" (1-year) or "2020-2024" (5-year).
acs_period_label <- function(survey, year) {
  ifelse(survey == "acs5", paste0(year - 4, "-", year), as.character(year))
}

#' TRUE when a row may be used in a trend comparison.
#' 2020 ACS 1-year estimates are always excluded (pandemic non-response bias).
include_in_trend <- function(survey, year) {
  !(survey == "acs1" & year == 2020)
}

#' Which tract boundaries a 5-year tract estimate uses.
tract_boundary_vintage <- function(year) {
  ifelse(year >= 2020, "2020 census tracts", "2010 census tracts")
}
