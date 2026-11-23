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
  tar_target(checks, run_indicator_checks(spec, csv, raw, acs_vintages, county_tracts,
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

  tar_combine(indicator_csvs, per_indicator[["csv"]],
              command = c(!!!.x)),
  tar_target(combined_csvs, write_combined_csvs(indicator_csvs, pipeline_cfg), format = "file"),
  tar_combine(indicator_checks, per_indicator[["checks"]],
              command = c(!!!.x)),

  # Module C: validation report, then the blocking gate.
  tar_target(legacy_check, check_legacy(
    purrr::map_dfr(unname(indicator_csvs), read_output_csv),
    read_legacy_reference(legacy_file), validation_cfg)),
  tar_target(validation_report, write_validation_report(
    indicator_checks,
    output_paths = c(as.list(indicator_csvs), as.list(combined_csvs)),
    legacy_check = legacy_check,
    validation_cfg = validation_cfg,
    pipeline_cfg = pipeline_cfg,
    vintages = acs_vintages)),
  tar_target(validation_gate_passed, validation_gate(validation_report))
)
