# sigilbadges

Every release, as it ships. This page is generated automatically from changelog.md — edit the markdown and reload to update it.

## 0.2.0 — August 15, 2026

- Fixed `badge:`/`badge-row:` markers hard-erroring whenever a file also contained `sigilmd`'s own `$table.key` / `@table.key` reference markers — both tools share the same `<!--[[ ]]-->` bracket syntax with no namespace, so `sigilbadges` now recognizes and skips sigilmd's (unambiguous) reference shape instead of dying on it. Table-*declare* markers (a bare identifier) are deliberately not whitelisted — that shape is indistinguishable from a mistyped `badge:` marker, so it still hard-errors on purpose
- Fixed a `uses: lucianofedericopereira/sigilbadges@v0.1.0` pin in the docs that never matched any real tag — the actual published tag is `v0.1`
- Added the missing `LICENSE` file (the README's own license badge already linked to it)
- Fixed missing i18n coverage on the changelog page's nav links and headings
- Removed a stale reference to a retired sibling project in the README's opening paragraph

## 0.1.0 — August 11, 2026

- Added `sigilbadges.pl`: a single core-Perl script that scans a Markdown file for `<!--[[ badge: ... ]]-->` and `<!--[[ badge-row: ... ]]-->` marker comments and regenerates the matching SVG badges in place — no template language, no CPAN dependencies, no external binary
- Added five badge styles: `chip` (this project's own gradient look), `flat`, `flat-square`, `plastic`, and `for-the-badge`
- Added 21 bundled brand logos under `assets/logos/`, each with a default brand color, plus support for `logo-color=` and `color=` overrides on any badge
- Added `badge-row:` for a responsive strip of badges sharing one set of defaults, with per-badge specs living in the marker's own tag (not the disposable body) so a re-run never loses them
- Added `--check` for CI: exits non-zero without writing anything when the README or any badge SVG is out of date
- Added `action.yml`, a composite GitHub Action wrapping the script — no interpreter setup step, since GitHub-hosted runners ship Perl natively
- Added a CI workflow that runs the test suite unmodified across a matrix of Perl versions, and a dogfooding job that checks this repo's own README against `--check`
- Added a test suite (`prove -r t`) exercising the marker grammar, every style, color/key validation errors, duplicate-id detection, and idempotency of repeated runs
- Added the project site (`index.html`, `docs.html`, this changelog) and a `sigilbadges.svg` wordmark as the project's logo
