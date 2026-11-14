---
name: rusti-graben
description: Strict Rust hygiene template. Use when setting up or enforcing quality gates in Rust repos. Always use ./mk as single entrypoint; no direct cargo/rustfmt/clippy/typos/cargo-* calls. All gates fail hard.
license: AGPL-3.0-or-later
allowed-tools:
  - Bash(./mk:*)
  - Bash(cargo:*)
  - Bash(rustup:*)
  - Bash(git:*)
metadata:
  author: adafede
  version: "1.0.0"
  tags: [rust, hygiene, ci, gates, linting, formatting, security, template]
---

# rusti-graben

A zero-drift quality-hygiene template and adoption runner for Rust repositories. See [`AGENTS.md`](../../AGENTS.md) for repo conventions.

## Rules
- **Single entrypoint**: Always use `./mk <task>`. Do not invoke `cargo`, `rustfmt`, `clippy`, `typos`, `cargo-deny`, `cargo-audit`, or `cargo-machete` directly.
- **Hard failures**: Gates fail hard on violations. A gate skips only when inapplicable, and a missing or mismatched tool version fails.
- **Version pinning**: Toolchain in `rust-toolchain.toml`, every tool in `mk.versions`; `tools` refuses version drift.
- **Standard vs local**: `mk`, `mk.versions`, and `.github/actions/setup/action.yml` stay identical across repos (synced by `scripts/adopt.sh`); never edit them in adopted repos. Repo-specific tasks (`task_<name>()` functions or `Makefile.toml` cargo-make tasks), overrides, and ratchets go in `mk.local`. Unknown `./mk <task>` names dispatch through `mk.local` or `cargo make --no-workspace`.
- **Strict lints**: `unsafe_code = "forbid"`, `unwrap_used = "deny"`, `allow_attributes = "deny"` at workspace level (use `#[expect(..., reason = "...")]`).
- **Pre-commit**: Use `prek` hooks invoking `./mk` (`./mk check` on commit, `./mk ci-fast` on push).
- **Doc boundary**: Never reference `AGENTS.md`, `CLAUDE.md`, `SKILL.md`, or `.agents/` from human-facing docs (`README.md`, `CONTRIBUTING.md`, `docs/`, `.github/`).

## Quick Start
```bash
./mk setup  # Install toolchain + pinned tools
./mk check  # Fast inner loop (fmt + tombi + typos + lint)
./mk ci     # Run all blocking CI gates
```

## Gates (`./mk ci`)
`tools`, `actions`, `shell`, `commits`, `ratchet`, `fmt`, `tombi`, `typos`, `lint`, `lints-inherit`, `test`, `doc`, `deny`, `audit`, `machete`, `msrv`, `echoes`, `refquiem`, `semver` (skips without lib crates, when all crates are pre-1.0, or without an earlier `v*` tag), `wasm` (runs only when `wasm32` is declared outside comments), `mutants-diff` (mutation testing on changed and untracked Rust files). Rust compilation gates skip automatically on `ci` / `ci-fast` only for standalone doc/workflow/meta diffs. See `docs/GATES.md`.

## Commands
- `./mk help` - Show tiers and task aliases
- `./mk --list` - List all available tasks
- `./mk setup [ci|nightly|all]` - Install toolchains and pinned tools (needs `cargo-binstall`)
- `./mk check` - Fast inner loop: `fmt` + `tombi` + `typos` + `lint`
- `./mk fix` - Auto-fix formatting, TOML, typos, and clippy
- `./mk test-fast` - Unit and integration tests without doctests (`nextest` / `cargo test`)
- `./mk watch` - Continuous feedback via `bacon` / `cargo-watch`
- `./mk fmt`, `./mk lint`, `./mk test`, `./mk doc`, `./mk deny`, `./mk audit`, `./mk typos`, `./mk tombi` (`toml`), `./mk machete` (`unused-deps`), `./mk msrv`, `./mk echoes` (`duplication`/`dup`), `./mk refquiem` (`stale-refs`)
- `./mk ci-fast` - Local pre-push gates (skips `mutants-diff` & network `audit`; change-aware)
- `./mk ci` - All blocking PR gates
- `./mk ci-nightly` - Nightly checks (`mutants`, `coverage`/`cov`, `powerset`/`hack`, `miri`, `outdated`)
- `./mk ci-release` - Release checks (`./mk ci` + `cargo publish --workspace --dry-run`)
- `./mk coverage-baseline` - Set the coverage floor to today's coverage
- `./mk echoes-baseline` - Record legacy echoes counts in `mk.local`
- `./mk selftest` - Inject one violation per gate and assert each gate fails (template repo)

## Adoption
`DRY_RUN=0 scripts/adopt.sh <repo>` syncs standard files, seeds missing configs (`docs/DEBT.md` and `AGENTS.md` stripped of template specifics), sets the repo's license in `deny.toml`, adds lint tables, and preserves existing configs with diffs. See `docs/ADOPTING.md`.
