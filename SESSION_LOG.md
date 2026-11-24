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
