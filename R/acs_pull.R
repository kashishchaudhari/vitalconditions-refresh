# Pulling ACS tables with tidycensus, with a local disk cache --------------
#
# Each (survey, year, geography, variable set) is fetched once and saved under
# data/cache/acs/. Later runs read the saved copy, which keeps re-runs fast and
# polite to the Census API. Delete the cache folder to force a fresh download.
# The saved copy is exactly what tidycensus returned: it is the "source" that
# validation compares the outputs against.

census_key_available <- function() nzchar(Sys.getenv("CENSUS_API_KEY"))

acs_cache_path <- function(cache_dir, survey, year, geography, variables) {
  hash <- substr(digest::digest(sort(unique(variables))), 1, 12)
  file.path(cache_dir, sprintf("%s_%d_%s_%s.rds", survey, year, geography, hash))
}

pull_acs_cached <- function(variables, survey, year, geography, area, cache_dir) {
  path <- acs_cache_path(cache_dir, survey, year, geography, variables)
  if (file.exists(path)) return(readRDS(path))
  if (!census_key_available()) {
    stop("CENSUS_API_KEY is not set and ", basename(path), " is not cached. ",
         "Get a free key at https://api.census.gov/data/key_signup.html and set it ",
         "as an environment variable.", call. = FALSE)
  }
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  out <- tryCatch(
    suppressMessages(tidycensus::get_acs(
      geography = geography,
      variables = unique(variables),
      year = year,
      survey = survey,
      state = area$state_fips,
      county = area$county_fips,
      moe_level = 90,
      cache_table = TRUE
    )),
    error = function(e) {
      stop("Census API request failed for ", survey, " ", year, " ", geography, ": ",
           conditionMessage(e),
           "\nIf a table does not exist for early years, set `first_year` for this ",
           "survey in the indicator's registry entry.", call. = FALSE)
    }
  )
  out <- dplyr::select(out, GEOID, NAME, variable, estimate, moe)
  saveRDS(out, path)
  out
}

#' Which (survey, year, geography) pulls an indicator needs.
indicator_pull_plan <- function(spec, vintages, pipeline_cfg) {
  avail <- dplyr::filter(vintages, available, survey %in% spec$surveys)
  first <- spec$first_year %||% list()
  avail <- dplyr::filter(avail, year >= purrr::map_int(survey, ~ as.integer(first[[.x]] %||% 0L)))
  plan <- list()
  if ("county" %in% spec$geographies) {
    plan$county <- dplyr::mutate(avail, geography = "county")
  }
  if ("tract" %in% spec$geographies && "acs5" %in% spec$surveys) {
    plan$tract <- tibble::tibble(survey = "acs5", year = latest_vintage(vintages, "acs5"),
                                 geography = "tract")
  }
  dplyr::bind_rows(plan) |> dplyr::select(survey, year, geography)
}

#' Pull every vintage and geography an indicator needs.
#' Returns the raw tidycensus rows plus survey / year / geography columns.
pull_indicator_raw <- function(spec, vintages, pipeline_cfg) {
  vars <- unique(indicator_variables(spec)$variable)
  plan <- indicator_pull_plan(spec, vintages, pipeline_cfg)
  purrr::pmap_dfr(plan, function(survey, year, geography) {
    pull_acs_cached(vars, survey, year, geography, pipeline_cfg$area,
                    pipeline_cfg$paths$cache_dir) |>
      dplyr::mutate(survey = survey, year = as.integer(year), geography = geography,
                    .before = 1)
  })
}
