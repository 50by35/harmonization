update_env <- local({
  environment <- new.env(parent = globalenv())
  sys.source(testthat::test_path("..", "..", "update.R"), envir = environment)
  environment
})
