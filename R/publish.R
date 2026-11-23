# Report and website (run only after the validation gate passes) -------------

git_commit_short <- function() {
  sha <- Sys.getenv("GITHUB_SHA")
  if (nzchar(sha)) return(substr(sha, 1, 7))
  out <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE),
                  error = function(e) character())
  if (length(out)) out[1] else "unknown"
}

build_info <- function(report, vintages, pums_vintages) {
  list(
    run_date = format(Sys.time(), "%Y-%m-%d %H:%M UTC", tz = "UTC"),
    commit = git_commit_short(),
    acs1 = latest_vintage(vintages, "acs1"),
    acs5 = acs_period_label("acs5", latest_vintage(vintages, "acs5")),
    pums = paste(sprintf("%s %s", ifelse(pums_vintages$survey == "acs5", "5-year", "1-year"),
                         acs_period_label(pums_vintages$survey, pums_vintages$year)), collapse = ", "),
    status = report$overall,
    pass = report$counts$pass, warn = report$counts$warn, fail = report$counts$fail
  )
}

status_badge <- function(status) {
  col <- switch(status, pass = "#2f855a", pass_with_warnings = "#b7791f", "#c53030")
  txt <- switch(status, pass = "passed", pass_with_warnings = "passed with warnings", "FAILED")
  sprintf('<span style="background:%s;color:#fff;border-radius:3px;padding:1px 6px;font-size:0.85em;">validation: %s</span>',
          col, txt)
}

#' Copy outputs into site/data and write the footer metadata.
prepare_site_inputs <- function(info, output_files, site_dir = "site") {
  data_dir <- file.path(site_dir, "data")
  unlink(data_dir, recursive = TRUE)
  dir.create(data_dir, recursive = TRUE)
  file.copy(unname(unlist(output_files)), data_dir, overwrite = TRUE)
  write_explorer_data(file.path(data_dir, "all_indicators.csv"), file.path(data_dir, "explorer_county.csv"))
  footer_left <- paste0(
    "Built by Kashish Chaudhari &middot; ",
    "<a href=\"https://www.linkedin.com/in/kashishchaudhari\">LinkedIn</a> &middot; ",
    "<a href=\"https://github.com/kashishchaudhari/vitalconditions-refresh\">Code on GitHub</a><br>",
    "Independent, unofficial prototype: not affiliated with or endorsed by Forsyth Futures. ",
    "Data: U.S. Census Bureau ACS (open public data)."
  )
  footer_right <- sprintf(
    "Run %s &middot; commit <code>%s</code> &middot; ACS 1-year %s, 5-year %s &middot; PUMS %s &middot; %s",
    info$run_date, info$commit, info$acs1, info$acs5, info$pums, status_badge(info$status))
  yaml::write_yaml(list(website = list(`page-footer` = list(left = footer_left, right = footer_right))),
                   file.path(site_dir, "_build_info.yml"))
  c(list.files(data_dir, full.names = TRUE), file.path(site_dir, "_build_info.yml"))
}

#' Compact county-level file for the in-browser Explore page (rows in the
#' registry's group order, numbers rounded for size).
write_explorer_data <- function(all_path, out_path) {
  read_output_csv(all_path) |>
    dplyr::filter(geography %in% c("county", "county_pums"), include_in_trend) |>
    dplyr::transmute(indicator_id, vital_condition, year, vintage_type, acs_period, group,
                     measure, measure_label, unit,
                     estimate = signif(estimate, 7), moe = signif(moe, 5), cv = round(cv, 1),
                     reliability_flag, source_table, notes) |>
    readr::write_csv(out_path, na = "")
  out_path
}

#' Run quarto with this R session's package library, so the child R process
#' finds the same (renv) packages.
with_project_libs <- function(code) {
  withr::with_envvar(
    c(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep), RENV_ACTIVATE_PROJECT = "FALSE"),
    code)
}

render_report <- function(qmd, ...) {
  with_project_libs(quarto::quarto_render(qmd, quiet = TRUE))
  sub("\\.qmd$", ".html", qmd)
}

render_site <- function(site_dir, ...) {
  with_project_libs(quarto::quarto_render(site_dir, quiet = TRUE))
  file.path(dirname(normalizePath(site_dir)), "_site", "index.html")
}
