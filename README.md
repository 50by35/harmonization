# 50by35 Harmonization

This repository maintains a local mirror of the harmonized files available from the Datalibweb FDP server. The files support monitoring of the 50by35 vision. The complete mirror, including microdata, is stored outside Git; only harmonization programs are tracked here.

`update.R` retrieves the current FDP server catalog and downloads every file in the harmonized FDP collection using the Datalibweb API. The complete catalog-provided directory structure is written beneath `FDP_PATH`, while files under `Programs/` are also copied locally into this repository's `FDP/` directory.

## Requirements

- R 4.2 or newer
- A Datalibweb token with access to the FDP server
- R packages managed by `renv` (runtime: `data.table`, `digest`, `fs`, and `httr2`; tests additionally use `testthat` and `withr`)
- A local directory with enough storage for the mirror
- The configured `FDP_PATH` must be outside this repository

The `DLW_TOKEN` must have permission to access all files in the harmonized
FDP collection for synchronization to complete successfully. Verified users
can request a token at <https://datalibweb2.worldbank.org/>.

Restore the project environment from the lockfile:

```sh
Rscript -e 'renv::restore()'
```

After changing dependencies, update the lockfile:

```sh
Rscript -e 'renv::snapshot()'
```

The committed `renv.lock` records the R version and exact package versions.

## Configuration

Copy `.Renviron.example` to `.Renviron`, replace the placeholder values, or
set the variables in the shell. `.Renviron` is ignored by Git.

```text
DLW_TOKEN=your-datalibweb-token
FDP_PATH=/path/to/local/fdp-mirror
```

The token is read directly from `DLW_TOKEN` and is never written by this repository. `FDP_PATH` may point to a SharePoint-synced folder or another local directory. The repository's `FDP/` path is inferred from `update.R`, or can be overridden with `FDP_REPO_PATH`.

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
| `FDP_REPO_PATH` | directory containing `update.R` | Repository root used for the tracked program mirror |

## Usage

Run from the repository root:

```sh
Rscript -e 'renv::restore()'  # first setup only
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

The script prints a summary of unchanged, downloaded, updated, copied, and failed files. Files that exist locally but are no longer in the catalog are reported as orphans and are not deleted automatically.

## What Is Synced

Every file beneath a harmonized FDP collection directory in the FDP server catalog is synchronized. The collection is identified from the catalog path by a directory component ending in `_A_FDP`, for example:

```text
COL/COL_2023_GEIH/COL_2023_GEIH_V01_M_V01_A_FDP/
```

This currently includes:

- Harmonized Stata datasets under `Data/Harmonized/`
- Harmonization code under `Programs/`. These files are downloaded once to `FDP_PATH` and copied from there into the repository's `FDP/` tree.

Programs can use different naming conventions and supported source formats, including Stata `.do`/`.ado`, R, Python, SAS, SQL, and shell scripts. The repository mirror uses a source-extension allowlist so unfamiliar data, document, and binary formats are not copied into Git; all catalog files still go to `FDP_PATH`.

Raw/non-harmonized files under directories such as `..._V01_M/Data/Stata/` are intentionally excluded. The catalog's complete `FilePath` is preserved below `FDP_PATH`, including the country, survey, version, collection, and directory structure. The same relative path is used below repository `FDP/` for program files only.

## Safe Synchronization

- Catalog paths must be relative and cannot contain `..` path components.
- Downloads are streamed to a temporary file in the destination directory, so large datasets are not buffered in memory.
- A destination is replaced only after the complete response is received and validated.
- The response filename and `Content-Length` are checked when supplied by the API.
- A local SHA-256 manifest is written after a successful complete sync.
- The API's current checksum field is retained as metadata but is not trusted for change detection because it currently reports the same empty-file MD5 value for all observed catalog rows.
- Existing local files are not treated as unchanged until a matching manifest entry and SHA-256 hash are available.
- Failed synchronization runs do not overwrite the previous manifest.
- Requests retry connection failures and HTTP `429`, `500`, `502`, `503`, and `504` responses up to `FDP_RETRIES` times.
- The API's human-readable `FileSize` values are not treated as exact byte counts. A local manifest hash is required before a file is considered unchanged.
- A current file in `FDP_PATH` repairs a missing or changed repository program copy locally without another API download.
- `FDP_PATH` and the repository root cannot contain one another, preventing microdata from being written into the Git worktree.

## Tests

Run the unit tests from the repository root with:

```sh
Rscript tests/testthat.R
```

From another working directory, use the absolute path to `tests/testthat.R`.

The tests do not require a Datalibweb token or network access.
