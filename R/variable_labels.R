# Variable-label consistency ---------------------------------------------------
#
# The Census Bureau sometimes renumbers a table's variables between years.
# For example, S1903 moved median income from column C02 to C03 in 2017, and
# S2301_C02_001 changed from "in labor force" (a count) to "labor force
# participation rate" (a percent) in 2015. A pipeline that pulls the same
# variable ID every year would silently mix different things.
#
# So, for every variable an indicator uses, we download its label for every
# year pulled (cached under data/cache/meta/) and require the labels to
# agree. "Agree" means the words of one label are contained in the other, after
# ignoring punctuation, the word "estimate" and dollar-year references, because
# Census sometimes adds context words without changing the meaning.

fetch_group_labels <- function(table, survey, year, cache_dir) {
  dir <- file.path(dirname(cache_dir), "meta")
  path <- file.path(dir, sprintf("%s_%d_%s.rds", survey, year, table))
  if (file.exists(path)) return(readRDS(path))
  sub <- if (startsWith(table, "S")) "/subject" else ""
  url <- sprintf("https://api.census.gov/data/%d/acs/%s%s/groups/%s.json", year, survey, sub, table)
  res <- curl::curl_fetch_memory(url)
  if (res$status_code == 404) {
    out <- tibble::tibble(variable = character(), label = character())
  } else if (res$status_code != 200) {
    stop("Could not download labels for ", table, " (", survey, " ", year, "): HTTP ",
         res$status_code, call. = FALSE)
  } else {
    v <- jsonlite::fromJSON(rawToChar(res$content), simplifyVector = FALSE)$variables
    est <- names(v)[grepl("E$", names(v))]
    out <- tibble::tibble(variable = sub("E$", "", est),
                          label = purrr::map_chr(v[est], ~ .x$label %||% NA_character_))
  }
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(out, path)
  out
}

pull_indicator_labels <- function(spec, vintages, pipeline_cfg) {
  vars <- indicator_variables(spec) |> dplyr::distinct(table, variable)
  plan <- indicator_pull_plan(spec, vintages, pipeline_cfg) |> dplyr::distinct(survey, year)
  tidyr::expand_grid(plan, table = unique(vars$table)) |>
    purrr::pmap_dfr(function(survey, year, table) {
      fetch_group_labels(table, survey, year, pipeline_cfg$paths$cache_dir) |>
        dplyr::filter(variable %in% vars$variable[vars$table == table]) |>
        dplyr::mutate(survey = survey, year = as.integer(year), table = table, .before = 1)
    })
}

label_tokens <- function(label) {
  x <- tolower(label)
  x <- gsub("[0-9]{4} inflation-adjusted", "year inflation-adjusted", x)
  x <- gsub("[^a-z0-9.%]+", " ", x)
  w <- strsplit(trimws(x), " +")[[1]]
  unique(setdiff(w, c("estimate", "")))
}

check_label_consistency <- function(spec, labels, vintages, pipeline_cfg) {
  vars <- indicator_variables(spec) |> dplyr::distinct(table, variable)
  plan <- indicator_pull_plan(spec, vintages, pipeline_cfg) |> dplyr::distinct(survey, year)
  expected <- tidyr::expand_grid(plan, vars)
  latest <- labels |>
    dplyr::group_by(variable) |>
    dplyr::slice_max(year, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(variable, reference_label = label)
  units <- expected |>
    dplyr::left_join(labels, by = c("survey", "year", "table", "variable")) |>
    dplyr::left_join(latest, by = "variable") |>
    dplyr::mutate(pass = purrr::map2_lgl(label, reference_label, function(a, b) {
      if (is.na(a) || is.na(b)) return(FALSE)
      ta <- label_tokens(a); tb <- label_tokens(b)
      all(ta %in% tb) || all(tb %in% ta)
    }))
  check_result(
    paste0(spec$id, "__variable_labels"), "source_match", spec$id,
    sprintf("%s: each of the %d variables means the same thing in every year pulled (its Census label matches the newest year's label), so renumbered tables cannot slip in.",
            spec$name, nrow(vars)),
    units)
}
