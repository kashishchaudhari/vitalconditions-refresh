# Pipeline definition (targets). Run with targets::tar_make() or
# Rscript run_pipeline.R. Only the pieces whose inputs changed are re-run.

library(targets)
library(tarchetypes)

tar_option_set(
  packages = c("dplyr", "tidyr", "purrr", "readr", "tibble"),
  format = "rds",
  error = "stop"
)

tar_source("R")

# Every `status: active` indicator in the registry gets its own set of targets.
active_ids <- active_indicator_ids("config/indicators.yml")

per_indicator <- tar_map(
  values = tibble::tibble(indicator = active_ids),
  names = indicator,
  tar_target(spec, get_indicator_spec(registry, indicator)),
  tar_target(raw, pull_indicator_raw(spec, acs_vintages, pipeline_cfg)),
  tar_target(indicator_table, build_indicator_table(spec, raw, pipeline_cfg)),
  tar_target(csv, write_indicator_csv(indicator_table, pipeline_cfg), format = "file"),
  # Validation is written alongside each output, not at the end.
  tar_target(labels, pull_indicator_labels(spec, acs_vintages, pipeline_cfg)),
  tar_target(checks, run_indicator_checks(spec, csv, raw, labels, acs_vintages, county_tracts,
                                          pipeline_cfg, validation_cfg))
)

list(
  # Configuration files: editing any of them re-runs what depends on it.
  tar_target(registry_file, "config/indicators.yml", format = "file"),
  tar_target(pipeline_file, "config/pipeline.yml", format = "file"),
  tar_target(validation_file, "config/validation.yml", format = "file"),
  tar_target(legacy_file, "config/legacy_reference.csv", format = "file"),
  tar_target(registry, read_registry(registry_file)),
  tar_target(pipeline_cfg, read_config(pipeline_file)),
  tar_target(validation_cfg, read_config(validation_file)),

  # Which ACS vintages exist right now (checked on every run).
  tar_target(acs_vintages, detect_acs_vintages(pipeline_cfg), cue = tar_cue(mode = "always")),

  # Tract list for the newest 5-year vintage, counted from TIGER/Line.
  tar_target(county_tracts, get_county_tracts(latest_vintage(acs_vintages, "acs5"),
                                              pipeline_cfg$area)),

  per_indicator,

  # PUMS: Child Housing Cost Burden, with replicate-weight standard errors.
  tar_target(pums_vintages, detect_pums_vintages(pipeline_cfg), cue = tar_cue(mode = "always")),
  tar_target(pums_spec, get_indicator_spec(registry, "child_housing_cost_burden")),
  tar_target(pums_raw, pull_pums_all(pums_vintages, pipeline_cfg)),
  tar_target(pums_estimates, estimate_child_burden(pums_raw, pipeline_cfg, pums_spec)),
  tar_target(pums_table, build_child_burden_table(pums_estimates, pums_spec, pipeline_cfg)),
  tar_target(pums_csv, write_indicator_csv(pums_table, pipeline_cfg), format = "file"),
  tar_target(pums_published, pull_pums_benchmark_published(pums_vintages, pipeline_cfg)),
  tar_target(pums_checks, run_pums_checks(pums_spec, pums_csv, pums_raw, pums_vintages,
                                          pums_published, pipeline_cfg, validation_cfg)),

  tar_combine(acs_indicator_csvs, per_indicator[["csv"]],
              command = c(!!!.x)),
  tar_target(indicator_csvs, c(acs_indicator_csvs, csv_child_housing_cost_burden = pums_csv)),
  tar_target(combined_csvs, write_combined_csvs(indicator_csvs, pipeline_cfg), format = "file"),
  tar_combine(acs_indicator_checks, per_indicator[["checks"]],
              command = c(!!!.x)),
  tar_target(indicator_checks, c(acs_indicator_checks, pums_checks)),

  # Staleness: legacy vintage vs newest available, per indicator.
  tar_target(staleness_csv, write_staleness_report(registry, indicator_csvs, acs_vintages,
                                                   pipeline_cfg), format = "file"),
  tar_target(staleness_check, check_staleness(staleness_csv, registry,
                                              active_indicator_ids(registry_file, "any"),
                                              acs_vintages, pums_vintages)),

  # Module B: tract-level Childcare & Housing Affordability Gap.
  tar_target(facilities_file, pipeline_cfg$childcare$facilities_csv, format = "file"),
  tar_target(tract_year, latest_vintage(acs_vintages, "acs5")),
  tar_target(tract_geometry, get_county_tract_geometry(tract_year, pipeline_cfg$area)),
  tar_target(county_boundary, get_county_boundary(tract_year, pipeline_cfg$area)),
  tar_target(municipal_boundaries, get_municipal_boundaries(tract_year, pipeline_cfg$area,
                                                            county_boundary)),
  tar_target(affordability_gap, build_affordability_gap(
    tract_geometry, facilities_file, csv_young_children_and_working_parents,
    csv_median_family_income, csv_housing_cost_burden, tract_year,
    pipeline_cfg$childcare, pipeline_cfg)),
  tar_target(affordability_geo, build_affordability_geo(tract_geometry, affordability_gap,
                                                        pipeline_cfg$childcare)),
  tar_target(affordability_files, write_affordability_outputs(
    affordability_gap, affordability_geo, facilities_file, municipal_boundaries, pipeline_cfg),
    format = "file"),
  tar_target(affordability_checks, check_affordability(
    affordability_files, facilities_file, county_tracts$geoid, county_boundary, tract_geometry,
    csv_young_children_and_working_parents, csv_median_family_income, tract_year,
    pipeline_cfg$childcare, pipeline_cfg)),

  # Module C: validation report, then the blocking gate.
  tar_target(legacy_check, check_legacy(
    purrr::map_dfr(unname(indicator_csvs), read_output_csv),
    read_legacy_reference(legacy_file), validation_cfg)),
  tar_target(validation_report, write_validation_report(
    c(indicator_checks, list(staleness_check), affordability_checks),
    output_paths = c(as.list(indicator_csvs), as.list(combined_csvs)),
    legacy_check = legacy_check,
    validation_cfg = validation_cfg,
    pipeline_cfg = pipeline_cfg,
    vintages = acs_vintages)),
  tar_target(validation_gate_passed, validation_gate(validation_report)),

  # Publishing steps: these only run if the gate passed (it errors otherwise).
  tar_target(site_build_info, {
    validation_gate_passed
    build_info(validation_report, acs_vintages, pums_vintages)
  }, cue = tar_cue(mode = "always")),
  tar_target(site_inputs, prepare_site_inputs(
    site_build_info,
    c(unname(indicator_csvs), unname(combined_csvs), staleness_csv, affordability_files,
      validation_report$html, validation_report$json)), format = "file"),
  tar_target(site_sources, c(setdiff(list.files("site", pattern = "[.](qmd|yml)$", full.names = TRUE),
                                     "site/_build_info.yml"),
                             "DATA_EQUITY_AND_LIMITATIONS.md", "reports/refresh_summary.qmd"),
             format = "file"),
  tar_target(report_html, render_report("reports/refresh_summary.qmd", site_inputs, site_sources),
             format = "file"),
  tar_target(site_index, render_site("site", site_inputs, site_sources), format = "file")
)
