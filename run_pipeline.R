# Refresh everything: pull data, build outputs, validate.
# Usage (from the project folder):  Rscript run_pipeline.R
#
# Needs the CENSUS_API_KEY environment variable unless every pull is already
# cached in data/cache/. The key is read by tidycensus from the environment
# and is never printed or written to disk by this project.

if (!nzchar(Sys.getenv("CENSUS_API_KEY"))) {
  message("Note: CENSUS_API_KEY is not set. Cached data will be used where available; ",
          "new pulls and the validation re-pull will fail.")
}

targets::tar_make()

summary_path <- "outputs/validation/validation_summary.json"
if (file.exists(summary_path)) {
  s <- jsonlite::read_json(summary_path)
  message(sprintf("Validation: %s (pass %d, warn %d, fail %d)",
                  s$overall_status, s$counts$pass, s$counts$warn, s$counts$fail))
}
