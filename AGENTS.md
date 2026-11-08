# AGENTS.md

`rusti-graben` is the zero-drift Rust quality-hygiene template and adoption runner. Every repository adopting it shares a single entrypoint (`./mk`) so local development, pre-push hooks, and CI run identical checks at pinned tool versions.

## Architecture Map

| Path | Responsibility | Key Entry Points |
|---|---|---|
| `mk` | Standard task runner (synced across repos; never edit in adopted repos) | `./mk ci`, `./mk check`, `./mk fix`, `./mk test-fast` |
| `mk.versions` | Single source of truth for pinned tool and nightly toolchain versions | `CARGO_TOOLS_CI`, `CARGO_TOOLS_NIGHTLY`, `TOMBI_VERSION`, `SHELLCHECK_VERSION` |
| `mk.local` | Repository-specific gate extensions, overrides, package scopes, and ratchets | `LOCAL_CI_GATES`, `LOCAL_OVERRIDES`, `COVERAGE_FAIL_UNDER_LINES`, `ECHOES_MAX_*` |
| `scripts/adopt.sh` | Idempotent dry-run/apply script to adopt or sync `rusti-graben` in a repo | `scripts/adopt.sh <repo>`, `DRY_RUN=0 scripts/adopt.sh <repo>` |
| `tests/gate_selftest.sh` | Injects one violation per gate into a scratch repo and asserts failure | `./mk selftest` |
| `crates/sample-lib` | Sample library crate demonstrating workspace lints, doctests, and README sync | `sample_lib::add` |
| `crates/sample-bin` | Sample CLI binary crate demonstrating integration tests and lint exceptions | `main` |

## Commands

```bash
./mk help                      # Show tiers, gate descriptions, and task aliases
./mk setup                     # Install pinned toolchains and tools (once)
./mk check                     # Fast inner loop (<10s): fmt, tombi, typos, clippy
./mk fix                       # Auto-fix formatting, TOML, typos, and clippy
./mk test-fast                 # Unit + integration tests (nextest / cargo test, no doctests)
./mk test-fast -E 'test(name)' # Run one targeted test via nextest (or `-- name` with cargo test)
./mk test                      # Full test suite including doctests and README examples
./mk watch                     # Continuous feedback via bacon / cargo-watch
./mk mutants-diff              # Mutation testing on branch diff against base
./mk ci-fast                   # Local pre-push gate (skips mutants-diff & network audit; change-aware)
./mk ci                        # All blocking PR gates (must pass before finishing)
./mk ci-nightly                # Nightly gates: mutants, coverage (cov), powerset (hack), miri, outdated
./mk selftest                  # Template-only: prove every gate fails on an injected violation
```

Set `NO_COLOR=1` or `CI=1` for machine-readable, uncolored output.

## Definition of Done

1. `./mk ci` passes locally with zero errors.
2. Every new or modified code path has deterministic tests that kill its mutants (`./mk mutants-diff`).
3. Public items have rustdoc comments with compiling examples where applicable (`./mk doc`).
4. All commits on the branch follow Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`; verified by `./mk commits`).

## Conventions & Hard Prohibitions

- **Single entrypoint**: Always invoke `./mk <task>`. Never edit `mk`, `mk.versions`, or `.github/actions/setup/action.yml` in an adopted repo; put repo-specific settings in `mk.local`.
- **Never weaken a gate**:
  - No `unsafe` (`unsafe_code = "forbid"`).
  - No `unwrap()`, `expect()`, `panic!()`, `todo!()`, or `dbg!()` outside tests.
  - No bare `#[allow(...)]`; use `#[expect(lint, reason = "...")]` so the attribute fails once no longer needed.
  - Record any unavoidable legacy exception in [`docs/DEBT.md`](./docs/DEBT.md) alongside its inline marker (`// echoes: allow`, `// refquiem: allow(name)`, `.cargo/mutants.toml` comment, or `deny.toml` `skip` reason).
- **Deterministic tests**: No live network calls, wall-clock dependence, or unseeded randomness in unit/integration tests.
