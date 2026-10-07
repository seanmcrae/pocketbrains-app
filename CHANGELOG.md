# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The app
has not been released; versions refer to `MARKETING_VERSION` in
`project.yml`.

## [Unreleased]

### Added
- Reproducible tool-calling eval for the deterministic router
  (`Tests/Eval`): synthetic 40-utterance corpus, tool and end-to-end
  accuracy, latency, results in the CI job summary and README.
- `ToolCallParser`, extracted from the MLX backend so the prompted
  tool-call envelope is compiled and tested in every build.
- Tests for the tool registry, deterministic date parsing against a fixed
  reference date, and router regressions.
- CI on pull requests, a Linux repository-hygiene job
  (`scripts/check-hygiene.sh`), Dependabot for GitHub Actions.
- `docs/PRODUCT.md`, rewritten `docs/ARCHITECTURE.md` and `README.md`,
  `SECURITY.md`, `CONTRIBUTING.md`, issue and pull request templates.

### Fixed
- Router: explicit capture commands ("remind me…", "add a task…",
  "note…") now take precedence over keyword rules, so "remind me to
  finish the deck" creates a task instead of completing one.
- Router: "in N days" no longer leaks into task titles.
- Router: "notes about X" searches instead of creating a note.

### Changed
- CI no longer force-pushes failure logs to a `ci-log` branch and runs
  with read-only repository permissions.

### Removed
- A machine-specific sync script containing an absolute local path.
- The CC0 public-domain dedication, pending a licensing decision.

## [0.1.0] - 2026-07-22

First complete build of the app on `main`: the thread and spaces shell,
Deep Glass design system, SwiftData data layer, 13-tool agent with the
Foundation Models, MLX and deterministic backends, morning brief and
evening reflection, Siri intents, JSON export, privacy manifest, and a
31-test suite running on CI. Includes the data-persistence fixes recorded
in `docs/QA_REPORT.md`.
