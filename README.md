[![CI Quality Gate](https://github.com/Adafede/rusti-graben/actions/workflows/ci.yml/badge.svg)](https://github.com/Adafede/rusti-graben/actions/workflows/ci.yml)
[![Template Selftest](https://github.com/Adafede/rusti-graben/actions/workflows/selftest.yml/badge.svg)](https://github.com/Adafede/rusti-graben/actions/workflows/selftest.yml)

# `rusti-graben`

> A strict, zero-drift quality-hygiene template and migration framework for Rust repositories.

- **One entrypoint.** `./mk <task>` runs every gate; CI calls the same tasks, so local and CI cannot disagree.
- **Fast inner loop.** `./mk check`, `./mk fix`, `./mk test-fast`, and `./mk watch` give quick local feedback before running `./mk ci`.
- **Every gate blocks.** A gate skips only when it cannot apply, and says why. A missing tool, or one at another version than [`mk.versions`](./mk.versions), fails.
- **Every gate is proven.** `./mk selftest` injects one violation per gate and checks that the gate fails because of it.

## Quickstart

**New repository:** "Use this template" on GitHub, replace the sample crates in `crates/`, then:

```bash
./mk setup       # pinned toolchains and tools (needs cargo-binstall)
./mk check       # fast inner loop: fmt + tombi + typos + clippy
./mk test-fast   # unit + integration tests (no doctests)
./mk ci-fast     # local pre-push gate (change-aware; skips mutants-diff & network audit)
./mk ci          # full blocking PR gate suite
```

**Existing repository** (workspace or single crate):

```bash
scripts/adopt.sh path/to/repo             # dry run
DRY_RUN=0 scripts/adopt.sh path/to/repo   # apply
```

Re-run `scripts/adopt.sh` at any time to sync the standard runner (`mk`, `mk.versions`, `.github/actions/setup/action.yml`). Repository-specific gates, tools, and overrides live in `mk.local`, which `adopt.sh` never overwrites.

## Gate Table (Blocking vs. Nightly vs. Inner Loop)

| Task | Tier | Tool | Policy |
|---|---|---|---|
| `./mk check` | Inner loop | rustfmt, tombi, typos, clippy | Fast pre-test verification (<10s) |
| `./mk fix` | Inner loop | rustfmt, tombi, typos, clippy `--fix` | Deterministic auto-remediation |
| `./mk test-fast` | Inner loop | cargo-nextest / cargo test | Unit + integration tests (no doctests) |
| `./mk watch` | Inner loop | bacon / cargo-watch | Continuous background feedback |
| `./mk ci-fast` | Pre-push (`prek`) | All blocking gates except `mutants-diff` & `audit` | Fast local pre-push verification (skips Rust compilation gates when a diff touches only standalone docs or workflow/tool configs) |
| `tools` | Blocking (`./mk ci`) | `mk.versions` | Exact pinned tool version verification |
| `actions` | Blocking (`./mk ci`) | zizmor | SHA-pinned Actions & workflow security audit |
| `shell` | Blocking (`./mk ci`) | shellcheck | Shell script lint (`--severity=style`) |
| `commits` | Blocking (`./mk ci`) | `./mk` regex | Conventional Commits on branch / `commit-msg` |
| `ratchet` | Blocking (`./mk ci`) | `./mk` vs. base branch | Rejects lowered coverage floor, raised echoes max, or new `Cargo.toml` lint allows |
| `fmt` | Blocking (`./mk ci`) | rustfmt | Rust formatting check |
| `tombi` (`toml`) | Blocking (`./mk ci`) | tombi | TOML formatting + schema lint |
| `typos` | Blocking (`./mk ci`) | typos-cli | Source & documentation spell check |
| `lint` | Blocking (`./mk ci`) | clippy `-D warnings` | Workspace pedantic/nursery/restriction + rustc lints |
| `lints-inherit` | Blocking (`./mk ci`) | `./mk` | Every crate inherits `[workspace.lints]` |
| `test` | Blocking (`./mk ci`) | cargo test | Unit, integration, doctests, and README examples |
| `doc` | Blocking (`./mk ci`) | rustdoc `-D warnings` | Intra-doc links, private items, rustdoc lints |
| `deny` | Blocking (`./mk ci`) | cargo-deny | Licenses, advisories, duplicate crate versions, sources |
| `audit` | Blocking (`./mk ci`) | cargo-audit | RustSec vulnerability & unmaintained crate check |
| `machete` (`unused-deps`) | Blocking (`./mk ci`) | cargo-machete | Unused dependency detection |
| `msrv` | Blocking (`./mk ci`) | `cargo +<msrv> check` | Verified build on declared `rust-version` |
| `echoes` (`duplication`, `dup`) | Blocking (`./mk ci`) | cargo-echoes | 0 exact duplicates; approximate & dependency reuse ratcheted |
| `refquiem` (`stale-refs`) | Blocking (`./mk ci`) | cargo-refquiem | No stale mentions of deleted or signature-changed items |
| `semver` | Blocking (`./mk ci`) | cargo-semver-checks | No breaking API changes since last `v*` tag (1.0+ libs) |
| `wasm` | Blocking (`./mk ci`) | `cargo check --target wasm32-unknown-unknown` | Verified when `wasm32` target is declared |
| `mutants-diff` | Blocking (`./mk ci`) | cargo-mutants `--in-diff` | 0 surviving mutants in Rust code changed on the branch |
| `mutants` | Nightly (`./mk ci-nightly`) | cargo-mutants | Bounded full-workspace mutation testing |
| `coverage` (`cov`) | Nightly (`./mk ci-nightly`) | cargo-llvm-cov | Line coverage ≥ `COVERAGE_FAIL_UNDER_LINES` |
| `powerset` (`feature-powerset`, `hack`) | Nightly (`./mk ci-nightly`) | cargo-hack | `--feature-powerset --no-dev-deps check` |
| `miri` | Nightly (`./mk ci-nightly`) | cargo miri | Undefined behavior detection in tests |
| `outdated` | Nightly (`./mk ci-nightly`) | cargo-outdated | Root dependency freshness |

See [`docs/GATES.md`](./docs/GATES.md) for the full specification of each gate and the violation `./mk selftest` injects.

## Ratcheting a Legacy Repository

When adopting `rusti-graben` in an existing codebase, **never weaken a gate globally**. Instead, record legacy debt explicitly and let `./mk ratchet` ensure counts only move toward zero:

1. **Adopt & baseline**:
   ```bash
   DRY_RUN=0 path/to/rusti-graben/scripts/adopt.sh .
   ./mk setup
   ./mk coverage-baseline   # sets COVERAGE_FAIL_UNDER_LINES in mk.local
   ./mk echoes-baseline     # sets ECHOES_MAX_APPROXIMATE and ECHOES_MAX_REUSE in mk.local
   ```
   Optional per-gate adoption flags (`ADOPT_MUTANTS=0`, `ADOPT_ECHOES=0`, `ADOPT_REFQUIEM=0`, `ADOPT_WORKFLOWS=0`) allow staging config files progressively.
2. **Scope legacy lints**: Use `#[expect(lint, reason = "...")]` at specific sites, or record legacy workspace-wide `# Ratchet` allow lines in `Cargo.toml` (`./mk ratchet` prevents adding new `"allow"` lines and encourages retiring existing ones).
3. **Track all exceptions in [`docs/DEBT.md`](./docs/DEBT.md)**: Document every `deny.toml` duplicate skip, `.cargo/mutants.toml` exclusion, `// echoes: allow`, and `// refquiem: allow(name)` with its reason and removal condition. See [`docs/ADOPTING.md`](./docs/ADOPTING.md).

## Requirements & Known Limitations

- `./mk setup` requires `rustup`, [`cargo-binstall`](https://github.com/cargo-bins/cargo-binstall), and network access to install pinned binaries and the nightly toolchain from [`mk.versions`](./mk.versions).
- `audit` and `outdated` query the RustSec advisory database and `crates.io` index over the network (`./mk ci-fast` omits `audit` for offline pre-push runs).
- `miri` cannot spawn subprocesses or open sockets; restrict crates via `MIRI_PACKAGES` in [`mk.local`](./mk.local) or mark process-spawning integration tests `#[cfg_attr(miri, ignore = "...")]`.
- `mutants` and `mutants-diff` require at least `MUTANTS_MIN_FREE_DISK_GB` (default `10` GB) free disk and `MUTANTS_MIN_FREE_MEM_PCT` (default `15%`) free memory; `LOCAL_OVERRIDES` cannot replace `mutants` or `mutants-diff` so the resource watchdog stays active.
- `semver` runs only on `1.0.0+` library crates after an earlier `v*` git tag exists; `wasm` runs only when `wasm32` is declared outside comments in `rust-toolchain.toml` or `Cargo.toml`.

## Documentation & Community

- [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — Runner and template architecture
- [`docs/ADOPTING.md`](./docs/ADOPTING.md) — Adoption and legacy ratchet guide
- [`docs/GATES.md`](./docs/GATES.md) — Gate reference and selftest matrix
- [`docs/DEBT.md`](./docs/DEBT.md) — Technical debt and exception ledger
- [`docs/adr/0001-inner-loop-and-ratchets.md`](./docs/adr/0001-inner-loop-and-ratchets.md) — Architecture decision record for inner-loop tasks and ratchets
- [`CONTRIBUTING.md`](./CONTRIBUTING.md), [`SECURITY.md`](./SECURITY.md), [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md)

## License

Licensed under the GNU Affero General Public License v3.0 or later (`AGPL-3.0-or-later`). See [`LICENSE`](./LICENSE). Repositories adopting the gates keep their own license: `adopt.sh` sets it in their `deny.toml`.
