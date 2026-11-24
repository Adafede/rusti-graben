# Review Notes (`rusti-graben` Deep Refactor)

## 1. Key Architectural Decisions & Rejected Alternatives

1. **Layered `.mk/` Bash + Pure-Stdlib Python vs. Rewriting `mk` in Compiled Rust**
   - *Decision*: Decomposed `mk` into 9 strictly layered modules under `.mk/` (`.mk/meta.py` + 8 focused Bash modules) synced into adopted repos via `scripts/adopt.sh`.
   - *Rejected alternative*: Compiling `mk` as a Rust workspace crate (`xtask`/CLI binary).
   - *Why*: `rusti-graben` is an adoption template synced into arbitrary single-crate and workspace repos. Adding a Rust runner crate would pollute adopted repos' `Cargo.toml`, `Cargo.lock`, `cargo deny`, `cargo audit`, `cargo machete`, `cargo publish`, and bootstrap order (running `./mk setup` before `rustc`/tools exist). The `.mk/` + Python 3 stdlib design keeps zero Rust build prerequisites while achieving strict layering, pure-function unit/property testing, and `<= 300`-LOC files.
2. **Centralized `.mk/meta.py` for All `cargo metadata` & Graph Queries**
   - *Decision*: Consolidated all workspace queries (`packages`, `manifests`, `has-lib`, `msrv`, `license`, `has-stable-version`, `has-publishable`), package-graph scoping (`changed`, `affected`), shard math, and JSON emission into `.mk/meta.py`, with pure functions decoupled from `cargo` subprocess calls.
   - *Rejected alternative*: Keeping ad-hoc `grep -o` JSON regexes and per-function inline `python3 -c` heredocs.
   - *Why*: Eliminates 9 fragile regex JSON parsers and 4 duplicated Python blocks, enables seeded randomized DAG property testing in `tests/test_meta.py`, and fixes `.mk/` trigger detection in `affected_packages`.
3. **Template-Only `local:runner_tests` Below `# Ratchet:` in `mk.local`**
   - *Decision*: Wired `tests/test_meta.py` and `tests/selftest/suite_unit.sh` into `LOCAL_CI_GATES` below `# Ratchet:` in `mk.local`.
   - *Why*: Ensures `./mk ci-fast` and `./mk ci` verify runner/graph/CLI regressions on every PR without leaking template-specific tests into adopted repositories (`scripts/adopt.sh` strips from `# Ratchet:` downward).

## 2. Intentional Behavior Changes

1. **`.mk/*` added to `STANDARD` in `scripts/adopt.sh`**: Adopted repositories now receive `.mk/{catalog,core,gates,mutants,mutants_plan,nightly,tier,tools}.sh` and `.mk/meta.py` alongside `mk`, `mk.versions`, and `.github/actions/setup/action.yml`, and stale `.mk/` files are resynced on re-run.
2. **`.mk/` added to `root_triggers` in `.mk/meta.py`**: Editing any `.mk/*` file treats all workspace packages as affected in `./mk check-changed`, `./mk test-changed`, and `./mk mutants-affected`, matching root `mk`.
3. **`sample-lib` optional `no_std` support**: Added `[features] default = ["std"]` and `#![cfg_attr(not(feature = "std"), no_std)]` in `crates/sample-lib` while keeping `std` enabled by default so `./mk wasm` selftest injection (`std::os::unix::ffi::OsStrExt`) continues to work.
4. **Release profile tuning in `Cargo.toml`**: Added `[profile.release]` (`lto = "thin"`, `codegen-units = 1`, `strip = "symbols"`), shrinking `sample-bin` by `22.0%` (`435,872` B → `339,824` B) at the cost of slower clean release LTO builds (`0.45s` → `52.84s`).
5. **`python3 -B` & `__pycache__/` hygiene**: Runner, adoption, and test invocations pass `-B` (`PYTHONDONTWRITEBYTECODE=1`) so running checks never dirties working trees with `.mk/__pycache__/`.
6. **`CONTRIBUTING.md` MSRV update**: Updated documented MSRV from stale `1.85` to `1.100.0` matching `Cargo.toml`.

## 3. Remaining Debt (Ranked)

1. **`./mk shell` wall time (`~51s`)**: Running `shellcheck --external-sources --severity=style` across all modular `.mk/*.sh` and `tests/selftest/*.sh` files in one invocation analyzes combined sourced ASTs multiple times (up from `11s` before modularization). Keeping targeted per-file or non-redundant `--external-sources` invocation in `cmd_shell` could be benchmarked if CI latency grows.
2. **Release cold LTO build time (`52.84s`)**: `lto = "thin"` + `codegen-units = 1` trades compile speed for binary size; projects optimizing release CI speed over binary footprint can remove or override `[profile.release]`.
3. **Scoped `# shellcheck disable=SC2016,SC2154` in `tests/selftest/suite_*.sh` and `# shellcheck disable=SC2154` on config-reading functions in `.mk/*.sh`**: Necessary because `cmd_shell` lints every `.sh` file individually without knowing variables sourced from `mk`/`mk.versions`/`mk.local` or `tests/selftest/harness.sh` at runtime.

## 4. What to Scrutinize First

1. **[.mk/mutants.sh](file:///Users/adrutz/Git/rusti-graben/.mk/mutants.sh) & [.mk/mutants_plan.sh](file:///Users/adrutz/Git/rusti-graben/.mk/mutants_plan.sh)**: Verify `run_mutants` process-group watchdog (`set -m`, `SIGINT`/`SIGKILL`), atomic `mkdir` lockdir acquisition/release, and `mutants-plan` JSON schema.
2. **[.mk/meta.py](file:///Users/adrutz/Git/rusti-graben/.mk/meta.py) & [tests/test_meta.py](file:///Users/adrutz/Git/rusti-graben/tests/test_meta.py)**: Verify workspace member filtering, longest-prefix nested crate matching, transitive reverse-dependency traversal, and `root_triggers`.
3. **[scripts/adopt.sh](file:///Users/adrutz/Git/rusti-graben/scripts/adopt.sh) & [tests/selftest/suite_adopt.sh](file:///Users/adrutz/Git/rusti-graben/tests/selftest/suite_adopt.sh)**: Verify `STANDARD` sync list, template-stripping in `seed_agents`/`seed_debt`/`write_mk_local`, and dry-run/idempotency guarantees.
4. **[.mk/tier.sh](file:///Users/adrutz/Git/rusti-graben/.mk/tier.sh) & [.mk/gates.sh](file:///Users/adrutz/Git/rusti-graben/.mk/gates.sh)**: Verify `LOCAL_OVERRIDES` cannot replace `mutants`/`mutants-diff`/`mutants-affected`, and `docs_or_meta_only_diff` never skips Rust gates on `.mk/*` edits.
