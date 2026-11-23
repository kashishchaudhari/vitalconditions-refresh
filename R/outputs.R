# Writing and reading the Tableau CSVs ----------------------------------------

schema_col_types <- function(schema = OUTPUT_SCHEMA) {
  spec <- purrr::map(schema, function(t) switch(t,
    character = readr::col_character(),
    integer   = readr::col_integer(),
    numeric   = readr::col_double(),
    logical   = readr::col_logical()))
  do.call(readr::cols, c(spec, list(.default = readr::col_character())))
}

#' Read an output CSV back from disk with the declared column types.
read_output_csv <- function(path) {
  readr::read_csv(path, col_types = schema_col_types(), na = "", progress = FALSE)
}

write_indicator_csv <- function(tbl, pipeline_cfg) {
  dir <- pipeline_cfg$paths$tableau_dir
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(dir, paste0(tbl$indicator_id[1], ".csv"))
  readr::write_csv(tbl, path, na = "")
  path
}

#' All indicators in one file, plus a county trend file without excluded rows.
write_combined_csvs <- function(indicator_paths, pipeline_cfg) {
  dir <- pipeline_cfg$paths$tableau_dir
  all <- purrr::map_dfr(unname(indicator_paths), read_output_csv)
  trends <- dplyr::filter(all, geography == "county", include_in_trend)
  p_all <- file.path(dir, "all_indicators.csv")
  p_trend <- file.path(dir, "trends_county.csv")
  readr::write_csv(all, p_all, na = "")
  readr::write_csv(trends, p_trend, na = "")
  c(all = p_all, trends = p_trend)
}
