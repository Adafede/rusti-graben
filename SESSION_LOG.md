# Refactor Session Log

## Baseline (Step 0 — `origin/main` `1c3af4b`)

- **Pinned tools synced**: `./mk setup ci` + `./mk tools` passed (`tombi 1.11.3`, `cargo-deny 0.21.0`, `cargo-machete 0.10.1`, etc.).
- **`./mk ci-fast`**: PASS in `22.813s` (`shell` 11s, `deny` 2s, `test-fast` 2s, `tools`/`ratchet`/`typos`/`lint`/`machete`/`echoes`/`refquiem` 1s each).
- **Release build time (`cargo build --workspace --release --timings`)**: `0.45s`.
- **`sample-bin` release size**: `435,872` bytes (`cargo bloat`: `.text` `213.5 KiB`, file `460.7 KiB`).
- **Code metrics (`tokei`)**: `3,157` total lines (`mk` 1,488, `tests/gate_selftest.sh` 580, `scripts/adopt.sh` 198, Rust 67).
- **Max function / block sizes**: `run_mutants` 168 LOC, main `case "$cmd"` 588 LOC, `affected_packages` 104 LOC, `mutants-plan` arm 101 LOC, `changed_rust_packages` 43 LOC, `run_tier` 42 LOC.
- **Inline Python / JSON regexes**: 4 inline `python3 -c` heredocs, 9 `grep -o`/`cut` JSON regexes across `mk` and `scripts/adopt.sh`.
- **Unit tests on runner/adoption**: 0.

## Phase 0 — Recon Audit

- **Deliverable**: Created `docs/audit/AUDIT.md` ranking `F-01`..`F-08` with `file:line` evidence.
- **Verification**: `NO_COLOR=1 ./mk ci-fast` (verified clean against `local:docs_boundary`, `typos`, `refquiem`).

## Phase 1 — Target Architecture & Migration Plan

- **Deliverables**: Rewrote [docs/ARCHITECTURE.md](file:///Users/adrutz/Git/rusti-graben/docs/ARCHITECTURE.md) with 5-layer dependency model and one-line component contracts; created [docs/REFACTOR_PLAN.md](file:///Users/adrutz/Git/rusti-graben/docs/REFACTOR_PLAN.md) with Steps 1–10.
- **Verification**: `NO_COLOR=1 ./mk ci-fast` (verified clean against `local:docs_boundary`, `typos`, `refquiem`).

## Step 1 — Characterization Tests

- **Files added**: [tests/characterization.sh](file:///Users/adrutz/Git/rusti-graben/tests/characterization.sh).
- **Tests added**: CLI `help`, `--list`, unknown-task exit/usage, `toml` alias, `mutants-plan` JSON/sharding/validation, `ratchet` numeric bounds, `scripts/adopt.sh` dry-run & idempotency, and `sample-bin` stdout golden output (`10 + 20 = 30`).
- **Verification**: `NO_COLOR=1 ./mk shell && NO_COLOR=1 ./mk ci-fast && tests/characterization.sh`.

## Step 2 — Extract Pure Metadata, Package Graph & Shard Planner

- **Files added**: [.mk/meta.py](file:///Users/adrutz/Git/rusti-graben/.mk/meta.py), [tests/test_meta.py](file:///Users/adrutz/Git/rusti-graben/tests/test_meta.py).
- **Files updated**: [mk](file:///Users/adrutz/Git/rusti-graben/mk), [mk.local](file:///Users/adrutz/Git/rusti-graben/mk.local), [scripts/adopt.sh](file:///Users/adrutz/Git/rusti-graben/scripts/adopt.sh), [tests/gate_selftest.sh](file:///Users/adrutz/Git/rusti-graben/tests/gate_selftest.sh).
- **Structural impact**: Eliminated all 4 inline `python3 -c` heredocs and all 6 `cargo metadata` JSON regex parsers in `mk` (1,488 → ~1,330 LOC); added unit tests + 50-trial seeded DAG property test via `local:runner_tests`.
- **Verification**: `python3 -m unittest discover -s tests -p 'test_*.py' -v`, `tests/characterization.sh`, `NO_COLOR=1 ./mk ci-fast`.

## Step 3 — Extract Gate Catalog & Core Primitives

- **Files added**: [.mk/catalog.sh](file:///Users/adrutz/Git/rusti-graben/.mk/catalog.sh), [.mk/core.sh](file:///Users/adrutz/Git/rusti-graben/.mk/core.sh).
- **Files updated**: [.mk/meta.py](file:///Users/adrutz/Git/rusti-graben/.mk/meta.py) (compacted `main()` dispatch under 300 LOC), [mk](file:///Users/adrutz/Git/rusti-graben/mk), [scripts/adopt.sh](file:///Users/adrutz/Git/rusti-graben/scripts/adopt.sh).
- **Structural impact**: Moved gate registry, aliases, help/listing, exit helpers, git diff queries, `upsert_kv_line`, docs-only diff classifier, and metadata shell facade into Layer 0 modules.
- **Verification**: `NO_COLOR=1 ./mk shell`, `tests/characterization.sh`, `NO_COLOR=1 ./mk ci-fast`.

## Step 4 — Extract Pinned Tool Isolation & Unified Installer

- **Files added**: [.mk/tools.sh](file:///Users/adrutz/Git/rusti-graben/.mk/tools.sh).
- **Files updated**: [mk](file:///Users/adrutz/Git/rusti-graben/mk), [scripts/adopt.sh](file:///Users/adrutz/Git/rusti-graben/scripts/adopt.sh).
- **Structural impact**: Extracted pinned tool resolution, `MK_TOOLS_DIR` PATH isolation, `$CARGO_HOME/bin` cache seeding, `cmd_setup`, and `cmd_tools` into Layer 1 `.mk/tools.sh`; unified `install_tombi` and `install_shellcheck` via shared `install_github_tarball`.
- **Verification**: `NO_COLOR=1 ./mk shell`, `NO_COLOR=1 ./mk tools`, `tests/characterization.sh`, `NO_COLOR=1 ./mk ci-fast`.

## Step 5 — Decompose Bounded Mutation Runner

- **Files added**: [.mk/mutants.sh](file:///Users/adrutz/Git/rusti-graben/.mk/mutants.sh).
- **Files updated**: [mk](file:///Users/adrutz/Git/rusti-graben/mk), [scripts/adopt.sh](file:///Users/adrutz/Git/rusti-graben/scripts/adopt.sh).
- **Structural impact**: Broke 168-LOC `run_mutants()` and 101-LOC `mutants-plan` into cohesive `<= 40`-LOC functions (`mutants_parse_flags`, `mutants_compute_budget`, `mutants_acquire_lock`, `mutants_exec_watchdog`, `mutants_plan_parse_args`, `cmd_mutants*`); `mk` shrunk from 875 to ~480 LOC.
- **Verification**: `NO_COLOR=1 ./mk shell`, `tests/characterization.sh`, `NO_COLOR=1 ./mk mutants-plan --mode full`, `NO_COLOR=1 ./mk ci-fast`.

## Step 6 — Extract Gate Handlers & Tier Engine (Thin `mk`)

- **Files added**: [.mk/gates.sh](file:///Users/adrutz/Git/rusti-graben/.mk/gates.sh), [.mk/tier.sh](file:///Users/adrutz/Git/rusti-graben/.mk/tier.sh).
- **Files updated**: [mk](file:///Users/adrutz/Git/rusti-graben/mk), [scripts/adopt.sh](file:///Users/adrutz/Git/rusti-graben/scripts/adopt.sh).
- **Structural impact**: Extracted all gate handlers into `.mk/gates.sh` (deduplicating `check-changed`/`test-changed` via `run_for_affected_packages` and `coverage`/`coverage-baseline` via `run_llvm_cov`) and tier engine into `.mk/tier.sh` (deduplicating `ci-nightly`/`ci-nightly-checks` via `run_nightly_tier`); shrunk `mk` from `1,488` LOC originally (`483` LOC in Step 5) down to `~105` LOC.
- **Verification**: `NO_COLOR=1 ./mk shell`, `tests/characterization.sh`, `NO_COLOR=1 ./mk ci-fast`.

## Step 7 — Modularize Adoption Runner

- **Files updated**: [scripts/adopt.sh](file:///Users/adrutz/Git/rusti-graben/scripts/adopt.sh).
- **Structural impact**: Eliminated `# shellcheck disable=SC2016`, all 4 `sh -c` wrappers, and all 3 `cargo metadata` JSON regexes; decomposed into cohesive phase functions (`sync_standard_runner`, `sync_gate_files`, `configure_deny_license`, `configure_lints`, `configure_member_lints`, `configure_debug_profiles`, `configure_gitignore`) using `.mk/meta.py`.
- **Verification**: `NO_COLOR=1 ./mk shell`, `tests/characterization.sh`, `NO_COLOR=1 ./mk ci-fast`.

## Step 8 — Modularize Selftest Suite

- **Files added**: [tests/selftest/harness.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/harness.sh), [tests/selftest/suite_unit.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/suite_unit.sh), [tests/selftest/suite_tools_ci.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/suite_tools_ci.sh), [tests/selftest/suite_mutants.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/suite_mutants.sh), [tests/selftest/suite_nightly.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/suite_nightly.sh), [tests/selftest/suite_adopt.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/suite_adopt.sh).
- **Files updated/removed**: [tests/gate_selftest.sh](file:///Users/adrutz/Git/rusti-graben/tests/gate_selftest.sh) (580 → 40 LOC), [mk.local](file:///Users/adrutz/Git/rusti-graben/mk.local) (`task_runner_tests` runs both `test_meta.py` and `suite_unit.sh`); deleted standalone `tests/characterization.sh` after merging into `suite_unit.sh`.
- **Verification**: `NO_COLOR=1 ./mk shell`, `NO_COLOR=1 ./mk ci-fast`, `NO_COLOR=1 ./mk selftest`.

## Step 9 — Rust Workspace Hygiene

- **Files updated**: [Cargo.toml](file:///Users/adrutz/Git/rusti-graben/Cargo.toml), [crates/sample-bin/Cargo.toml](file:///Users/adrutz/Git/rusti-graben/crates/sample-bin/Cargo.toml), [crates/sample-lib/Cargo.toml](file:///Users/adrutz/Git/rusti-graben/crates/sample-lib/Cargo.toml), [crates/sample-lib/src/lib.rs](file:///Users/adrutz/Git/rusti-graben/crates/sample-lib/src/lib.rs), [tests/selftest/suite_tools_ci.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/suite_tools_ci.sh).
- **Measured deltas**:
  - `sample-bin` release size (`stat -f%z`): `435,872` B → `339,824` B (`-22.0%`); `.text` (`cargo bloat`): `213.5 KiB` (608 methods) → `207.0 KiB` (555 methods).
  - Release build time (cold clean): `0.45s` → `52.84s` (`lto = "thin"`, `codegen-units = 1`, `strip = "symbols"` trade-off).
  - `sample-lib --no-default-features`: compiles cleanly as `no_std`; `./mk powerset`: 4/4 feature combinations pass.
- **Verification**: `NO_COLOR=1 ./mk tombi`, `cargo check -p sample-lib --no-default-features`, `NO_COLOR=1 ./mk powerset`, `NO_COLOR=1 ./mk ci`.

## Step 9.5 — Bytecode Hygiene & Strict Size Compliance

- **Files added**: [.mk/mutants_plan.sh](file:///Users/adrutz/Git/rusti-graben/.mk/mutants_plan.sh), [.mk/nightly.sh](file:///Users/adrutz/Git/rusti-graben/.mk/nightly.sh).
- **Files updated**: [.gitignore](file:///Users/adrutz/Git/rusti-graben/.gitignore), [mk](file:///Users/adrutz/Git/rusti-graben/mk), [mk.local](file:///Users/adrutz/Git/rusti-graben/mk.local), [.mk/core.sh](file:///Users/adrutz/Git/rusti-graben/.mk/core.sh), [.mk/meta.py](file:///Users/adrutz/Git/rusti-graben/.mk/meta.py), [.mk/mutants.sh](file:///Users/adrutz/Git/rusti-graben/.mk/mutants.sh), [.mk/gates.sh](file:///Users/adrutz/Git/rusti-graben/.mk/gates.sh), [scripts/adopt.sh](file:///Users/adrutz/Git/rusti-graben/scripts/adopt.sh), [tests/selftest/harness.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/harness.sh), [tests/selftest/suite_unit.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/suite_unit.sh), [tests/selftest/suite_adopt.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/suite_adopt.sh), [tests/selftest/suite_tools_ci.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/suite_tools_ci.sh), [docs/ARCHITECTURE.md](file:///Users/adrutz/Git/rusti-graben/docs/ARCHITECTURE.md).
- **Structural impact**: Enforced `python3 -B` across every runner/adoption/test invocation and ignored `__pycache__/`; split `.mk/mutants_plan.sh` and `.mk/nightly.sh` and decomposed selftest suite helpers so **zero** files exceed 300 LOC and **zero** functions exceed 40 LOC.
- **Verification**: LOC audit (`0` violations), `NO_COLOR=1 ./mk shell`, `NO_COLOR=1 ./mk ci-fast`.
