# Census tract boundaries (TIGER/Line via tigris) ------------------------------

#' Forsyth County tracts for a given year, from TIGER/Line cartographic
#' boundary files. Used to count tracts for validation (never hard-coded) and,
#' later, for maps.
get_county_tracts <- function(year, area) {
  options(tigris_use_cache = TRUE)
  tr <- tryCatch(
    suppressMessages(tigris::tracts(state = area$state_fips, county = area$county_fips,
                                    year = year, cb = TRUE, progress_bar = FALSE)),
    error = function(e) {
      message("Cartographic tract file for ", year, " unavailable; using full TIGER/Line file.")
      suppressMessages(tigris::tracts(state = area$state_fips, county = area$county_fips,
                                      year = year, cb = FALSE, progress_bar = FALSE))
    }
  )
  sf::st_drop_geometry(tr) |>
    dplyr::transmute(geoid = GEOID, tiger_year = as.integer(year)) |>
    dplyr::arrange(geoid)
}
