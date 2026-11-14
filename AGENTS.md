# AGENTS.md

`rusti-graben` enforces identical local, hook, and CI checks through one shell entrypoint (`./mk`) at pinned tool versions.

## Architecture Map

| Path | Responsibility | Key Entry Points |
|---|---|---|
| `mk` | Standard task runner (synced across repos; never edit in adopted repos) | `./mk ci`, `./mk check`, `./mk fix`, `./mk test-fast` |
| `mk.versions` | Pinned tool and nightly toolchain versions | `CARGO_TOOLS_CI`, `CARGO_TOOLS_NIGHTLY`, `TOMBI_VERSION`, `SHELLCHECK_VERSION` |
| `mk.local` | Repo-specific gates (`task_<name>()` / cargo-make), overrides, scopes, ratchets | `LOCAL_CI_GATES`, `LOCAL_OVERRIDES`, `COVERAGE_FAIL_UNDER_LINES`, `ECHOES_MAX_*` |
| `scripts/adopt.sh` | Template-only idempotent adoption and sync runner (`DRY_RUN=0`) | `scripts/adopt.sh <repo>` |
| `tests/gate_selftest.sh` | Template-only gate failure-injection and `adopt.sh` test suite | `./mk selftest` |
| `crates/sample-lib` | Sample library exercising workspace lints, doctests, README sync | `sample_lib::add` |
| `crates/sample-bin` | Sample CLI binary exercising integration tests and `#[expect]` exceptions | `main` |

## Commands (Cheapest First)

```bash
./mk help                      # Show tiers, gate descriptions, and task aliases
./mk setup [ci|nightly|all]    # Install pinned toolchains and tools (needs cargo-binstall)
./mk check                     # Fast inner loop: fmt, tombi, typos, clippy
./mk fix                       # Auto-fix formatting, TOML, typos, and clippy
./mk test-fast                 # Unit + integration tests (nextest / cargo test, no doctests)
./mk test-fast -E 'test(name)' # Single targeted test via nextest (or `-- name` with cargo test)
./mk test                      # Full test suite including doctests and README examples
./mk watch                     # Continuous feedback via bacon / cargo-watch
./mk mutants-diff              # Mutation testing on branch/untracked diff against base
./mk ci-fast                   # Local pre-push gate (omits mutants-diff & network audit; change-aware)
./mk ci                        # Full blocking PR gate suite (must pass before finishing)
./mk ci-nightly                # Nightly gates: mutants, coverage (cov), powerset (hack), miri, outdated
./mk selftest                  # Template-only: prove every gate fails on an injected violation
```

Set `NO_COLOR=1` or `CI=1` for plain, uncolored output.

## Definition of Done

1. `./mk ci` passes locally with zero errors.
2. Every new or modified code path has deterministic tests that kill its mutants (`./mk mutants-diff`).
3. Public items have rustdoc comments with compiling examples where applicable (`./mk doc`).
4. Branch commit subjects follow Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `ci:`, `chore:`; verified by `./mk commits`).

## Conventions & Hard Prohibitions

- **Single entrypoint**: Always invoke `./mk <task>`. Never edit `mk`, `mk.versions`, or `.github/actions/setup/action.yml` in an adopted repo; put repo-specific settings in `mk.local`.
- **Never weaken a gate**:
  - No `unsafe` (`unsafe_code = "forbid"`).
  - No `unwrap()`, `expect()`, `panic!()`, `todo!()`, or `dbg!()` outside tests.
  - No bare `#[allow(...)]`; use `#[expect(lint, reason = "...")]` so the attribute fails once obsolete.
  - Record persistent exceptions in [`docs/DEBT.md`](./docs/DEBT.md) alongside inline markers (`// echoes: allow`, `// refquiem: allow(name)`, `.cargo/mutants.toml` comment, or `deny.toml` `skip` reason).
- **Deterministic tests**: No live network calls, wall-clock dependence, or unseeded randomness in unit/integration tests.
- **Human docs boundary**: Never link agent files (`AGENTS.md`, `CLAUDE.md`, `SKILL.md`, `.agents/`) from human-facing docs (`README.md`, `docs/`, `CONTRIBUTING.md`, `.github/`); see [`docs/GATES.md`](./docs/GATES.md) and [`docs/ADOPTING.md`](./docs/ADOPTING.md).
- Template-only playbook, architecture invariants, and audit pitfalls: [`.agents/PLAYBOOK.md`](./.agents/PLAYBOOK.md).
