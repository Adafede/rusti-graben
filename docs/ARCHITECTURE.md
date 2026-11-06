# Architecture

`rusti-graben` is a zero-drift Rust quality-hygiene template and adoption runner. Its architecture keeps local runs, git hooks, and CI workflows identical by funneling every check through a single shell entrypoint (`./mk`).

## Components

| Component | Path | Responsibility |
|---|---|---|
| Standard runner | `mk` | Single entrypoint for all blocking (`./mk ci`), nightly (`./mk ci-nightly`), release (`./mk ci-release`), and inner-loop (`./mk check`, `./mk fix`, `./mk test-fast`, `./mk watch`) tasks. |
| Pinned versions | `mk.versions` | Single source of truth for nightly toolchain date, `cargo-binstall` crate versions, `tombi`, and `shellcheck`. |
| Local extensions | `mk.local` | Repository-specific gate additions (`LOCAL_CI_GATES`), overrides (`LOCAL_OVERRIDES`), extra tools (`LOCAL_CARGO_TOOLS`), package scopes (`MIRI_PACKAGES`, `MUTANTS_PACKAGES`), and ratchets (`COVERAGE_FAIL_UNDER_LINES`, `ECHOES_MAX_*`). |
| Adoption script | `scripts/adopt.sh` | Idempotent dry-run/apply script that syncs standard files (`mk`, `mk.versions`, `.github/actions/setup/action.yml`) and seeds missing configs, lints, workflows, and agent guides into any single-crate or workspace Rust repository. |
| Gate selftest | `tests/gate_selftest.sh` | Proves every gate can fail by injecting one violation per gate into a scratch repository and asserting that `./mk <gate>` fails with the expected diagnostic, plus testing `scripts/adopt.sh` idempotency across workspace, single-crate, cargo-make, and custom-runner fixtures. |
| Sample crates | `crates/sample-lib`, `crates/sample-bin` | Minimal library and binary crates exercising workspace lint inheritance, doctests, README inclusion, CLI integration tests, and 100% mutation/line coverage. |

## Design Invariants

1. **Zero drift between local and CI**: `.github/workflows/*.yml` and `prek.toml` never invoke `cargo`, `clippy`, or linters directly; they call `./mk <task>`.
2. **Hard failure on tool drift**: `mk` verifies exact pinned versions from `mk.versions` before running any gate.
3. **Bounded mutation testing**: `run_mutants` in `mk` caps concurrency, disables debuginfo/incremental caches, runs at `nice 19`, and monitors free memory and disk space with a watchdog.
4. **Ratchets only tighten**: `./mk ratchet` compares `Cargo.toml` lint allows, `COVERAGE_FAIL_UNDER_LINES`, and `ECHOES_MAX_*` against the merge-base and rejects any loosening.
