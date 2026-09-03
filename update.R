#!/usr/bin/env Rscript

# Synchronize the harmonized FDP collection exposed by Datalibweb.
#
# The API returns raw and harmonized artifacts. This script selects the
# harmonized collection from its catalog path and downloads response bytes
# directly instead of using dlw_get_data(), which converts .dta files into pins.

required_packages <- c("data.table", "digest", "fs", "httr2")
missing_packages <- required_packages[!vapply(
  required_packages,
  requireNamespace,
  logical(1),
  quietly = TRUE
)]

if (length(missing_packages) > 0) {
  stop(
    "Install the required R packages: ",
    paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

env_flag <- function(name, default = FALSE) {
  value <- Sys.getenv(name, unset = "")
  if (!nzchar(value)) {
    return(default)
  }

  value <- tolower(trimws(value))
  if (value %in% c("1", "true", "t", "yes", "y")) {
    TRUE
  } else if (value %in% c("0", "false", "f", "no", "n")) {
    FALSE
  } else {
    stop(
      name,
      " must be one of: 1, 0, true, false, yes, or no.",
      call. = FALSE
    )
  }
}

env_integer <- function(name, default) {
  value <- trimws(Sys.getenv(name, unset = ""))
  if (!nzchar(value)) {
    return(default)
  }

  if (!grepl("^[0-9]+$", value)) {
    stop(name, " must be a positive integer.", call. = FALSE)
  }
  parsed <- suppressWarnings(as.integer(value))
  if (is.na(parsed) || parsed < 1L) {
    stop(name, " must be a positive integer.", call. = FALSE)
  }
  parsed
}

scalar_text <- function(value, default = "") {
  if (length(value) == 0L || is.na(value[[1L]]) || !nzchar(as.character(value[[1L]]))) {
    default
  } else {
    as.character(value[[1L]])
  }
}

sync_config <- function() {
  list(
    base_url = Sys.getenv(
      "DLW_API_URL",
      unset = "https://datalibwebapiprod.ase.worldbank.org/dlw/api"
    ),
    api_version = Sys.getenv("DLW_API_VERSION", unset = "v1"),
    server = Sys.getenv("FDP_SERVER", unset = "FDP"),
    local_root = Sys.getenv("FDP_PATH", unset = ""),
    manifest_name = Sys.getenv(
      "FDP_MANIFEST",
      unset = ".fdp-sync-manifest.csv"
    ),
    dry_run = env_flag("FDP_DRY_RUN", default = FALSE),
    refresh = env_flag("FDP_REFRESH", default = FALSE),
    timeout_seconds = env_integer("FDP_TIMEOUT_SECONDS", default = 300L),
    retries = env_integer("FDP_RETRIES", default = 3L),
    user_agent = Sys.getenv(
      "FDP_USER_AGENT",
      unset = "50by35-data/0.1 (https://github.com/worldbank/50by35-data)"
    )
  )
}

abort_sync <- function(message, ...) {
  stop(paste0(message, ...), call. = FALSE)
}

require_config <- function(config) {
  if (!nzchar(trimws(Sys.getenv("DLW_TOKEN", unset = "")))) {
    abort_sync(
      "DLW_TOKEN is not set. Put it in .Renviron or export it before running update.R."
    )
  }

  if (!nzchar(config$local_root)) {
    abort_sync(
      "FDP_PATH is not set. Set it to the local directory that should contain the mirror."
    )
  }

  if (!nzchar(config$base_url) || !nzchar(config$api_version)) {
    abort_sync("DLW_API_URL and DLW_API_VERSION must not be empty.")
  }

  if (!nzchar(config$server)) {
    abort_sync("FDP_SERVER must not be empty.")
  }
}

api_request <- function(config, endpoint, method = "GET", ...) {
  token <- trimws(Sys.getenv("DLW_TOKEN", unset = ""))
  fields <- list(...)
  method <- toupper(method)
  if (!method %in% c("GET", "POST")) {
    abort_sync("Unsupported HTTP method: ", method, ".")
  }

  request <- httr2::request(config$base_url) |>
    httr2::req_url_path_append(config$api_version, endpoint) |>
    httr2::req_user_agent(config$user_agent) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_timeout(config$timeout_seconds) |>
    httr2::req_retry(
      max_tries = config$retries,
      max_seconds = config$timeout_seconds * config$retries,
      retry_on_failure = TRUE,
      is_transient = function(response) {
        httr2::resp_status(response) %in% c(429L, 500L, 502L, 503L, 504L)
      }
    )

  if (length(fields) > 0) {
    add_fields <- if (identical(method, "POST")) {
      httr2::req_body_form
    } else {
      httr2::req_url_query
    }
    request <- do.call(add_fields, c(list(request), fields))
  }

  # Keep non-2xx responses available to perform_request() so it can include
  # the status and response body in the error rather than losing that context.
  httr2::req_error(request, is_error = function(response) FALSE)
}

response_error <- function(response, endpoint, request_fields = list()) {
  status <- httr2::resp_status(response)
  status_description <- httr2::resp_status_desc(response)
  content_type <- scalar_text(httr2::resp_content_type(response))
  body <- tryCatch(
    httr2::resp_body_string(response),
    error = function(error) "<response body unavailable>"
  )
  body <- gsub("[[:space:]]+", " ", trimws(scalar_text(body)))
  if (nchar(body) > 500L) {
    body <- paste0(substr(body, 1L, 497L), "...")
  }

  fields <- request_fields[setdiff(names(request_fields), "token")]
  field_text <- if (length(fields) > 0) {
    paste(
      names(fields),
      vapply(fields, scalar_text, character(1)),
      sep = "=",
      collapse = ", "
    )
  } else {
    ""
  }

  message <- paste0(
    "Datalibweb request failed [",
    status,
    " ",
    status_description,
    "] at ",
    endpoint,
    if (nzchar(field_text)) paste0(" (", field_text, ")") else "",
    "."
  )
  if (nzchar(content_type)) {
    message <- paste0(message, " Content-Type: ", content_type, ".")
  }
  if (nzchar(body)) {
    message <- paste0(message, " Response: ", body)
  }

  abort_sync(message)
}

api_response_error <- function(response, endpoint, request_fields = list()) {
  status <- httr2::resp_status(response)
  status_description <- httr2::resp_status_desc(response)
  content_type <- scalar_text(httr2::resp_content_type(response))
  response_filename <- scalar_text(
    httr2::resp_header(response, "filename", default = "")
  )
  body <- tryCatch(
    httr2::resp_body_string(response),
    error = function(error) "<response body unavailable>"
  )
  body <- gsub("[[:space:]]+", " ", trimws(scalar_text(body)))
  if (nchar(body) > 500L) {
    body <- paste0(substr(body, 1L, 497L), "...")
  }

  fields <- request_fields[setdiff(names(request_fields), "token")]
  field_text <- if (length(fields) > 0) {
    paste(
      names(fields),
      vapply(fields, scalar_text, character(1)),
      sep = "=",
      collapse = ", "
    )
  } else {
    ""
  }

  message <- paste0(
    "Datalibweb returned an API error [",
    status,
    " ",
    status_description,
    "] at ",
    endpoint,
    if (nzchar(field_text)) paste0(" (", field_text, ")") else "",
    "."
  )
  if (nzchar(content_type)) {
    message <- paste0(message, " Content-Type: ", content_type, ".")
  }
  if (nzchar(response_filename)) {
    message <- paste0(message, " Response file: ", response_filename, ".")
  }
  if (nzchar(body)) {
    message <- paste0(message, " Response: ", body)
  }

  abort_sync(message)
}

is_api_error_response <- function(response) {
  response_filename <- tolower(scalar_text(
    httr2::resp_header(response, "filename", default = "")
  ))
  if (identical(response_filename, "ecafileinfo.csv")) {
    return(TRUE)
  }

  content_type <- tolower(scalar_text(httr2::resp_content_type(response)))
  inspect_body <- !nzchar(content_type) ||
    grepl("csv|json|xml|html", content_type)
  if (!inspect_body) {
    return(FALSE)
  }

  body_path <- inherits(response$body, "httr2_path")
  if (!nzchar(content_type) && body_path &&
      fs::file_info(response$body)$size > 1024^2) {
    return(FALSE)
  }

  body <- tryCatch(
    httr2::resp_body_string(response),
    error = function(error) ""
  )
  if (!nzchar(body)) {
    return(FALSE)
  }

  columns <- tryCatch(
    names(data.table::fread(text = body, nrows = 0L, showProgress = FALSE)),
    error = function(error) character()
  )
  if (all(c("filename", "errorcode", "errordetail") %in% tolower(columns))) {
    return(TRUE)
  }

  grepl("application/(problem\\+)?json|xml|html", content_type) &&
    grepl(
      "error|message|detail|not found|unauthori[sz]ed|forbidden",
      body,
      ignore.case = TRUE
    )
}

perform_request <- function(
  request,
  endpoint,
  request_fields = list(),
  path = NULL
) {
  response <- tryCatch(
    httr2::req_perform(request, path = path),
    error = function(error) {
      abort_sync(
        "Datalibweb request could not be completed at ",
        endpoint,
        ": ",
        conditionMessage(error)
      )
    }
  )

  status <- httr2::resp_status(response)
  if (status < 200L || status >= 300L) {
    response_error(response, endpoint, request_fields)
  }

  if (is_api_error_response(response)) {
    api_response_error(response, endpoint, request_fields)
  }

  response
}

parse_catalog <- function(response) {
  content_type <- tolower(scalar_text(httr2::resp_content_type(response)))
  if (!grepl("csv", content_type, fixed = TRUE)) {
    abort_sync(
      "The ServerCatalog endpoint returned Content-Type ",
      content_type,
      " instead of CSV."
    )
  }

  catalog <- tryCatch(
    data.table::fread(
      text = httr2::resp_body_string(response),
      na.strings = c("", "NA")
    ),
    error = function(error) {
      abort_sync("The FDP catalog could not be parsed: ", conditionMessage(error))
    }
  )

  required_columns <- c(
    "ServerAlias", "Country", "Year", "Survey", "FilePath",
    "FileSize", "Timestamp", "Checksum"
  )
  missing_columns <- setdiff(required_columns, names(catalog))
  if (length(missing_columns) > 0L) {
    abort_sync(
      "The FDP catalog is missing required columns: ",
      paste(missing_columns, collapse = ", ")
    )
  }

  catalog[, FilePath := gsub("\\\\", "/", FilePath)]
  catalog[, FileName := basename(FilePath)]
  catalog
}

get_catalog <- function(config) {
  request <- api_request(
    config,
    "ServerCatalog",
    Server = config$server
  )
  parse_catalog(perform_request(
    request,
    "ServerCatalog",
    list(Server = config$server)
  ))
}

select_sync_files <- function(catalog, server) {
  rows <- catalog[
    !is.na(ServerAlias) &
      !is.na(FileName) &
      toupper(ServerAlias) == toupper(server)
  ]

  rows <- rows[is_harmonized_collection_path(FilePath)]

  if (nrow(rows) == 0L) {
    abort_sync(
      "No harmonized FDP collection files were found for server ",
      server,
      "."
    )
  }

  if (anyDuplicated(rows$FilePath)) {
    duplicates <- unique(rows$FilePath[duplicated(rows$FilePath)])
    abort_sync(
      "The FDP catalog contains duplicate FilePath values: ",
      paste(duplicates, collapse = ", ")
    )
  }

  required_values <- c(
    "ServerAlias", "Country", "Year", "Survey", "FilePath", "FileName"
  )
  missing_values <- vapply(
    required_values,
    function(column) {
      values <- as.character(rows[[column]])
      any(is.na(values) | !nzchar(trimws(values)))
    },
    logical(1)
  )
  if (any(missing_values)) {
    abort_sync(
      "The FDP catalog has missing values in selected file fields: ",
      paste(names(missing_values)[missing_values], collapse = ", ")
    )
  }

  rows
}

is_harmonized_collection_path <- function(path) {
  grepl("(^|/)[^/]+_A_FDP/", path, ignore.case = TRUE)
}

validate_relative_path <- function(path) {
  if (is.na(path) || !nzchar(path)) {
    abort_sync("The catalog contains an empty FilePath.")
  }

  normalized <- gsub("\\\\", "/", path)
  if (startsWith(normalized, "/") || grepl("^[A-Za-z]:[/]", normalized)) {
    abort_sync("The catalog contains an absolute FilePath: ", path)
  }

  components <- strsplit(normalized, "/", fixed = TRUE)[[1L]]
  if (any(components %in% c("", ".", ".."))) {
    abort_sync("The catalog contains an unsafe FilePath: ", path)
  }

  normalized
}

validate_catalog_paths <- function(catalog, local_root) {
  catalog[, RelativePath := vapply(FilePath, validate_relative_path, character(1))]
  path_keys <- tolower(catalog$RelativePath)
  if (anyDuplicated(path_keys)) {
    duplicates <- unique(catalog$RelativePath[duplicated(path_keys)])
    abort_sync(
      "The FDP catalog contains paths that collide on case-insensitive filesystems: ",
      paste(duplicates, collapse = ", ")
    )
  }
  catalog[, LocalPath := fs::path(local_root, RelativePath)]

  root <- fs::path_norm(fs::path_abs(local_root))
  local_paths <- fs::path_norm(fs::path_abs(catalog$LocalPath))
  inside_root <- if (identical(root, "/")) {
    startsWith(local_paths, "/")
  } else {
    local_paths == root | startsWith(local_paths, paste0(root, "/"))
  }
  if (any(!inside_root)) {
    abort_sync("At least one catalog path escapes FDP_PATH.")
  }

  catalog
}

path_is_within <- function(path, root) {
  path <- fs::path_norm(fs::path_abs(path))
  root <- fs::path_norm(fs::path_abs(root))
  if (identical(root, "/")) {
    startsWith(path, "/")
  } else {
    path == root | startsWith(path, paste0(root, "/"))
  }
}

ensure_destination_parent <- function(local_root, local_path) {
  parent <- fs::path_dir(local_path)
  fs::dir_create(parent, recurse = TRUE)
  root_real <- fs::path_real(local_root)
  parent_real <- fs::path_real(parent)
  if (!path_is_within(parent_real, root_real)) {
    abort_sync("The destination directory escapes FDP_PATH: ", parent)
  }
  invisible(parent)
}

manifest_path <- function(config) {
  path <- config$manifest_name
  if (fs::is_absolute_path(path)) {
    path
  } else {
    fs::path(config$local_root, validate_relative_path(path))
  }
}

empty_manifest <- function() {
  data.table::data.table(
    RelativePath = character(),
    FileName = character(),
    Extension = character(),
    Country = character(),
    Year = integer(),
    Survey = character(),
    Bytes = numeric(),
    Sha256 = character(),
    ServerChecksum = character(),
    ServerFileSize = character(),
    ServerTimestamp = character(),
    SyncedAt = character()
  )
}

read_manifest <- function(path) {
  if (!fs::file_exists(path)) {
    return(empty_manifest())
  }

  manifest <- tryCatch(
    data.table::fread(
      path,
      na.strings = c("", "NA"),
      colClasses = "character"
    ),
    error = function(error) {
      abort_sync("The sync manifest could not be read: ", conditionMessage(error))
    }
  )

  required_columns <- names(empty_manifest())
  missing_columns <- setdiff(required_columns, names(manifest))
  if (length(missing_columns) > 0L) {
    abort_sync(
      "The sync manifest is missing required columns: ",
      paste(missing_columns, collapse = ", ")
    )
  }
  if (anyDuplicated(manifest$RelativePath)) {
    abort_sync("The sync manifest contains duplicate RelativePath values.")
  }
  manifest[, Bytes := suppressWarnings(as.numeric(Bytes))]
  manifest
}

sha256_file <- function(path) {
  digest::digest(path, algo = "sha256", file = TRUE)
}

same_local_file <- function(row, manifest_row, refresh = FALSE) {
  if (refresh || !fs::file_exists(row$LocalPath)) {
    return(FALSE)
  }

  local_size <- fs::file_info(row$LocalPath)$size
  if (is.na(local_size) || local_size == 0) {
    return(FALSE)
  }

  server_checksum <- scalar_text(row$Checksum)
  checksum_is_usable <- grepl(
    "^[0-9a-f]{32}$",
    server_checksum,
    ignore.case = TRUE
  ) && !identical(tolower(server_checksum), "d41d8cd98f00b204e9800998ecf8427e")

  manifest_checksum <- if (nrow(manifest_row) == 1L) {
    scalar_text(manifest_row$ServerChecksum[[1L]])
  } else {
    ""
  }
  checksum_matches <- !checksum_is_usable || identical(
    tolower(manifest_checksum),
    tolower(server_checksum)
  )

  if (nrow(manifest_row) == 1L &&
      identical(scalar_text(manifest_row$ServerFileSize[[1L]]), scalar_text(row$FileSize)) &&
      identical(scalar_text(manifest_row$ServerTimestamp[[1L]]), scalar_text(row$Timestamp)) &&
      checksum_matches &&
      identical(as.numeric(manifest_row$Bytes[[1L]]), as.numeric(local_size)) &&
      nzchar(scalar_text(manifest_row$Sha256[[1L]])) &&
      identical(scalar_text(manifest_row$Sha256[[1L]]), sha256_file(row$LocalPath))) {
    return(TRUE)
  }

  # The API checksum and human-readable size are not reliable enough to
  # identify an existing file. Download once to establish a local hash.
  FALSE
}

download_row <- function(row, config) {
  request_fields <- list(
    Server = config$server,
    Country = row$Country,
    filename = row$FileName,
    year = row$Year,
    survey = row$Survey,
    collection = config$server
  )
  request <- do.call(
    api_request,
    c(
      list(
        config = config,
        endpoint = "FileInformationInternal/GetFileInfo",
        method = "POST"
      ),
      request_fields
    )
  )

  ensure_destination_parent(config$local_root, row$LocalPath)
  temp_path <- fs::file_temp(
    pattern = ".fdp-download-",
    tmp_dir = fs::path_dir(row$LocalPath)
  )
  keep_temp <- FALSE
  on.exit(
    if (!keep_temp && fs::file_exists(temp_path)) fs::file_delete(temp_path),
    add = TRUE
  )

  response <- perform_request(
    request,
    "FileInformationInternal/GetFileInfo",
    request_fields,
    path = temp_path
  )

  expected_name <- row$FileName
  response_type <- tolower(scalar_text(httr2::resp_content_type(response)))
  expected_type <- tolower(tools::file_ext(expected_name))
  if (expected_type %in% c("dta", "do") &&
      nzchar(response_type) &&
      !response_type %in% c(
        expected_type,
        "application/octet-stream",
        "binary/octet-stream",
        if (expected_type == "do") c("text/plain", "plain") else "application/x-stata"
      )) {
    abort_sync(
      "The file endpoint returned Content-Type ",
      response_type,
      " for ",
      row$RelativePath,
      "; expected a ",
      expected_type,
      " file."
    )
  }

  response_name <- scalar_text(httr2::resp_header(response, "filename", default = ""))
  if (!nzchar(response_name)) {
    disposition <- scalar_text(
      httr2::resp_header(response, "content-disposition", default = "")
    )
    if (grepl("filename[[:space:]]*=", disposition, ignore.case = TRUE)) {
      response_name <- sub(
        ".*filename[[:space:]]*=[[:space:]]*\"?([^\";]+).*",
        "\\1",
        disposition,
        ignore.case = TRUE
      )
    }
  }
  if (nzchar(response_name) && !identical(basename(response_name), expected_name)) {
    abort_sync(
      "The API returned an unexpected filename for ",
      row$RelativePath,
      ": ",
      response_name
    )
  }

  if (!nzchar(response_type) && !nzchar(response_name)) {
    abort_sync(
      "The file endpoint returned no content type or filename for ",
      row$RelativePath,
      "."
    )
  }

  if (!fs::file_exists(temp_path)) {
    abort_sync("The API did not produce a file for ", row$RelativePath, ".")
  }

  bytes <- fs::file_info(temp_path)$size
  if (is.na(bytes) || bytes == 0) {
    abort_sync("The API returned an empty response for ", row$RelativePath, ".")
  }

  content_length <- suppressWarnings(as.numeric(
    httr2::resp_header(response, "content-length", default = NA_character_)
  ))
  if (!is.na(content_length) && bytes != content_length) {
    abort_sync(
      "The downloaded byte count for ",
      row$RelativePath,
      " does not match Content-Length."
    )
  }

  sha256 <- sha256_file(temp_path)
  keep_temp <- TRUE
  list(
    temp_path = temp_path,
    bytes = as.numeric(bytes),
    sha256 = sha256,
    content_type = response_type,
    response_name = response_name
  )
}

atomic_replace <- function(source, destination) {
  tryCatch(
    fs::file_move(source, destination),
    error = function(error) {
      abort_sync(
        "Could not replace ",
        destination,
        " with the completed temporary file: ",
        conditionMessage(error)
      )
    }
  )
  invisible(destination)
}

cleanup_temp_files <- function(local_root) {
  if (!fs::dir_exists(local_root)) {
    return(invisible(character()))
  }

  local_files <- fs::dir_ls(
    local_root,
    recurse = TRUE,
    type = "file",
    fail = FALSE
  )
  if (length(local_files) == 0L) {
    return(invisible(character()))
  }

  temporary_files <- local_files[grepl(
    "(^|/)[.]fdp-(download|manifest)-",
    local_files
  )]
  if (length(temporary_files) > 0L) {
    fs::file_delete(temporary_files)
  }
  invisible(temporary_files)
}

write_manifest <- function(manifest, path) {
  fs::dir_create(fs::path_dir(path), recurse = TRUE)
  temp_path <- fs::file_temp(pattern = ".fdp-manifest-", tmp_dir = fs::path_dir(path))
  on.exit(if (fs::file_exists(temp_path)) fs::file_delete(temp_path), add = TRUE)
  data.table::fwrite(manifest, temp_path, na = "")
  atomic_replace(temp_path, path)
  invisible(path)
}

sync_files <- function(catalog, config, manifest) {
  results <- vector("list", nrow(catalog))
  failure_result <- function(relative_path, error) {
    list(
      RelativePath = relative_path,
      status = "failed",
      bytes = NA_real_,
      sha256 = "",
      error = conditionMessage(error)
    )
  }

  for (i in seq_len(nrow(catalog))) {
    row <- catalog[i]
    manifest_row <- manifest[RelativePath == row$RelativePath]

    if (same_local_file(row, manifest_row, refresh = config$refresh)) {
      results[[i]] <- list(
        RelativePath = row$RelativePath,
        status = "unchanged",
        bytes = fs::file_info(row$LocalPath)$size,
        sha256 = if (nrow(manifest_row) == 1L) manifest_row$Sha256[[1L]] else ""
      )
      next
    }

    action <- if (fs::file_exists(row$LocalPath)) "update" else "download"
    if (config$dry_run) {
      results[[i]] <- list(
        RelativePath = row$RelativePath,
        status = paste0("would_", action),
        bytes = NA_real_,
        sha256 = ""
      )
      next
    }

    ensure_destination_parent(config$local_root, row$LocalPath)
    downloaded <- tryCatch(download_row(row, config), error = identity)
    if (inherits(downloaded, "error")) {
      results[[i]] <- failure_result(row$RelativePath, downloaded)
      next
    }

    replacement_error <- tryCatch(
      {
        atomic_replace(downloaded$temp_path, row$LocalPath)
        NULL
      },
      error = identity
    )
    if (inherits(replacement_error, "error")) {
      if (fs::file_exists(downloaded$temp_path)) {
        fs::file_delete(downloaded$temp_path)
      }
      results[[i]] <- failure_result(row$RelativePath, replacement_error)
      next
    }

    results[[i]] <- list(
      RelativePath = row$RelativePath,
      status = action,
      bytes = downloaded$bytes,
      sha256 = downloaded$sha256
    )
  }

  data.table::rbindlist(results, fill = TRUE)
}

build_manifest <- function(catalog, results, existing_manifest) {
  current <- catalog[, .(
    RelativePath,
    FileName,
    Extension = tolower(tools::file_ext(FileName)),
    Country,
    Year = as.integer(Year),
    Survey,
    ServerChecksum = as.character(Checksum),
    ServerFileSize = as.character(FileSize),
    ServerTimestamp = as.character(Timestamp)
  )]

  current[, existing_sha256 := existing_manifest$Sha256[
    match(RelativePath, existing_manifest$RelativePath)
  ]]
  current[, existing_bytes := existing_manifest$Bytes[
    match(RelativePath, existing_manifest$RelativePath)
  ]]
  current[, result_sha256 := results$sha256[match(RelativePath, results$RelativePath)]]
  current[, result_bytes := results$bytes[match(RelativePath, results$RelativePath)]]
  current[, Sha256 := ifelse(
    !is.na(result_sha256) & nzchar(result_sha256),
    result_sha256,
    existing_sha256
  )]
  current[, Bytes := ifelse(
    !is.na(result_bytes),
    result_bytes,
    existing_bytes
  )]
  missing_hash <- is.na(current$Sha256) | !nzchar(current$Sha256)
  if (any(is.na(current$Bytes)) || any(missing_hash)) {
    abort_sync("Cannot write a complete sync manifest because a synchronized file has no hash or byte count.")
  }
  current[, SyncedAt := format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")]

  current[, c("existing_sha256", "existing_bytes", "result_sha256", "result_bytes") := NULL]
  current[, .(
    RelativePath,
    FileName,
    Extension,
    Country,
    Year,
    Survey,
    Bytes,
    Sha256,
    ServerChecksum,
    ServerFileSize,
    ServerTimestamp,
    SyncedAt
  )]
}

find_orphans <- function(catalog, config, manifest_path_value) {
  if (!fs::dir_exists(config$local_root)) {
    return(character())
  }

  tracked <- c(catalog$RelativePath, fs::path_rel(manifest_path_value, config$local_root))
  local_files <- fs::dir_ls(
    config$local_root,
    recurse = TRUE,
    type = "file",
    fail = FALSE
  )
  if (length(local_files) == 0L) {
    return(character())
  }

  relative <- fs::path_rel(local_files, start = config$local_root)
  relative[!relative %in% tracked]
}

print_summary <- function(results, orphans, config) {
  counts <- table(factor(
    results$status,
    levels = c("unchanged", "download", "update", "failed", "would_download", "would_update")
  ))
  cat("FDP synchronization", if (config$dry_run) "(dry run)" else "", "\n", sep = " ")
  cat("  unchanged: ", counts[["unchanged"]], "\n", sep = "")
  cat("  downloaded: ", counts[["download"]], "\n", sep = "")
  cat("  updated: ", counts[["update"]], "\n", sep = "")
  cat("  failed: ", counts[["failed"]], "\n", sep = "")
  cat("  would download: ", counts[["would_download"]], "\n", sep = "")
  cat("  would update: ", counts[["would_update"]], "\n", sep = "")
  cat("  local orphans: ", length(orphans), "\n", sep = "")

  failures <- results[status == "failed"]
  if (nrow(failures) > 0L) {
    cat("\nFailed files:\n")
    for (i in seq_len(nrow(failures))) {
      cat("  - ", failures$RelativePath[[i]], ": ", failures$error[[i]], "\n", sep = "")
    }
  }

  if (length(orphans) > 0L) {
    cat("\nLocal files absent from the current catalog (not deleted):\n")
    cat(paste0("  - ", orphans, collapse = "\n"), "\n", sep = "")
  }
}

run_sync <- function() {
  config <- sync_config()
  require_config(config)
  if (!config$dry_run) {
    fs::dir_create(config$local_root, recurse = TRUE)
    cleanup_temp_files(config$local_root)
  }

  catalog <- get_catalog(config)
  catalog <- select_sync_files(catalog, config$server)
  catalog <- validate_catalog_paths(catalog, config$local_root)
  manifest_file <- manifest_path(config)
  existing_manifest <- read_manifest(manifest_file)

  results <- sync_files(catalog, config, existing_manifest)
  orphans <- find_orphans(catalog, config, manifest_file)

  if (!config$dry_run && !any(results$status == "failed")) {
    manifest <- build_manifest(catalog, results, existing_manifest)
    write_manifest(manifest, manifest_file)
  }

  print_summary(results, orphans, config)

  if (any(results$status == "failed")) {
    abort_sync("One or more files failed to synchronize.")
  }
  invisible(results)
}

if (sys.nframe() == 0L) {
  run_sync()
}
