# Independent Census API client (validation only) -----------------------------
#
# Validation re-pulls a random sample of estimates through this code, which
# calls the Census API directly with curl and jsonlite. It shares no code with
# the main pull (tidycensus), so a bug in one path shows up as a mismatch.
#
# Conventions, matching how the main pull stores values:
#   - JSON null            -> NA (estimate not published)
#   - negative annotation  -> NA (the Census Bureau's special codes such as
#     codes like -555555555, -666666666, -999999999 mean "no value")

direct_acs_fetch <- function(variables, survey, year, geography, area,
                             key = Sys.getenv("CENSUS_API_KEY")) {
  if (!nzchar(key)) stop("CENSUS_API_KEY is needed for the reconciliation re-pull.", call. = FALSE)
  chunks <- split(unique(variables), ceiling(seq_along(unique(variables)) / 24))
  geo <- switch(geography,
    county = sprintf("for=county:%s&in=state:%s", area$county_fips, area$state_fips),
    tract  = sprintf("for=tract:*&in=state:%s%%20county:%s", area$state_fips, area$county_fips),
    stop("Unsupported geography: ", geography))
  purrr::map_dfr(chunks, function(v) {
    get <- paste(c(paste0(v, "E"), paste0(v, "M")), collapse = ",")
    url <- sprintf("https://api.census.gov/data/%d/acs/%s?get=%s&%s&key=%s",
                   year, survey, get, geo, key)
    res <- curl::curl_fetch_memory(url)
    if (res$status_code != 200) {
      stop("Direct Census API request failed (HTTP ", res$status_code, ") for ",
           survey, " ", year, " ", geography, ".", call. = FALSE)
    }
    m <- jsonlite::fromJSON(rawToChar(res$content), simplifyVector = TRUE)
    df <- as.data.frame(m[-1, , drop = FALSE], stringsAsFactors = FALSE)
    names(df) <- m[1, ]
    geoid <- if (geography == "county") paste0(df$state, df$county)
             else paste0(df$state, df$county, df$tract)
    purrr::map_dfr(v, function(var) {
      tibble::tibble(
        geoid = geoid,
        variable = var,
        estimate_api = clean_census_value(df[[paste0(var, "E")]]),
        moe_api = clean_census_value(df[[paste0(var, "M")]])
      )
    })
  })
}

clean_census_value <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x[!is.na(x) & x < -100000000] <- NA_real_
  x
}
