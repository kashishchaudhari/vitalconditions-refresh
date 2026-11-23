# Validation report, summary and blocking gate (Module C) --------------------

VITAL_CONDITIONS <- c(
  "Natural World", "Basic Needs for Health & Safety", "Meaningful Work & Wealth",
  "Lifelong Learning", "Humane Housing", "Reliable Transportation",
  "Belonging & Civic Muscle"
)

action_for <- function(severity) {
  if (identical(severity, "fail")) pointblank::action_levels(stop_at = 1)
  else pointblank::action_levels(warn_at = 1)
}

#' A pointblank agent for one unit-level check result.
agent_from_check <- function(chk, validation_cfg) {
  sev <- validation_cfg$severity[[chk$category]] %||% "fail"
  pointblank::create_agent(
    tbl = chk$units,
    tbl_name = chk$check_id,
    label = chk$description,
    actions = action_for(sev)
  ) |>
    pointblank::col_vals_equal(
      columns = pass, value = TRUE, na_pass = TRUE,
      label = paste0("[", chk$category, "] ", chk$check_id)
    ) |>
    pointblank::interrogate(progress = FALSE)
}

#' Schema and value rules on an output table, as pointblank steps.
rules_agent <- function(tbl, tbl_name, validation_cfg, trend_file = FALSE) {
  schema <- do.call(pointblank::col_schema, as.list(OUTPUT_SCHEMA))
  a <- pointblank::create_agent(
    tbl = tbl, tbl_name = tbl_name,
    label = paste0("Rules and schema: ", tbl_name),
    actions = action_for(validation_cfg$severity$rules)
  ) |>
    pointblank::col_schema_match(schema, complete = TRUE, in_order = TRUE,
                                 label = "[rules] columns and types match the output schema") |>
    pointblank::rows_distinct(columns = dplyr::all_of(OUTPUT_KEY),
                              label = "[rules] one row per indicator x place x year x survey x group x measure") |>
    pointblank::col_vals_between(columns = estimate, left = 0, right = 100, na_pass = TRUE,
                                 preconditions = function(x) dplyr::filter(x, unit == "percent"),
                                 label = "[rules] percentages are between 0 and 100") |>
    pointblank::col_vals_gte(columns = c(estimate, moe, se), value = 0, na_pass = TRUE,
                             label = "[rules] estimates, MOEs and SEs are not negative") |>
    pointblank::col_vals_not_null(columns = c(reliability_flag, source_table, source_variables,
                                              year, vintage_type, acs_period, include_in_trend,
                                              vital_condition),
                                  label = "[rules] every row has a reliability flag, source table, vintage and trend flag") |>
    pointblank::col_vals_in_set(columns = reliability_flag, set = RELIABILITY_LEVELS,
                                label = "[rules] reliability flag is reliable / use_with_caution / suppress") |>
    pointblank::col_vals_in_set(columns = vital_condition, set = VITAL_CONDITIONS,
                                label = "[rules] vital condition is one of the seven") |>
    pointblank::col_vals_in_set(columns = vintage_type, set = c("acs1", "acs5"),
                                label = "[rules] vintage type is acs1 or acs5") |>
    pointblank::col_vals_expr(expr = ~ !(vintage_type == "acs1" & year == 2020 & include_in_trend),
                              label = "[rules] 2020 ACS 1-year rows are never marked for trends")
  if (trend_file) {
    a <- a |>
      pointblank::col_vals_expr(expr = ~ !(vintage_type == "acs1" & year == 2020),
                                label = "[rules] no 2020 ACS 1-year value appears in the trend file") |>
      pointblank::col_vals_equal(columns = include_in_trend, value = TRUE,
                                 label = "[rules] trend file holds only trend-eligible rows")
  }
  pointblank::interrogate(a, progress = FALSE)
}

#' One summary row per validation step.
summarise_agent <- function(agent, check_id, category, indicator_id, severity, note = NA_character_,
                            n_not_evaluated = NA_integer_) {
  vs <- agent$validation_set
  cols <- purrr::map_chr(vs$column, ~ paste(stats::na.omit(unlist(.x)), collapse = ", "))
  tibble::tibble(
    check_id = check_id,
    category = category,
    indicator_id = indicator_id,
    step = ifelse(nzchar(cols) & !grepl("^\\[(completeness|source_match|reconciliation|derived|consistency|legacy)\\]", vs$label),
                  paste0(vs$label, " [", cols, "]"), vs$label),
    n_units = as.integer(vs$n),
    n_passed = as.integer(vs$n_passed),
    n_failed = as.integer(vs$n_failed),
    n_not_evaluated = n_not_evaluated,
    status = dplyr::case_when(
      vs$eval_error ~ "fail",
      !is.na(vs$n_failed) & vs$n_failed > 0 & severity == "fail" ~ "fail",
      !is.na(vs$n_failed) & vs$n_failed > 0 ~ "warn",
      !is.na(note) ~ "warn",       # e.g. nothing to compare against yet
      TRUE ~ "pass"
    ),
    note = note
  )
}

#' Build every agent, write the HTML report and JSON summary, return the summary.
write_validation_report <- function(checks, output_paths, legacy_check, validation_cfg,
                                    pipeline_cfg, vintages) {
  dir <- pipeline_cfg$paths$validation_dir
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  unit_checks <- c(checks, list(legacy_check))
  unit_agents <- purrr::map(unit_checks, agent_from_check, validation_cfg = validation_cfg)
  unit_summary <- purrr::map2_dfr(unit_checks, unit_agents, function(chk, ag) {
    summarise_agent(ag, chk$check_id, chk$category, chk$indicator_id,
                    validation_cfg$severity[[chk$category]] %||% "fail",
                    note = chk$note, n_not_evaluated = sum(is.na(chk$units$pass)))
  })

  output_paths <- unname(unlist(output_paths))
  rule_agents <- purrr::map(output_paths, function(p) {
    rules_agent(read_output_csv(p), basename(p), validation_cfg,
                trend_file = grepl("^trends", basename(p)))
  })
  rule_summary <- purrr::map2_dfr(rule_agents, output_paths, function(ag, p) {
    summarise_agent(ag, paste0("rules__", basename(p)), "rules",
                    sub("\\.csv$", "", basename(p)),
                    validation_cfg$severity$rules)
  })

  summary <- dplyr::bind_rows(unit_summary, rule_summary)
  counts <- as.list(table(factor(summary$status, levels = c("pass", "warn", "fail"))))
  overall <- if (counts$fail > 0) "fail" else if (counts$warn > 0) "pass_with_warnings" else "pass"

  # HTML report: every agent in one multiagent report.
  ma <- do.call(pointblank::create_multiagent, c(unit_agents, rule_agents))
  html <- file.path(dir, "validation_report.html")
  pointblank::export_report(ma, filename = html, quiet = TRUE)

  json <- file.path(dir, "validation_summary.json")
  jsonlite::write_json(
    list(
      run_time_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      overall_status = overall,
      counts = counts,
      acs_vintages = list(
        acs1_latest = latest_vintage(vintages, "acs1"),
        acs5_latest = latest_vintage(vintages, "acs5")
      ),
      checks = summary
    ),
    json, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null"
  )
  list(summary = summary, counts = counts, overall = overall, html = html, json = json)
}

#' Stop the pipeline if any check failed. Nothing downstream (publishing)
#' runs after an error here.
validation_gate <- function(report) {
  fails <- dplyr::filter(report$summary, status == "fail")
  if (nrow(fails)) {
    stop("Validation FAILED (", nrow(fails), " step(s)). Publishing is blocked.\n",
         paste0("  - ", fails$check_id, ": ", fails$step, " (", fails$n_failed, " failing)",
                collapse = "\n"),
         "\nSee ", report$html, call. = FALSE)
  }
  message("Validation passed: ", report$counts$pass, " pass, ", report$counts$warn,
          " warn, 0 fail.")
  TRUE
}
