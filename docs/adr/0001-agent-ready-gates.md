# ADR 0001: Agent-Ready Fast Feedback Loops and Progressive Ratcheting

- **Status:** Accepted
- **Date:** 2026-11-06

## Context

Autonomous coding agents iterate rapidly on small code changes before running the full blocking CI suite (`./mk ci`). They need sub-10-second inner-loop verification (`check`, `fix`, `test-fast`), deterministic non-colored output when `NO_COLOR` or `CI=1` is set, single-source-of-truth instructions (`AGENTS.md` + `CLAUDE.md`), and a tracked ledger (`docs/DEBT.md`) for legacy ratchets when adopting `rusti-graben` in existing repositories.

## Decision

1. Add fast inner-loop tasks to the standard `mk` runner (`check`, `fix`, `test-fast`, `watch`, `bench`, `udeps`, plus aliases `cov` and `hack`).
2. Fix `cargo_make()` in `mk` to invoke `cargo make --no-workspace "$@"` without `exec`, so `LOCAL_SETUP` loops run every task to completion.
3. Honor `NO_COLOR` and `CI=1` in `mk` by exporting `CARGO_TERM_COLOR=never` and `NO_COLOR=1`.
4. Ship `.config/nextest.toml`, `bacon.toml`, `.editorconfig`, `.vscode/settings.json`, `.github/PULL_REQUEST_TEMPLATE.md`, `CLAUDE.md`, and `docs/DEBT.md` in the template and sync/seed them via `scripts/adopt.sh` with per-gate opt-in flags (`ADOPT_MUTANTS`, `ADOPT_ECHOES`, `ADOPT_REFQUIEM`, `ADOPT_WORKFLOWS`).

## Consequences

- Every adopted repository gains identical `./mk check`, `./mk fix`, and `./mk test-fast` inner loops without custom `Makefile.toml` boilerplate.
- Adopted repositories with multi-step `LOCAL_SETUP` or custom `mk.local` tasks no longer need to diverge from the standard `mk` runner.
