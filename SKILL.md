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

A strict, zero-drift quality-hygiene template for Rust repositories.

## Rules
- **Single entrypoint**: Always use `./mk <task>`. Do not invoke cargo/rustfmt/clippy/typos/cargo-deny/cargo-audit/cargo-machete/etc directly.
- **Hard failures**: All gates must fail hard on violations. No `|| true`, no silent skips.
- **Version pinning**: Toolchain in `rust-toolchain.toml`, every tool in `mk.versions`; gates refuse other versions.
- **Strict lints**: `unsafe_code = forbid`, `unwrap_used = deny` at workspace level.
- **Pre-commit**: Use `prek` hooks that call `./mk`.

## Quick Start
```bash
./mk setup  # Install toolchain + pinned tools
./mk ci     # Run all blocking CI gates
```

## Gates (./mk ci)
tools, actions, shell, commits, ratchet, fmt, tombi, typos, lint, lints-inherit, test, doc, deny, audit, machete, msrv, echoes, semver (skips with no lib, pre-1.0 crates, or no earlier `v*` tag), wasm (only when wasm32 is declared), mutants-diff (mutation testing of the branch's changes). refquiem is experimental: `./mk ci-experimental`, not enforced. All are blocking; a missing tool, or one not at its pinned version, fails. See `docs/GATES.md`.

## Commands
- `./mk --list` - List all tasks
- `./mk setup [ci|nightly|all]` - Install toolchains and pinned tools (needs cargo-binstall)
- `./mk fmt` - Check formatting (rustfmt + typos + tombi)
- `./mk lint` - Clippy with `-D warnings`
- `./mk test` - Run tests
- `./mk doc` - Build docs with `-D warnings`
- `./mk deny` - cargo-deny
- `./mk audit` - cargo-audit
- `./mk typos` - Spell check
- `./mk tombi` - TOML formatting check
- `./mk machete` - Unused deps
- `./mk ci` - All blocking gates
- `./mk ci-nightly` - Nightly checks (mutants, coverage, powerset, miri, outdated)
- `./mk ci-release` - Release checks
- `./mk ci-experimental` - Experimental gates (refquiem), not enforced
- `./mk coverage-baseline` - Set the coverage floor to today's coverage
- `./mk selftest` - Inject one violation per gate and assert each gate fails

## Adoption
`DRY_RUN=0 scripts/adopt.sh <repo>` copies the gates, workflows and configs into an existing repo (workspace or single crate), keeps existing files with a diff, adds lints and the repo's own license. See `docs/ADOPTING.md`.

## CI
- Tiered workflows: ci, nightly, release
- SHA-pinned actions, least privilege permissions, concurrency
- Self-test injects violations to assert hard failures
