# Refactor Plan

Ordered, incremental migration plan executing against `docs/audit/AUDIT.md` and `docs/ARCHITECTURE.md`. Every step ends in a green build/test run and one Conventional Commit.

## Migration Steps

- [x] **Step 0 — Environment Sync & Baseline Timings**: Sync pinned CI tools (`./mk setup ci`), verify `./mk tools` and `./mk ci-fast`, capture baseline release build/binary/timing metrics.
- [x] **Phase 0 — Recon Audit (`docs/audit/AUDIT.md`)**: Map workspace, capture `tokei`/`cargo bloat`/hotspot baselines, rank findings `F-01`..`F-08` (`af2d61a`).
- [x] **Phase 1 — Target Architecture & Plan (`docs/ARCHITECTURE.md`, `docs/REFACTOR_PLAN.md`)**: Define strict layered architecture, one-line component contracts, error/concurrency invariants, and step plan.
- [x] **Step 1 — Characterization Tests (`tests/characterization.sh`)**: Pin current behavior of `mk` (`help`, `--list`, unknown task, aliases, `mutants-plan`, `ratchet` validation), `scripts/adopt.sh` (dry-run & idempotency), and `sample-bin` stdout before modifying runner code.
  - *Verify*: `NO_COLOR=1 ./mk shell && NO_COLOR=1 ./mk ci-fast && tests/characterization.sh`
  - *Rollback*: Delete `tests/characterization.sh`.
- [x] **Step 2 — Pure Metadata, Graph & Shard Planner (`.mk/meta.py`, `tests/test_meta.py`)**: Extract all 4 inline Python heredocs and all `cargo metadata` JSON regexes into pure stdlib functions in `.mk/meta.py` with unit + seeded-DAG property tests in `tests/test_meta.py`; register template-only `local:runner_tests` in `mk.local`.
  - *Verify*: `python3 -m unittest discover -s tests -p 'test_*.py' -v && tests/characterization.sh && NO_COLOR=1 ./mk ci-fast`
  - *Rollback*: Revert `.mk/meta.py`, `tests/test_meta.py`, and `mk`/`mk.local`/`scripts/adopt.sh` changes.
- [x] **Step 3 — Gate Catalog & Core Primitives (`.mk/catalog.sh`, `.mk/core.sh`)**: Extract declarative gate tables, alias normalization, help/list formatting, exit helpers, git diff helpers, `mk.local` key upserts, and docs-only diff classifier.
  - *Verify*: `NO_COLOR=1 ./mk shell && tests/characterization.sh && NO_COLOR=1 ./mk ci-fast`
  - *Rollback*: Revert commit restoring catalog/core functions into `mk`.
- [x] **Step 4 — Pinned Tool Isolation & Unified Installer (`.mk/tools.sh`)**: Extract version spec parsing, `MK_TOOLS_DIR` `PATH` isolation, `$CARGO_HOME/bin` seeding, and unify `install_tombi` + `install_shellcheck` via `install_github_tarball`.
  - *Verify*: `NO_COLOR=1 ./mk shell && NO_COLOR=1 ./mk tools && tests/characterization.sh && NO_COLOR=1 ./mk ci-fast`
  - *Rollback*: Revert commit restoring tool management into `mk`.
- [x] **Step 5 — Decompose Bounded Mutation Runner (`.mk/mutants.sh`)**: Break 168-LOC `run_mutants()` and 101-LOC `mutants-plan` into cohesive `<= 38`-LOC functions (flag parsing, config inspection, budget computation, `TMPDIR`, lockdir, watchdog, scoping, commands).
  - *Verify*: `NO_COLOR=1 ./mk shell && tests/characterization.sh && NO_COLOR=1 ./mk mutants-plan --mode full && NO_COLOR=1 ./mk ci-fast`
  - *Rollback*: Revert commit restoring mutation logic into `mk`.
- [x] **Step 6 — Gate Handlers & Tier Engine (`.mk/gates.sh`, `.mk/tier.sh`, thin `mk`)**: Extract all gate command handlers, deduplicate `check-changed`/`test-changed`, `coverage`/`coverage-baseline`, and `ci-nightly`/`ci-nightly-checks`, and shrink `mk` to `<= 120` LOC.
  - *Verify*: `NO_COLOR=1 ./mk shell && tests/characterization.sh && NO_COLOR=1 ./mk ci-fast`
  - *Rollback*: Revert commit restoring handlers into `mk`.
- [x] **Step 7 — Modularize Adoption Runner (`scripts/adopt.sh`)**: Replace `sh -c` hacks (`SC2016`) and JSON regexes with named phase functions and `.mk/meta.py`, and sync all `.mk/*` files in `STANDARD`.
  - *Verify*: `NO_COLOR=1 ./mk shell && tests/characterization.sh && NO_COLOR=1 ./mk ci-fast`
  - *Rollback*: Revert commit restoring previous `scripts/adopt.sh`.
- [x] **Step 8 — Modularize Selftest Suite (`tests/gate_selftest.sh`, `tests/selftest/*.sh`)**: Split 580-LOC selftest into reusable assertion harness, fast unit/characterization suite (merged from `tests/characterization.sh` and wired into `local:runner_tests`), CI/tool suite, mutants suite, nightly suite, and adoption suite (verifying `.mk/*` sync).
  - *Verify*: `NO_COLOR=1 ./mk shell && NO_COLOR=1 ./mk ci-fast && NO_COLOR=1 ./mk selftest`
  - *Rollback*: Revert commit restoring monolithic `tests/gate_selftest.sh`.
- [x] **Step 9 — Rust Workspace Hygiene (`Cargo.toml`, `crates/sample-*`)**: Introduce `[workspace.dependencies]`, add `[profile.release]` (`lto = "thin"`, `codegen-units = 1`, `strip = "symbols"`), make `sample-lib` `no_std`-capable (`default = ["std"]`), and record binary-size/build-time deltas.
- [x] **Step 9.5 — Bytecode Hygiene & Strict File/Function Size Compliance**: Add `python3 -B` / `__pycache__/` hygiene, split `.mk/mutants_plan.sh` and `.mk/nightly.sh` so all files are `<= 300` LOC and all functions `<= 40` LOC.
  - *Verify*: `cargo check -p sample-lib --no-default-features && NO_COLOR=1 ./mk powerset && NO_COLOR=1 ./mk ci && NO_COLOR=1 ./mk selftest`
  - *Rollback*: Revert workspace manifest and `sample-lib` feature changes.
- [x] **Step 10 — Doc Alignment, Anti-Timidity Check & Final Sign-off**: Update human and contributor docs (`CONTRIBUTING.md` MSRV, `README.md`, `docs/ADOPTING.md`, `docs/GATES.md`, etc.), finalize `SESSION_LOG.md` anti-timidity metrics and `REVIEW_NOTES.md`, and run full verification (`ci`, `ci-nightly`, `selftest`, `ci-release`).
  - *Verify*: `NO_COLOR=1 ./mk ci && NO_COLOR=1 ./mk ci-nightly && NO_COLOR=1 ./mk selftest && NO_COLOR=1 ./mk ci-release`
  - *Rollback*: Revert doc-finalization commit.
