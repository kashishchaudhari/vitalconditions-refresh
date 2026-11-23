# Run with: Rscript tests/testthat.R   (no Census API key or network needed)
testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
