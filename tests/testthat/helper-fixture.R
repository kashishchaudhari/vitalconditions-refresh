# Offline fixture: a small synthetic "Census pull" for the real registry
# entry, so tests run without an API key or network.

root <- normalizePath(testthat::test_path("..", ".."))
for (f in list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages(library(dplyr))

fixture_cfgs <- function() {
  pipeline_cfg <- read_config(file.path(root, "config", "pipeline.yml"))
  pipeline_cfg$paths$tableau_dir <- tempfile("tableau_")
  validation_cfg <- read_config(file.path(root, "config", "validation.yml"))
  list(pipeline = pipeline_cfg, validation = validation_cfg)
}

fixture_spec <- function() {
  read_registry(file.path(root, "config", "indicators.yml"))[["homeownership_by_race"]]
}

fixture_vintages <- function() {
  tibble::tribble(
    ~survey, ~year, ~available, ~note,
    "acs1", 2019L, TRUE,  NA,
    "acs1", 2020L, FALSE, "No standard 2020 ACS 1-year release.",
    "acs1", 2021L, TRUE,  NA,
    "acs5", 2023L, TRUE,  NA,
    "acs5", 2024L, TRUE,  NA
  )
}

fixture_tracts <- function() {
  tibble::tibble(geoid = c("37067000100", "37067000200", "37067000301"), tiger_year = 2024L)
}

#' Internally consistent fake ACS rows for every variable the spec needs.
fixture_raw <- function(spec, vintages = fixture_vintages(), tracts = fixture_tracts(), seed = 1) {
  set.seed(seed)
  plan <- dplyr::bind_rows(
    dplyr::filter(vintages, available) |> dplyr::mutate(geography = "county"),
    tibble::tibble(survey = "acs5", year = 2024L, geography = "tract")
  )
  alone <- c("A", "B", "C", "D", "E", "F", "G")
  purrr::pmap_dfr(plan[, c("survey", "year", "geography")], function(survey, year, geography) {
    geoids <- if (geography == "county") "37067" else tracts$geoid
    purrr::map_dfr(geoids, function(g) {
      scale <- if (geography == "county") 20000 else 300
      own <- round(runif(7, 0.05, 1) * scale); rent <- round(runif(7, 0.05, 1) * scale)
      vals <- list()
      for (i in seq_along(alone)) vals[[alone[i]]] <- c(own[i] + rent[i], own[i], rent[i])
      vals[["H"]] <- round(vals[["A"]] * 0.9); vals[["H"]][1] <- vals[["H"]][2] + vals[["H"]][3]
      vals[["I"]] <- c(sum(own[6:7]) + sum(rent[6:7]), sum(own[6:7]), sum(rent[6:7]))
      vals[[""]] <- c(sum(own) + sum(rent), sum(own), sum(rent))
      purrr::imap_dfr(vals, function(v, suffix) {
        tibble::tibble(
          survey = survey, year = as.integer(year), geography = geography,
          GEOID = g, NAME = paste("Fake", geography, g),
          variable = paste0("B25003", suffix, "_00", 1:3),
          estimate = v, moe = round(sqrt(v) * 3) + 5
        )
      })
    })
  })
}

#' A fake direct API fetch that answers from the fixture raw data.
fixture_fetch <- function(raw) {
  function(variables, survey, year, geography, area) {
    raw |>
      dplyr::filter(survey == !!survey, year == !!year, geography == !!geography,
                    variable %in% variables) |>
      dplyr::transmute(geoid = GEOID, variable, estimate_api = estimate, moe_api = moe)
  }
}

#' Build the fixture outputs and run every check; returns everything.
fixture_run <- function(corrupt = identity) {
  cfg <- fixture_cfgs()
  spec <- fixture_spec()
  raw <- fixture_raw(spec)
  tbl <- build_indicator_table(spec, raw, cfg$pipeline)
  path <- write_indicator_csv(tbl, cfg$pipeline)
  # Corrupt the written output file, as an analyst's slip or a bug might.
  readr::write_csv(corrupt(read_output_csv(path)), path, na = "")
  checks <- run_indicator_checks(spec, path, raw, fixture_vintages(), fixture_tracts(),
                                 cfg$pipeline, cfg$validation, fetch = fixture_fetch(raw))
  list(cfg = cfg, spec = spec, raw = raw, path = path, checks = checks)
}

check_by_suffix <- function(checks, suffix) {
  purrr::detect(checks, ~ endsWith(.x$check_id, suffix))
}

failed_units <- function(chk) sum(!chk$units$pass, na.rm = TRUE)
