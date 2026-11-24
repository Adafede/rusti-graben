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
