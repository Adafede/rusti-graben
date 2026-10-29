# HYGIENE-AUDIT

Every gate below fails the build. A gate is skipped only when it cannot apply,
and says why. A missing tool, or one at a version other than `mk.versions`, is a
failure, not a skip. `./mk selftest` injects one violation per gate and asserts
the gate fails for that reason (run on every PR).

## `./mk ci` (blocking, every PR and push)

| Gate | Tool | Catches | Selftest violation |
|---|---|---|---|
| tools | `mk.versions` | Local/CI tool drift | Pinned version changed |
| actions | zizmor (offline), `.github/` | Unpinned actions, credential leaks, injection in workflows and the shared setup action | Action pinned to a tag |
| shell | shellcheck | Quoting, word-splitting and portability bugs in `mk` and every tracked script | Unquoted `$1` |
| commits | `./mk` (Conventional Commits regex) | Commit subjects on the branch that break the convention (changelogs, release tooling) | `Update the library` |
| fmt | rustfmt | Unformatted Rust | Unformatted function |
| tombi | tombi format + lint | Unformatted or schema-invalid TOML, unreadable tombi config | Unformatted table |
| typos | typos | Misspellings in code and docs | Misspelled comment |
| lint | clippy `-D warnings` + workspace lints | unwrap, panic, todo, dbg, unsafe, bare `#[allow]` (use `#[expect(.., reason)]`), pedantic/nursery, and a curated restriction set (printing in libraries, indexing, `std` where `core` works, assert without message, ...) | `unwrap()`, `unsafe {}`, `#[allow]`, `println!` in a lib |
| lints-inherit | `./mk` | Crates that do not opt into `[lints] workspace = true` | `[lints]` removed |
| test | cargo test | Regressions, doctests, crate READMEs (included as crate docs) | Failing assertion, failing README example |
| doc | rustdoc `-D warnings`, private items, rustdoc lints | Broken or private intra-doc links, unbalanced backticks, bare URLs, invalid code blocks | Unresolved link, stray backtick |
| deny | cargo-deny | Licenses outside the allow-list, advisories, duplicate versions, wildcards, unknown sources | GPL crate |
| audit | cargo-audit `--deny warnings` | RUSTSEC advisories, unmaintained and yanked crates | Vulnerable `smallvec` in lockfile |
| machete | cargo-machete | Unused dependencies | Unused `itoa` |
| msrv | `cargo +<rust-version> check` | Code that does not build on the declared MSRV | `is_multiple_of` (1.87) |
| echoes | echoes (`cargo echoes`, `.echoes.toml`) | Duplicated doctests, functions and code blocks across the workspace; local code re-implementing an API already exported anywhere in the transitive dependency graph (dev, build, optional, all features, latest releases) | Copy-pasted function; re-implemented dependency fn; weakened config |
| refquiem | refquiem (`cargo refquiem`) | Docs and comments mentioning items deleted in git history | README naming a deleted fn |
| semver | cargo-semver-checks vs. the last `v*` tag | Breaking API change without a major bump (skips: no lib, or no earlier tag) | Public fn removed after a tag |
| wasm | `cargo check --target wasm32-unknown-unknown` | Code that does not build for wasm (skips: no wasm32 target declared) | `std::os::unix` import |
| mutants-diff | cargo-mutants `--in-diff` vs. the base branch | New or changed code no test checks, caught on the PR instead of nightly | Untested fn added on the branch |

`./mk selftest` also runs `scripts/adopt.sh` against a scratch legacy crate: dry run writes nothing, apply copies every config, existing files are kept, and a second run changes nothing.

## `./mk ci-nightly`

| Gate | Tool | Catches |
|---|---|---|
| mutants | cargo-mutants (`mutants.toml`) | Code whose behavior no test checks; zero missed mutants |
| coverage | cargo-llvm-cov `--fail-under-lines` | Line coverage below `COVERAGE_FAIL_UNDER_LINES` (ratchet, only goes up) |
| powerset | cargo-hack `--feature-powerset` | Feature combinations that do not compile |
| miri | miri on the pinned nightly | Undefined behavior, mostly in dependencies |
| outdated | cargo-outdated `--exit-code 1` | Direct dependencies behind their latest release |

## `./mk ci-release` (on `v*` tags)

`./mk ci` (which includes semver against the previous tag), then `cargo publish --workspace --dry-run`.

## Tool provenance

`echoes` and `refquiem` are published on crates.io under those crate names
(binaries `cargo-echoes` / `cargo-refquiem`, by Luca Cappelletti, MIT). The
`cargo-echoes` / `cargo-refquiem` crate names do not exist, which is why earlier
CI installs silently failed.
