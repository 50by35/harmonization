# 50by35 Harmonized Microdata

This repository maintains a local mirror of the harmonized collection files
available from the Datalibweb FDP server. The files support monitoring of the
50by35 vision.

`update.R` retrieves the current FDP server catalog and downloads every file
in the harmonized FDP collection using the Datalibweb API. Files are written
to the complete catalog-provided directory structure beneath `FDP_PATH`.

## Requirements

- R 4.2 or newer
- A Datalibweb token with access to the FDP server
- R packages: `data.table`, `digest`, `fs`, and `httr2`
- A local directory with enough storage for the mirror

Install the R packages if needed:

```r
install.packages(c("data.table", "digest", "fs", "httr2"))
```

For the test suite, also install `testthat`:

```r
install.packages("testthat")
```

## Configuration

Copy `.Renviron.example` to `.Renviron`, replace the placeholder values, or
set the variables in the shell. `.Renviron` is ignored by Git.

```text
DLW_TOKEN=your-datalibweb-token
FDP_PATH=/path/to/local/fdp-mirror
```

The token is read directly from `DLW_TOKEN` and is never written by this
repository. `FDP_PATH` may point to a SharePoint-synced folder or another
local directory.

Optional variables:

| Variable | Default | Description |
| --- | --- | --- |
| `DLW_API_URL` | `https://datalibwebapiprod.ase.worldbank.org/dlw/api` | Datalibweb API base URL |
| `DLW_API_VERSION` | `v1` | API version |
| `FDP_SERVER` | `FDP` | Datalibweb server alias |
| `FDP_MANIFEST` | `.fdp-sync-manifest.csv` | Manifest filename or absolute path |
| `FDP_DRY_RUN` | `false` | Report work without downloading files |
| `FDP_REFRESH` | `false` | Redownload every selected file |
| `FDP_TIMEOUT_SECONDS` | `300` | Timeout for an individual HTTP request |
| `FDP_RETRIES` | `3` | Maximum request attempts |
| `FDP_USER_AGENT` | repository default | HTTP user agent |

## Usage

Run from the repository root:

```sh
Rscript update.R
```

Run a safe catalog and filesystem preview first:

```sh
FDP_DRY_RUN=true Rscript update.R
```

To force a complete refresh:

```sh
FDP_REFRESH=true Rscript update.R
```

The script prints a summary of unchanged, downloaded, updated, and failed
files. Files that exist locally but are no longer in the catalog are reported
as orphans and are not deleted automatically.

## What Is Synced

Every file beneath a harmonized FDP collection directory in the FDP server
catalog is synchronized. The collection is identified from the catalog path by
a directory component ending in `_A_FDP`, for example:

```text
COL/COL_2023_GEIH/COL_2023_GEIH_V01_M_V01_A_FDP/
```

This currently includes:

- Harmonized Stata datasets under `Data/Harmonized/`
- Harmonization programs under `Programs/`

The selection is not restricted by filename or extension. Programs can use
different naming conventions and languages, including Stata `.do`, R, Python,
or other script files exposed by the catalog. Any additional files under the
harmonized collection directory are included as well.

Source/non-harmonized files under directories such as `..._V01_M/Data/Stata/`
are intentionally excluded. The catalog's complete `FilePath` is preserved
below `FDP_PATH`, including the country, survey, version, collection, and
directory structure.

## Safe Synchronization

- Catalog paths must be relative and cannot contain `..` path components.
- Downloads are streamed to a temporary file in the destination directory, so
  large datasets are not buffered in memory.
- A destination is replaced only after the complete response is received and
  validated.
- The response filename and `Content-Length` are checked when supplied by the
  API.
- A local SHA-256 manifest is written after a successful complete sync.
- The API's current checksum field is retained as metadata but is not trusted
  for change detection because it currently reports the same empty-file MD5
  value for all observed catalog rows.
- Existing local files are not treated as unchanged until a matching manifest
  entry and SHA-256 hash are available.
- Failed synchronization runs do not overwrite the previous manifest.
- Requests retry connection failures and HTTP `429`, `500`, `502`, `503`, and
  `504` responses up to `FDP_RETRIES` times.
- The API's human-readable `FileSize` values are not treated as exact byte
  counts. A local manifest hash is required before a file is considered
  unchanged.

## Tests

Run the unit tests from the repository root with:

```sh
Rscript tests/testthat.R
```

From another working directory, use the absolute path to `tests/testthat.R`.

The tests do not require a Datalibweb token or network access.
