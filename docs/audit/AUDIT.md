# Baseline Workspace Audit (`rusti-graben`)

> Read-only reconnaissance captured against `origin/main` (`1c3af4b`) before any structural refactor.

## 1. Workspace & Repository Map

| Component | Path | Type | Responsibility |
|---|---|---|---|
| Workspace manifest | `Cargo.toml` | Cargo workspace | Workspace members, edition `2024`, MSRV `1.100.0`, shared lint tables, dev/test dependency debug profile |
| Sample domain lib | `crates/sample-lib` | Library crate (`rlib`) | Minimal pure `sample_lib::add` function, doc/README tests, mutant-kill tests |
| Sample CLI binary | `crates/sample-bin` | Binary crate (`bin`) | CLI entrypoint printing `10 + 20 = 30` via `sample_lib::add`, process-level integration test |
| Standard runner | `mk` | Bash script (1,488 LOC) | Monolithic task runner handling dispatch, tool pins/installs, metadata/graph queries, mutation watchdog, all CI/nightly gates |
| Tool pins | `mk.versions` | Shell env | Pinned nightly toolchain, `CARGO_TOOLS_CI`, `CARGO_TOOLS_NIGHTLY`, `TOMBI_VERSION`, `SHELLCHECK_VERSION` |
| Local config | `mk.local` | Shell env + functions | Repo ratchets (`COVERAGE_FAIL_UNDER_LINES=100`) and template-only `local:docs_boundary` gate |
| Adoption script | `scripts/adopt.sh` | Bash script (198 LOC) | Idempotent adoption & sync of standard runner, lints, deny rules, workflows, and contributor docs |
| Gate selftest | `tests/gate_selftest.sh` | Bash script (580 LOC) | Scratch-repo violation injection suite for CI/nightly gates plus `scripts/adopt.sh` fixture tests |
| CI/CD workflows | `.github/workflows/*.yml`, `.github/actions/setup/action.yml` | GitHub Actions | Sharded CI/nightly/release/selftest pipelines delegating exclusively to `./mk` |

### Rust Cargo Dependency Graph & Targets

- **Dependency tree**: `sample-bin v0.1.0 -> sample-lib v0.1.0` (zero external crates, zero duplicate versions).
- **Feature flags**: None defined in `Cargo.toml`, `crates/sample-lib/Cargo.toml`, or `crates/sample-bin/Cargo.toml`.
- **Build targets**: Native host (`aarch64-apple-darwin` locally, `x86_64-unknown-linux-gnu` on CI); `wasm32-unknown-unknown` is supported via `./mk wasm` when declared in `rust-toolchain.toml` or `Cargo.toml` (currently commented out in `rust-toolchain.toml:2`).
- **`build.rs` / proc-macros**: None.

## 2. Baseline Quantitative Metrics

### Code Volume (`tokei`)

- **Total tracked files analyzed**: 32 files, 3,157 lines (2,369 code, 502 comments, 286 blanks)
- **Bash/Shell**: 3 files (`mk` 1,488 LOC; `tests/gate_selftest.sh` 580 LOC; `scripts/adopt.sh` 198 LOC) = **2,266 lines** (71.8% of total repo)
- **Rust**: 4 files (`crates/sample-lib/src/lib.rs` 25, `crates/sample-lib/tests/mutant_kill_example.rs` 12, `crates/sample-bin/src/main.rs` 9, `crates/sample-bin/tests/cli.rs` 21) = **67 lines**
- **TOML**: 9 files = 219 lines; **JSON**: 2 files = 67 lines; **Markdown**: 14 files = 540 lines

### Complexity & Size Hotspots

| File / Function | Location | Size (LOC) | Issue |
|---|---|---|---|
| `mk` (whole file) | `mk:1-1488` | 1,488 | Monolithic god script mixing 7 distinct architectural layers |
| Main dispatch `case "$cmd"` | `mk:901-1488` | 588 | 45+ inline command handlers mixed with control flow |
| `run_mutants()` | `mk:561-728` | 168 | God function mixing CLI parsing, config parsing, CPU budgeting, `TMPDIR`, lockdir, and watchdog |
| `affected_packages()` | `mk:173-276` | 104 | Shell wrapper embedding a 95-line inline Python graph traversal script |
| `mutants-plan` case arm | `mk:1306-1406` | 101 | Inline arg parser, scoping, diff setup, shard math, and Python JSON formatter |
| `tests/gate_selftest.sh` (whole file) | `tests/gate_selftest.sh:1-580` | 580 | Single sequential script with global mutable state and zero unit-level runner tests |
| `changed_rust_packages()` | `mk:129-171` | 43 | Shell wrapper embedding a 34-line inline Python path mapper |
| `run_tier()` | `mk:844-885` | 42 | Tier loop orchestrator |
| `ratchet` case arm | `mk:1070-1109` | 40 | Inline numeric validation, git merge-base diffing, and awk lint-allow counting |

### Build, Binary, Hygiene & Test Baseline

- **Clippy (`cargo clippy --all-targets --all-features -- -W clippy::cognitive_complexity`)**: Clean (0 warnings).
- **Unused dependencies (`cargo machete`)**: Clean (0 unused).
- **Release build time (`cargo clean -p sample-lib -p sample-bin && cargo build --workspace --release --timings`)**: `0.45s`.
- **`sample-bin` release binary size**: `435,872` bytes on disk (`cargo bloat --release -p sample-bin`: `213.5 KiB` `.text` section, `460.7 KiB` reported file size, top symbols all `std::backtrace_rs::symbolize::gimli` / DWARF unwinding).
- **`./mk ci-fast` wall time**: `22.81s` (`shell` static analysis alone takes `11s`).
- **Runner unit/characterization tests**: `0` (all coverage relied on slow full-integration `gate_selftest.sh`).

## 3. Ranked Architectural Smells (Impact × Effort)

| ID | Impact | Effort | Location | Finding |
|---|---|---|---|---|
| `F-01` | Critical | High | `mk:1-1488`, `mk:901-1488` | **God-file monolith & 588-LOC dispatcher**: `mk` mixes pure domain logic (gate catalog, workspace graph, shard math), tool installation, mutation resource watchdog, gate execution, and CLI routing in one file. |
| `F-02` | Critical | Medium | `mk:561-728` | **168-LOC `run_mutants()` god function**: Interleaves CLI argument parsing (`--in-place`, `--gitignore`, `--jobserver-tasks`, `--config`), `.cargo/mutants.toml` inspection, CPU/thread budgeting, `TMPDIR` selection, starvation checks, atomic `mkdir` lockdir acquisition, and `set -m` process-group watchdog loops. |
| `F-03` | High | Medium | `mk:77,84,114,137,181,1157,1254,1342,1469`, `scripts/adopt.sh:129,177,190` | **Duplicated inline Python & fragile JSON regex parsing**: 4 inline `python3 -c '...'` heredocs repeat `cargo metadata` loading/walking while 9 shell call sites parse `cargo metadata` JSON via `grep -o`/`cut`/`sed` regexes (`"kind":\[`, `"manifest_path":"[^"]*"`, `"publish":null`, `"license":"[^"]*"`, `"version":"0\.`). |
| `F-04` | High | Medium | `tests/gate_selftest.sh:1-580` | **Monolithic test script & zero unit tests**: 580 lines mixing assertion harness, CI gate injection, mutation tests, nightly injection, and `scripts/adopt.sh` fixture suites; 6+ duplicated `if/else/failed=1` check blocks (`gate_selftest.sh:244-251,370-377,383-390,406-413,424-446`); no fast unit tests for pure logic. |
| `F-05` | High | Low | `mk:1306-1406` | **101-LOC inline `mutants-plan` arm**: Embeds flag parsing, diff generation, scoping loops, shard arithmetic, and an inline Python JSON serializer inside the main `case` block. |
| `F-06` | Medium | Low | `mk:424-463`, `mk:1219-1227,1426-1430`, `mk:1409-1424`, `mk:959-998,1275-1305`, `mk:1450-1465` | **Copy-pasted logic across handlers**: `install_tombi` & `install_shellcheck` duplicate GitHub tarball download/extract/seed/verify; `echoes-baseline` & `coverage-baseline` duplicate `mk.local` key upserts; `coverage` & `coverage-baseline` duplicate `cargo-nextest` detection; `check-changed` & `test-changed` duplicate `affected_packages` scoping; `ci-nightly` & `ci-nightly-checks` duplicate `idle_scheduled_nightly` branching; `git diff` + `git ls-files` is repeated 3 times. |
| `F-07` | Medium | Low | `scripts/adopt.sh:1-198` | **Imperative script with `sh -c` hacks**: Top-level procedural script relies on `# shellcheck disable=SC2016` and 4 `act ... sh -c '...'` wrappers (`adopt.sh:105,107,158-169,175`) instead of named functions and phases, plus 3 regex JSON parsers on `cargo metadata`. |
| `F-08` | Medium | Low | `Cargo.toml`, `crates/sample-bin/Cargo.toml:11`, `crates/sample-lib/src/lib.rs`, `CONTRIBUTING.md:13` | **Workspace Rust hygiene & stale doc drift**: `sample-bin` specifies `sample-lib` path/version inline instead of `[workspace.dependencies]`; `sample-lib` lacks `no_std` support despite having zero `std` imports; root `Cargo.toml` omits `[profile.release]` tuning (`sample-bin` is 435 KB for a 9-line binary); `CONTRIBUTING.md:13` still mentions `MSRV 1.85` instead of `1.100.0`. |
