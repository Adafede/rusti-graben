# Agent Playbook (`rusti-graben`)

Dense operational reference for coding agents working inside the `rusti-graben` template repository.

## Cheapest-First Verification Ladder

Run the cheapest check that proves your change before running full suites:

1. `./mk check` — static + lint loop (`fmt`, `tombi`, `typos`, `lint`).
2. `./mk test-fast -E 'test(<name>)'` — single test via `nextest` (or `-- <name>` via `cargo test`), then `./mk test-fast`.
3. `./mk mutants-diff` — mutation check on changed/untracked `.rs` files relative to base branch.
4. `./mk ci-fast` — local pre-push gate (omits `mutants-diff` and network `audit`; change-aware).
5. `./mk ci` — full blocking PR gate suite (`19` active checks + `3` conditional skips on this workspace).
6. `./mk selftest` — mandatory whenever editing `mk`, `mk.versions`, `mk.local`, `scripts/adopt.sh`, or `tests/gate_selftest.sh`.

Always set `NO_COLOR=1` (or `CI=1`) when reading output programmatically.

## Hard Invariants

1. **Zero-drift single entrypoint**: CI workflows (`.github/workflows/*.yml`) and hooks (`prek.toml`) invoke `./mk <task>`. Never bypass `./mk` with raw tool invocations when verifying deliverables.
2. **Standard vs. local split**: `mk`, `mk.versions`, and `.github/actions/setup/action.yml` stay byte-identical across adopted repos (`scripts/adopt.sh` syncs them). Put repo-specific settings and custom `LOCAL_*` gates below `mk.local`'s header. Wait before adding below `# Ratchet:` in template `mk.local`: `scripts/adopt.sh` runs `sed "/^# Ratchet:/,\$d"` when creating an adopted repo's `mk.local`, so anything below `# Ratchet:` stays template-only.
3. **Change-aware docs/meta skip**: `docs_or_meta_only_diff` skips Rust compilation gates only when changed files cannot affect `rustc`/`rustdoc` compilation:
   - Single-crate root `README.md` or any Markdown referenced by `include_str!` / `include_bytes!` in `*.rs` triggers full Rust gates.
   - `LICENSE*`, `NOTICE*`, nested `crates/*/README.md`, and script/manifest edits trigger full Rust gates.
4. **Monotonic ratchets**: `./mk ratchet` validates `COVERAGE_FAIL_UNDER_LINES` (`0..=100`), `ECHOES_MAX_APPROXIMATE`, and `ECHOES_MAX_REUSE` as non-negative integers, enforces implicit base defaults (`COVERAGE_FAIL_UNDER_LINES=100` when `mk` exists on base; `ECHOES_MAX_*=0` when `.echoes.toml` exists on base), and counts only non-comment `= "allow"` lines inside `[lints.*]` / `[workspace.lints.*]`.
5. **Strict human/agent doc separation**: `local:docs_boundary` in `mk.local` fails `./mk ci` if any file under `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CITATION.cff`, `codemeta.json`, `docs/`, `.github/`, or `crates/` references `AGENTS.md`, `CLAUDE.md`, `SKILL.md`, `.agents/`, or agent instructions. Agent files may link to human docs (`docs/GATES.md`, `docs/ADOPTING.md`, `docs/DEBT.md`), never the reverse.
6. **Tool pin enforcement**: `tools` hard-fails on missing binaries or versions differing from `mk.versions` (`RUST_NIGHTLY`, `TOMBI_VERSION`, `SHELLCHECK_VERSION`, `CARGO_TOOLS_CI`, `CARGO_TOOLS_NIGHTLY`).

## Audit Pitfalls

- **Compiled Markdown**: `crates/sample-lib/README.md` is embedded via `#![doc = include_str!("../README.md")]` in `crates/sample-lib/src/lib.rs`. Backticks, broken intra-doc links, and Rust fenced blocks are compiled by `./mk doc` and `./mk test`. Keep example anchor `/// Adds two` intact unless updating `tests/gate_selftest.sh`.
- **TOML inline comments**: `tombi format --check` requires two spaces before inline `#` comments (`"MIT",  # comment`).
- **Git-history symbol tracking**: `cargo refquiem` scans commits and flags backticked deleted or signature-changed Rust items across comments and Markdown. Update mentions or document `<!-- refquiem: allow(name) -->` / `// refquiem: allow(name)` in `docs/DEBT.md` (unused markers also fail).
- **Bounded mutation runner**: `LOCAL_OVERRIDES` cannot override `mutants` or `mutants-diff`. `run_mutants` requires free disk (`MUTANTS_MIN_FREE_DISK_GB=10`) and free memory (`MUTANTS_MIN_FREE_MEM_PCT=15`).
- **Miri temp-path stubs**: `cargo-miri` caches the build CWD inside test runner stubs under `target/miri`. In `tests/gate_selftest.sh`, run `miri` with an isolated `CARGO_TARGET_DIR="$WORK/target-miri"` so deleted `mktemp` directories never break subsequent selftest runs.
- **Host `CARGO_HOME` contention**: If concurrent jobs share `~/.cargo/bin` and overwrite pinned binaries (such as `tombi`), use an isolated `CARGO_HOME` populated with `./mk setup ci` instead of mutating shared globals.
- **Line-ending & sed portability**: `scripts/adopt.sh` runs on macOS BSD `sed` and Bash (`-i.bak` followed by `rm -f *.bak`, newline-checked `.gitignore` appends). Test shell edits with `./mk shell` (`shellcheck --severity=style`).

## Playbooks

### Adding or Modifying a Gate

1. Implement the task in `mk` (or template-only in `mk.local` below `# Ratchet:`), update `./mk help` if public, and add its `gate_desc` / `gate_hint` entries.
2. Add an `expect_fail` violation case in `tests/gate_selftest.sh` first and confirm it fails before patching or catches the target marker afterward.
3. Update `docs/GATES.md` with accurate trigger and selftest violation rows (no agent references).
4. Run `NO_COLOR=1 ./mk shell && NO_COLOR=1 ./mk ci && NO_COLOR=1 ./mk selftest`.

### Modifying `scripts/adopt.sh` or `AGENTS.md`

1. Keep `seed_agents()` and `seed_debt()` regex filters synchronized with any new template-only sections in `AGENTS.md` or `docs/DEBT.md`.
2. Ensure all seeded TOML files pass `tombi format --check` and repeated applies are byte-identical.
3. Verify via `./mk selftest` (`adopt:` checks).

### Recording Unavoidable Gate Exceptions

1. Prefer `#[expect(lint, reason = "...")]` over bare `#[allow(...)]`.
2. Document every workspace-level lint allow, `deny.toml` skip, `.cargo/mutants.toml` exclusion, `// echoes: allow`, or `// refquiem: allow(name)` in `docs/DEBT.md` with owner and removal condition.
