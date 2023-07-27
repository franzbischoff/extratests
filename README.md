
<!-- README.md is generated from README.Rmd. Please edit that file -->

# extratests

<!-- badges: start -->

[![R build status - CRAN
installs](https://github.com/tidymodels/extratests/workflows/CRAN-R-CMD-check/badge.svg)](https://github.com/tidymodels/extratests/actions)
[![R build status - GH
installs](https://github.com/tidymodels/extratests/workflows/GH-R-CMD-check/badge.svg)](https://github.com/tidymodels/extratests/actions)
[![R build status -
Spark](https://github.com/tidymodels/extratests/workflows/spark-R-CMD-check/badge.svg)](https://github.com/tidymodels/extratests/actions)
<!-- badges: end -->

`extratests` is an internal package used for tests that

- Depend on multiple tidymodels packages

- Involve special/extra packages.

- Whose run-time is not practical for individual packages.

These tests are run on a cron job and are run for both CRAN versions and
the current GitHub development versions.

## PR-pairs with package repos

PRs on extratests typically are part of a PR pair since they test
changes in package repositories. The following workflow ensures that the
CI run triggered by the PR on extratests runs with the changes in the
corresponding PR on the package repository.

Normal development

- \[pkg\] Make changes
- [extratests](#extratests) Write tests

Set version for the change

- \[pkg\] Give it new dev version number in DESCRIPTION,
  e.g. `1.1.0.9001` instead of `1.1.0.9000`
- [extratests](#extratests) Add `skip_if_not_installed()` to the tests
  with that dev version number as `minimum_version`.

Open PRs and point GHA to the changes

- \[pkg\] Make a PR
- [extratests](#extratests) in `GH-R-CMD-check.yaml`, point GHA to the
  pkg PR by appending `#<PR number>`,
  e.g. `try(pak::pkg_install("tidymodels/parsnip#991"))`
  - Without pointing GHA to that branch, the tests will be skipped based
    on the version number.
  - If the branch information is added to the DESCRIPTION via `Remotes:`
    instead, the “CRAN workflow” will also run the dev version.
- [extratests](#extratests) Make a PR, link it to the pkg-PR in the PR
  description
- [extratests](#extratests) Make a review comment to change remote back
  to main before merging, such as
  <https://github.com/tidymodels/extratests/pull/103/files#r1269277696>

Clean-up and merge (after PR review and approval)

- \[pkg\] Merge PR
- [extratests](#extratests) Point remote back to main
- [extratests](#extratests) Merge PR
