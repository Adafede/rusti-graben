# Gates

Every gate below fails the build. A gate is skipped only when it cannot apply,
and says why. A missing tool, or one at a version other than `mk.versions`, is a
failure, not a skip. `./mk selftest` injects one violation per gate and asserts
the gate fails for that reason (template CI, every PR).

## `./mk ci` (blocking, every PR and push), `./mk ci-core`, & `./mk ci-fast` (local `pre-push`)

`./mk ci` runs all 21 blocking gates below. On GitHub Actions, `.github/workflows/ci.yml` splits `./mk ci` into `./mk ci-core` (the 20 non-mutation gates), `./mk mutants-plan --mode diff`, and sharded `MUTANTS_IN_PLACE=1 ./mk mutants-diff` jobs (`1..=4` shards, skipped when `mutants == 0`). `./mk ci-fast` (used by `prek` on `pre-push`) runs the same local checks with `test-fast` (`cargo nextest`, no doctests) while deferring `mutants-diff` and network `audit` to pull request CI. When a branch diff against the base branch touches only standalone Markdown (excluding single-crate root `README.md` or any file referenced via `include_str!`/`include_bytes!` in `*.rs`), `.github/` files, or non-Rust hygiene config files, `./mk ci`, `./mk ci-core`, and `./mk ci-fast` skip the Rust compilation gates (`fmt`, `lint`, `lints-inherit`, `test`, `test-fast`, `doc`, `deny`, `machete`, `msrv`, `echoes`, `semver`, `wasm`, `mutants-diff`) while still enforcing `tools`, `actions`, `shell`, `commits`, `ratchet`, `tombi`, `typos`, and `refquiem`.

| Gate (alias) | Tool | Catches | Selftest violation |
|---|---|---|---|
| tools | `mk.versions` | Local/CI tool drift | Pinned version changed |
| actions | zizmor (offline), `.github/` | Unpinned actions, credential leaks, injection in workflows and the shared setup action | Action pinned to a tag |
| shell | shellcheck | Quoting, word-splitting and portability bugs in `mk` and every tracked script | Unquoted `$1` |
| commits | `./mk` (Conventional Commits regex) | Commit subjects on the branch or in `commit-msg` that break the convention (changelogs, release tooling) | `Update the library` |
| ratchet | `./mk` vs. the base branch | A lowered `COVERAGE_FAIL_UNDER_LINES`, a raised `ECHOES_MAX_*`, an added `= "allow"` lint line in `Cargo.toml` | Floor lowered to 1; echoes maximum raised; new lint allow in `Cargo.toml` |
| fmt | rustfmt | Unformatted Rust | Unformatted function |
| tombi (`toml`) | tombi format + lint | Unformatted or schema-invalid TOML, unreadable tombi config | Unformatted table |
| typos | typos | Misspellings in code and docs | Misspelled comment |
| lint | clippy `-D warnings` + workspace lints | unwrap, panic, todo, dbg, unsafe, bare `#[allow]` (use `#[expect(.., reason)]`), pedantic/nursery, and a curated restriction set (printing in libraries, indexing, `std` where `core` works, assert without message, ...) | `unwrap()`, `unsafe {}`, `#[allow]`, `println!` in a lib |
| lints-inherit | `./mk` | Missing `[lints.{clippy,rust,rustdoc}]` tables, or workspace crates that do not opt into `[lints] workspace = true` | `[lints]` removed |
| test | `cargo nextest` + `cargo test --doc` | Regressions, doctests, crate READMEs (included as crate docs) | Failing assertion, failing README example |
| doc | rustdoc `-D warnings`, private items, rustdoc lints | Broken or private intra-doc links, unbalanced backticks, bare URLs, invalid code blocks | Unresolved link, stray backtick |
| deny | cargo-deny | Licenses outside the allow-list, advisories, duplicate versions, wildcards, unknown sources | GPL crate |
| audit | cargo-audit `--deny warnings` | RUSTSEC advisories, unmaintained and yanked crates | Vulnerable `smallvec` in lockfile |
| machete (`unused-deps`) | cargo-machete | Unused dependencies | Unused `itoa` |
| msrv | `cargo +<rust-version> check` | Code that does not build on the declared MSRV (skips inside tiers after `lint` passes on identical `rustc`) | `is_multiple_of` (1.87) |
| echoes (`duplication`, `dup`) | echoes (`cargo echoes`, `.echoes.toml`) | Duplicated doctests, functions and code blocks across the workspace; local code re-implementing an API a direct dependency already exports (dev, build, optional, all features, at the locked versions). Exact duplicates must be 0; approximate groups and reuse may not exceed the `ECHOES_MAX_*` ratchet in `mk.local` | Copy-pasted function; re-implemented dependency fn; weakened config |
| refquiem (`stale-refs`) | refquiem (`cargo refquiem`, `.refquiem.toml`) | Comments, doc comments, Markdown and string literals mentioning Rust items, dependencies, features, binaries, examples or serde names deleted in git history; on a branch, untouched text naming an item whose signature, fields, variants or const/static value changed; unused `refquiem: allow(...)` markers | Mention of a deleted fn; untouched mention of a fn whose signature changed; weakened config |
| semver | cargo-semver-checks vs. the last `v*` tag | Breaking API change without a major bump (skips: no lib, every crate pre-1.0 and so in development, or no earlier tag) | Public fn removed after `v1.0.0` |
| wasm | `cargo check --target wasm32-unknown-unknown` | Code that does not build for wasm (skips unless `rust-toolchain.toml` or `Cargo.toml` declares wasm32) | `std::os::unix` import |
| mutants-diff | cargo-mutants `--in-diff` vs. the base branch (touched `MUTANTS_PACKAGES` only) | New or changed code no test checks, caught on the PR instead of nightly; fast-skips when no package in mutation scope changed | Untested fn added on the branch; untracked `.rs` file; excluded-package fast-skip |

`./mk selftest` also runs `scripts/adopt.sh` against a scratch workspace and a single crate: a dry run writes nothing, apply copies every config and workflow, keeps existing files, adds lints, allows the repository's own license, and a second run changes nothing.

## `./mk ci-nightly` & `./mk ci-nightly-checks`

On scheduled runs (`GITHUB_EVENT_NAME=schedule`), if the repository has no commits in the last 24 hours, `./mk ci-nightly` and `./mk ci-nightly-checks` run only `audit` and `outdated` instead of re-running multi-hour mutation and Miri sweeps on unchanged code. On GitHub Actions, `.github/workflows/nightly.yml` runs `./mk ci-nightly-checks` in parallel with `./mk mutants-plan`, dispatching sharded `./mk mutants-affected` on Monday–Saturday and full `./mk mutants` (`1..=8` shards) on Sunday or manual dispatch.

| Gate (alias) | Tool | Catches | Selftest violation |
|---|---|---|---|
| mutants | cargo-mutants (`.cargo/mutants.toml`), `MUTANTS_PACKAGES` if set | Code whose behavior no test checks; zero missed mutants (`cap_lints = true` avoids masking via denied lints) | Untested fn; low free disk; `LOCAL_OVERRIDES=(mutants)` |
| mutants-affected | cargo-mutants on changed packages + reverse-dependents | Regressions in changed crates or downstream dependents without full-workspace sweep | Mutant in downstream crate broken by upstream change |
| coverage (`cov`) | `cargo llvm-cov nextest` `--fail-under-lines` | Line coverage below `COVERAGE_FAIL_UNDER_LINES` (ratchet, only goes up) | Untested fn dropping line coverage below floor |
| powerset (`feature-powerset`, `hack`) | cargo-hack `--feature-powerset --no-dev-deps check` | Feature combinations that do not compile | Type error behind optional feature |
| miri | miri on the pinned nightly, isolation disabled, `MIRI_PACKAGES` if set | Undefined behavior and memory leaks in unit, integration, and doc tests | Heap memory leak in unit test |
| outdated | cargo-outdated `--exit-code 1` | Direct dependencies behind their latest release | Outdated `itoa = "0.4"` dependency |

All mutation gates (`mutants`, `mutants-affected`, and `mutants-diff`) run through one bounded runner in `mk`, because an unbounded `cargo-mutants` run can wedge developer machines or exhaust a CI runner. It runs `MUTANTS_JOBS` mutants at once (1 locally, half the cores on CI) with `--jobserver-tasks` capped to match (`threads` for `MUTANTS_IN_PLACE=1` / `--in-place` where `--jobs` is omitted, `jobs * threads` otherwise), defaults `--gitignore=true`, reuses a persistent `CARGO_TARGET_DIR` (`.../target/mutants`) guarded by an atomic `mkdir` lockdir when `jobs == 1` (or isolated per-scratch target dirs when `jobs > 1`), disables debuginfo (`CARGO_PROFILE_DEV_DEBUG=0`, `CARGO_PROFILE_TEST_DEBUG=0`), defaults `MUTANTS_INCREMENTAL=1` (forced `0` under `sccache`), honors `cap_lints = true` and `test_tool = "nextest"` in `.cargo/mutants.toml`, runs at `nice 19`, and stops cleanly if available memory falls below `MUTANTS_MIN_FREE_MEM_PCT` (15) or free disk falls below `MUTANTS_MIN_FREE_DISK_GB` (10). `./mk mutants -p crate` runs one crate.

## `./mk ci-release` (on `v*` tags)

`./mk ci` (which includes semver against the previous tag), then `cargo publish --workspace --dry-run`.

## Tool provenance

`echoes` and `refquiem` are the crates.io names of `cargo echoes` and
`cargo refquiem` (Luca Cappelletti, MIT).

## Dependency updates

Dependabot updates Cargo dependencies and GitHub Actions digests (workflows and
the shared setup action). Renovate only updates what Dependabot cannot: the
tools in `mk.versions`, the `rust-toolchain.toml` pin and cargo-binstall. Both
wait 7 days after a release, and Dependabot commits use `chore(deps):` so they
pass `./mk commits`.
