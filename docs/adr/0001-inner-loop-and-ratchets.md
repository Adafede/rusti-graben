# ADR 0001: Fast Inner-Loop Tasks and Progressive Ratcheting

- **Status:** Accepted
- **Date:** 2026-11-06

## Context

Contributors iterate on small code changes before running the full blocking CI suite (`./mk ci`). Without fast local tasks, contributors either skip checks until push or bypass `./mk` by calling `cargo` directly, causing drift against CI. Existing repositories adopting `rusti-graben` also need progressive ratchets (`docs/DEBT.md` and `mk.local` floors) so strict gates can be introduced without rewriting legacy code all at once.

## Decision

1. Provide fast inner-loop tasks in the standard `mk` runner (`check`, `fix`, `test-fast`, `watch`, `bench`, `udeps`, plus aliases `cov` and `hack`).
2. Dispatch local tasks in `cargo_make()` through `task_<name>()` functions defined in `mk.local` or `cargo make --no-workspace "$@"` when `Makefile.toml` exists, without `exec`, so `LOCAL_SETUP` loops run every task to completion.
3. Honor `NO_COLOR` and `CI=1` in `mk` by exporting `CARGO_TERM_COLOR=never` and `NO_COLOR=1` for plain, deterministic output.
4. Ship `.config/nextest.toml`, `bacon.toml`, `.editorconfig`, `.vscode/settings.json`, `.github/PULL_REQUEST_TEMPLATE.md`, and `docs/DEBT.md` in the template and sync/seed them via `scripts/adopt.sh` with per-gate opt-in flags (`ADOPT_MUTANTS`, `ADOPT_ECHOES`, `ADOPT_REFQUIEM`, `ADOPT_WORKFLOWS`).

## Consequences

- Adopted repositories share identical `./mk check`, `./mk fix`, and `./mk test-fast` inner loops without custom `Makefile.toml` boilerplate.
- Repositories with multi-step `LOCAL_SETUP` or custom `mk.local` tasks can extend or override gates locally without modifying `mk`.
