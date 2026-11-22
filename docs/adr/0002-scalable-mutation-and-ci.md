# ADR 0002: Scalable Mutation Testing, Package-Graph Scoping, and Sharded CI

- **Status:** Accepted
- **Date:** 2026-11-22

## Context

As adopted workspaces grew in crate count, asset size, and lint strictness, full-tree copies, single-job mutation testing, uncached CI tool installs, and workspace-wide builds turned inner loops and PR/nightly CI into compute bottlenecks:

1. `cargo-mutants` copied gitignored directories (`target/`, fetched assets, local graph caches) into scratch directories and compiled each mutant from a fresh target directory when `CARGO_TARGET_DIR` was unset.
2. `mutants-diff` ran `cargo-mutants` over the entire `MUTANTS_PACKAGES` set even when a branch touched only an excluded crate, and rebuilt every workspace crate's feature unification baseline.
3. Without `cap_lints = true`, denied lints such as `dead_code = "deny"` caused real mutants to fail compilation as `Unviable` instead of being tested against the test suite.
4. Monolithic `ci` and `ci-nightly` CI jobs serialized non-mutation checks behind mutation testing, re-downloaded all pinned tools on every run, and could not shard `mutants-diff` or nightly `mutants` horizontally across runners.

## Decision

1. **Workspace package-graph helpers (`changed_rust_packages`, `affected_packages`)**: Resolve changed `*.rs` files and transitive workspace reverse-dependents via `cargo metadata --no-deps --format-version 1` (falling back to the full workspace whenever root manifests, lockfiles, toolchain, or runner configs change).
   - `mutants-diff` intersects `changed_rust_packages` with `MUTANTS_PACKAGES`, skipping immediately (`<1s`) when empty and scoping `--package=` flags otherwise.
   - `mutants-affected` mutates `affected_packages` intersected with `MUTANTS_PACKAGES`.
   - `check-changed` and `test-changed` scope `clippy` and `cargo-nextest` to `affected_packages`; `check`, `lint`, and `test-fast` also accept explicit `-p` / `--package` flags.
2. **Accelerated bounded `run_mutants`**:
   - Default `--gitignore=true` unless explicitly overridden or configured in `.cargo/mutants.toml`.
   - Pass `--jobserver-tasks` capped to the runner's CPU budget (`threads` when `--in-place`, `jobs * threads` otherwise).
   - Support `--in-place` (`MUTANTS_IN_PLACE=1`) for disposable CI runners, omitting `--jobs` because `cargo-mutants` 27.x rejects `--jobs` alongside `--in-place`.
   - When running locally out-of-place with `jobs == 1`, reuse a persistent `CARGO_TARGET_DIR` (`.../target/mutants`, never nested) guarded by an atomic `mkdir` lockdir; when `jobs > 1`, unset `CARGO_TARGET_DIR` so parallel workers keep isolated scratch target directories.
   - Enable `cap_lints = true` in `.cargo/mutants.toml` so denied lints do not mask real mutants as `Unviable`.
   - Keep `CARGO_PROFILE_DEV_DEBUG=0` and `CARGO_PROFILE_TEST_DEBUG=0` (and seed `[profile.dev.package."*"]` / `[profile.test.package."*"]` `debug = false` in `Cargo.toml`), and default `MUTANTS_INCREMENTAL=1` (forced to `0` when `RUSTC_WRAPPER` contains `sccache`).
3. **Faster non-mutation gates**:
   - Run `./mk test` with pinned `cargo-nextest` (using `--profile ci` when `CI` is set and `[profile.ci]` exists) followed by `cargo test --workspace --doc --all-features --locked`.
   - Run `./mk coverage` and `./mk coverage-baseline` via `cargo llvm-cov nextest` when `cargo-nextest` is available.
   - Skip redundant `msrv` checks inside tier runs when `lint` has already passed and `rust-version` matches the active `rustc` version exactly (`major.minor.patch`); standalone `./mk msrv` and older `rust-version` pins always execute.
4. **Decoupled and sharded CI**:
   - Cache `MK_TOOLS_DIR` (`~/.cargo/mk-tools`) in `.github/actions/setup/action.yml` using `actions/cache` (and `actions/cache/restore` when `save-cache` is disabled in parallel matrix shards).
   - Split `.github/workflows/ci.yml` into `ci-core` (`./mk ci-core`), `mutants-plan` (`./mk mutants-plan --mode diff`), and dynamic `mutants-diff` shards (`1..=4`, target 150 mutants/shard).
   - Split `.github/workflows/nightly.yml` into `nightly-checks` (`./mk ci-nightly-checks`), `mutants-plan`, and `mutants-shard` (`1..=8`, target 250 mutants/shard), running `affected` on Mon–Sat and `full` on Sunday or manual dispatch.

## Empirical Benchmark (`lotus-explore-rs`)

Measured on `lotus-explore-rs` before finalizing the `MUTANTS_INCREMENTAL` default:

- **Tree copy (`--gitignore=false` vs `--gitignore=true`)**: `485,074,780` bytes (2,479 files) reduced to `5,361,635` bytes (669 files) — a 98.9% (~90x) copy reduction.
- **Excluded-crate `mutants-diff`**: `2.34s` before -> `0.71s` after (`[skip] mutants-diff: no Rust changes in mutation scope against origin/main`).
- **`mutants-diff` baseline & warm cache (6 mutants in `lotus-model/src/percent.rs`)**: `28.95s` before (`8s` build + `1s` test) -> `37.63s` after cold (`16s` build + `1s` test) -> `27.17s` after warm (`1s` build + `1s` test).
- **`MUTANTS_INCREMENTAL=0` vs `1` (19 mutants in `lotus-query/src/export.rs`)**:
  - `MUTANTS_INCREMENTAL=0`: cold `124.42s` (`59.2 MB` target), warm `100.27s` (`59.2 MB` target).
  - `MUTANTS_INCREMENTAL=1`: cold `89.72s` (-27.9%, `97.9 MB` target), warm `91.78s` (-8.5%, `97.9 MB` target).
  - Decision: Keep `MUTANTS_INCREMENTAL=1` as the default (disabling automatically under `sccache`) because it cuts multi-module mutant build times meaningfully at only `+38.7 MB` disk footprint while remaining under the memory/disk watchdog.
- **`cap_lints = false` vs `true` (`lotus-query`, `--check` across 410 mutants)**: `68` unviable / `342` viable (83.4%) before -> `29` unviable / `381` viable (92.9%) after, unmasking `+39` real mutants.

## Consequences

- Local iteration and CI workflows share the exact same `./mk` entrypoint with dramatically lower wall-clock latency and redundant builds.
- Repositories with strict lints such as `dead_code = "deny"` gain true mutation test coverage instead of silently classifying deleted-call mutants as `Unviable`.
