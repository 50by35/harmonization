script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_arg) == 0L) {
  stop("The test runner must be executed with Rscript.", call. = FALSE)
}

script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]))
testthat::test_dir(
  file.path(dirname(script_path), "testthat"),
  reporter = "summary"
)
