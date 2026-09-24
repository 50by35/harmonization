test_that("catalog selection keeps every file in the harmonized collection", {
  catalog <- data.table::data.table(
    ServerAlias = c("FDP", "FDP", "FDP", "FDP", "FDP", "GMD"),
    Country = rep("COL", 6L),
    Year = rep(2023L, 6L),
    Survey = rep("GEIH", 6L),
    FilePath = c(
      "COL/COL_2023_GEIH/COL_2023_GEIH_V01_M_V01_A_FDP/Data/Harmonized/data.dta",
      "COL/COL_2023_GEIH/COL_2023_GEIH_V01_M_V01_A_FDP/Programs/harmonize.do",
      "COL/COL_2023_GEIH/COL_2023_GEIH_V01_M_V01_A_FDP/Programs/harmonize.R",
      "COL/COL_2023_GEIH/COL_2023_GEIH_V01_M_V01_A_FDP/README.md",
      "COL/COL_2023_GEIH/COL_2023_GEIH_V01_M/Data/Stata/household.dta",
      "COL/COL_2023_GEIH/COL_2023_GEIH_V01_M_V01_A_OTHER/Programs/other.py"
    ),
    FileName = c(
      "data.dta",
      "harmonize.do",
      "harmonize.R",
      "README.md",
      "household.dta",
      "other.py"
    )
  )

  selected <- update_env$select_sync_files(catalog, "FDP")

  expect_identical(
    selected$FileName,
    c("data.dta", "harmonize.do", "harmonize.R", "README.md")
  )
})

test_that("harmonized collection paths are identified by their directory", {
  expect_true(update_env$is_harmonized_collection_path(
    "COL/COL_2023_GEIH/COL_2023_GEIH_V01_M_V01_A_FDP/Programs/harmonize.R"
  ))
  expect_false(update_env$is_harmonized_collection_path(
    "COL/COL_2023_GEIH/COL_2023_GEIH_V01_M/Data/Stata/household.dta"
  ))
  expect_false(update_env$is_harmonized_collection_path(
    "COL/COL_2023_GEIH/COL_2023_GEIH_V01_M_V01_A_OTHER/Programs/other.py"
  ))
})

test_that("only program paths are mirrored into the repository", {
  expect_true(update_env$is_program_path(
    "COL/survey_V01_M_V01_A_FDP/Programs/harmonize.do"
  ))
  expect_false(update_env$is_program_path(
    "COL/survey_V01_M_V01_A_FDP/Data/Harmonized/data.dta"
  ))
  expect_true(update_env$is_program_file(
    "COL/survey_V01_M_V01_A_FDP/Programs/harmonize.py"
  ))
  expect_false(update_env$is_program_file(
    "COL/survey_V01_M_V01_A_FDP/Programs/run"
  ))
  expect_false(update_env$is_program_file(
    "COL/survey_V01_M_V01_A_FDP/Programs/metadata.json"
  ))
  expect_true(update_env$is_program_file(
    "COL/survey_V01_M_V01_A_FDP/Programs/config.sql"
  ))
  expect_false(update_env$is_program_file(
    "COL/survey_V01_M_V01_A_FDP/Programs/reference.dta"
  ))
  expect_false(update_env$is_program_file(
    "COL/survey_V01_M_V01_A_FDP/Data/Harmonized/data.dta"
  ))
})

test_that("repository paths preserve catalog structure for programs only", {
  root <- tempfile("fdp-repository-")
  dir.create(root)
  catalog <- data.table::data.table(
    FilePath = c(
      "COL/survey_V01_M_V01_A_FDP/Programs/harmonize.do",
      "COL/survey_V01_M_V01_A_FDP/Data/Harmonized/data.dta"
    ),
    RelativePath = c(
      "COL/survey_V01_M_V01_A_FDP/Programs/harmonize.do",
      "COL/survey_V01_M_V01_A_FDP/Data/Harmonized/data.dta"
    )
  )

  validated <- update_env$validate_repository_paths(catalog, root)

  expect_identical(validated$IsProgram, c(TRUE, FALSE))
  expect_identical(
    validated$RepoRelativePath[[1L]],
    "COL/survey_V01_M_V01_A_FDP/Programs/harmonize.do"
  )
  expect_true(is.na(validated$RepoPath[[2L]]))
})

test_that("destination roots cannot contain one another", {
  repository <- tempfile("fdp-repository-")
  dir.create(repository)
  config <- list(
    local_root = fs::path(repository, "mirror"),
    repository_root = repository
  )

  expect_error(
    update_env$validate_destination_roots(config),
    "outside the repository tree"
  )
})

test_that("a current full mirror can repair a repository program copy", {
  root <- tempfile("fdp-copy-")
  repository <- tempfile("fdp-repository-")
  dir.create(root)
  dir.create(repository)
  source <- fs::path(root, "program.do")
  destination <- fs::path(repository, "program.do")
  writeBin(charToRaw("display hello"), source)
  row <- data.table::data.table(
    IsProgram = TRUE,
    LocalPath = source,
    RepoPath = destination
  )
  sha256 <- update_env$sha256_file(source)

  expect_false(update_env$same_repository_file(row, sha256))
  update_env$atomic_copy(source, destination, repository)
  expect_true(update_env$same_repository_file(row, sha256))
})

test_that("destination root checks resolve existing symlink ancestors", {
  skip_on_os("windows")
  root <- tempfile("fdp-root-")
  repository <- fs::path(root, "repository")
  mirror <- fs::path(root, "mirror")
  dir.create(repository, recursive = TRUE)
  dir.create(mirror)
  alias <- fs::path(root, "repository-alias")
  file.symlink(repository, alias)
  config <- list(local_root = fs::path(alias, "mirror"), repository_root = repository)

  expect_error(
    update_env$validate_destination_roots(config),
    "outside the repository tree"
  )
})

test_that("catalog paths are restricted to relative safe paths", {
  expect_identical(
    update_env$validate_relative_path("COL/data/file.dta"),
    "COL/data/file.dta"
  )
  expect_identical(
    update_env$validate_relative_path("COL\\data\\file.dta"),
    "COL/data/file.dta"
  )
  expect_error(update_env$validate_relative_path("/tmp/file.dta"), "absolute")
  expect_error(update_env$validate_relative_path("../file.dta"), "unsafe")
  expect_error(update_env$validate_relative_path("COL//file.dta"), "unsafe")
})

test_that("local path validation keeps files below the mirror root", {
  root <- tempfile("fdp-root-")
  dir.create(root)
  catalog <- data.table::data.table(
    FilePath = "COL/data/file.dta"
  )

  validated <- update_env$validate_catalog_paths(catalog, root)

  expect_true(startsWith(
    fs::path_abs(validated$LocalPath),
    paste0(fs::path_abs(root), "/")
  ))
})

test_that("manifest hashes identify an unchanged local file", {
  root <- tempfile("fdp-file-")
  dir.create(root)
  local_path <- fs::path(root, "file.do")
  writeBin(charToRaw("display hello"), local_path)

  catalog_row <- data.table::data.table(
    LocalPath = local_path,
    FileSize = "13 B",
    Timestamp = "Jul 14 2026 01:12 PM"
  )
  manifest_row <- data.table::data.table(
    Bytes = as.numeric(fs::file_info(local_path)$size),
    Sha256 = update_env$sha256_file(local_path),
    ServerFileSize = catalog_row$FileSize,
    ServerTimestamp = catalog_row$Timestamp
  )

  expect_true(update_env$same_local_file(catalog_row, manifest_row))

  writeBin(charToRaw("changed"), local_path)
  expect_false(update_env$same_local_file(catalog_row, manifest_row))
})

test_that("file sizes are normalized to plain numeric values", {
  root <- tempfile("fdp-bytes-")
  dir.create(root)
  path <- fs::path(root, "file.do")
  writeBin(charToRaw("display hello"), path)

  expect_type(update_env$plain_bytes(path), "double")
  expect_identical(update_env$plain_bytes(path), as.numeric(fs::file_info(path)$size))
})

test_that("manifest builder records successfully synchronized files", {
  catalog <- data.table::data.table(
    RelativePath = "COL/data/file.dta",
    FileName = "file.dta",
    LocalPath = "/tmp/file.dta",
    Country = "COL",
    Year = 2023L,
    Survey = "GEIH",
    Checksum = "d41d8cd98f00b204e9800998ecf8427e",
    FileSize = "3 B",
    Timestamp = "Jul 14 2026 01:12 PM"
  )
  results <- data.table::data.table(
    RelativePath = "COL/data/file.dta",
    status = "unchanged",
    bytes = 3,
    sha256 = paste(rep("a", 64), collapse = "")
  )

  manifest <- update_env$build_manifest(
    catalog,
    results,
    update_env$empty_manifest()
  )

  expect_identical(manifest$RelativePath, "COL/data/file.dta")
  expect_identical(manifest$Sha256, paste(rep("a", 64), collapse = ""))
  expect_identical(manifest$Bytes, 3)
})

test_that("catalog parser reads the API catalog and adds file names", {
  body <- paste(
    "ServerAlias,Country,Year,Survey,FilePath,Ext,FileSize,Timestamp,Checksum,OnlySol",
    "FDP,COL,2023,GEIH,COL/data/file.dta,dta,3 B,Jan 01 2026 12:00 PM,checksum,",
    sep = "\n"
  )
  response <- httr2::response(
    headers = list(`Content-Type` = "text/csv"),
    body = charToRaw(body)
  )

  catalog <- update_env$parse_catalog(response)

  expect_identical(catalog$FileName, "file.dta")
  expect_identical(catalog$Country, "COL")
})

test_that("API file errors are recognized even when returned with HTTP 200", {
  response <- httr2::response(
    headers = list(
      `Content-Type` = "csv",
      filename = "ECAFileinfo.csv"
    ),
    body = charToRaw(paste(
      "FileName,ErrorCode,ErrorDetail",
      ",404,File not found",
      sep = "\n"
    ))
  )

  expect_true(update_env$is_api_error_response(response))
  expect_error(
    update_env$api_response_error(
      response,
      "FileInformationInternal/GetFileInfo",
      list(Server = "FDP", filename = "missing.do")
    ),
    "File not found|ECAFileinfo"
  )
})

test_that("HTTP error messages include status and omit tokens", {
  response <- httr2::response(
    status_code = 401,
    headers = list(`Content-Type` = "text/plain"),
    body = charToRaw("invalid token")
  )

  error <- tryCatch(
    update_env$response_error(
      response,
      "Token/profile",
      list(Server = "FDP", token = "secret-token")
    ),
    error = identity
  )

  expect_match(conditionMessage(error), "401")
  expect_match(conditionMessage(error), "invalid token")
  expect_false(grepl("secret-token", conditionMessage(error), fixed = TRUE))
})

test_that("environment integers reject fractional and zero values", {
  withr::local_envvar(FDP_RETRIES = "3.5")
  expect_error(update_env$env_integer("FDP_RETRIES", 3L), "positive integer")

  withr::local_envvar(FDP_RETRIES = "0")
  expect_error(update_env$env_integer("FDP_RETRIES", 3L), "positive integer")
})

test_that("API requests retry transient server responses", {
  withr::local_envvar(DLW_TOKEN = "test-token")
  config <- list(
    base_url = "https://example.com/api",
    api_version = "v1",
    timeout_seconds = 30L,
    retries = 4L,
    user_agent = "test-agent"
  )

  request <- update_env$api_request(
    config,
    "ServerCatalog",
    Server = "FDP"
  )

  expect_identical(request$policies$retry_max_tries, 4L)
  expect_true(is.function(request$policies$retry_is_transient))
  expect_true(request$policies$retry_is_transient(httr2::response(500)))
  expect_true(request$policies$retry_is_transient(httr2::response(503)))
  expect_false(request$policies$retry_is_transient(httr2::response(404)))
})

test_that("case-insensitive catalog path collisions are rejected", {
  root <- tempfile("fdp-collision-")
  dir.create(root)
  catalog <- data.table::data.table(
    FilePath = c("COL/Data/file.dta", "COL/data/FILE.dta")
  )

  expect_error(
    update_env$validate_catalog_paths(catalog, root),
    "collide on case-insensitive filesystems"
  )
})

test_that("manifest round trips with stable character metadata", {
  root <- tempfile("fdp-manifest-")
  dir.create(root)
  path <- fs::path(root, "manifest.csv")
  manifest <- data.table::data.table(
    RelativePath = "COL/data/file.dta",
    FileName = "file.dta",
    Extension = "dta",
    Country = "COL",
    Year = 2023L,
    Survey = "GEIH",
    Bytes = 3,
    Sha256 = paste(rep("a", 64), collapse = ""),
    ServerChecksum = "checksum",
    ServerFileSize = "3 B",
    ServerTimestamp = "Jan 01 2026 12:00 PM",
    SyncedAt = "2026-01-01T00:00:00Z"
  )

  update_env$write_manifest(manifest, path)
  read_back <- update_env$read_manifest(path)

  expect_type(read_back$SyncedAt, "character")
  expect_identical(read_back$Bytes, 3)
  expect_identical(read_back$RelativePath, manifest$RelativePath)
})
