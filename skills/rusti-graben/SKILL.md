---
name: rusti-graben
description: "Strict Rust hygiene template. Use when setting up or enforcing quality gates in Rust repos. Always use ./mk as single entrypoint; no direct cargo/rustfmt/clippy/typos/cargo-* calls."
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

## Rules
- **Single entrypoint**: Always run `./mk <task>`; never invoke `cargo`, `rustfmt`, `clippy`, `typos`, `cargo-deny`, `cargo-audit`, or `cargo-machete` directly.
- **Hard failures & pinning**: All gates fail hard unless inapplicable (`rust-toolchain.toml` + `mk.versions`; `tools` refuses version drift).
- **Standard vs local**: Never edit synced `mk`, `mk.versions`, `.mk/*`, or `.github/actions/setup/action.yml` in adopted repos; put repo tasks (`task_<name>()`, `Makefile.toml`), overrides, and ratchets in `mk.local`.
- **Strict lints & hooks**: Enforce workspace `unsafe_code = "forbid"`, `unwrap_used = "deny"`, `allow_attributes = "deny"` (`#[expect(..., reason = "...")]`), and `prek` hooks (`./mk check` on commit, `./mk ci-fast` on push).
- **Doc boundary**: Never reference `AGENTS.md`, `CLAUDE.md`, `SKILL.md`, or `.agents/` from human docs (`README.md`, `CONTRIBUTING.md`, `docs/`, `.github/`).
- **Adopt**: `DRY_RUN=0 scripts/adopt.sh <repo>` (see `docs/ADOPTING.md` and `AGENTS.md`).

## Commands & Gates
- **Edit loop**: `./mk check [-p <crate>]` | `./mk check-changed` | `./mk fix` | `./mk test-fast [-p <crate>]` | `./mk test-changed` | `./mk watch`
- **Mutant loop**: `./mk mutants-diff -f <file>` → `./mk mutants-diff --iterate` | `./mk mutants-affected [base]` | `./mk mutants-plan [--mode diff|affected|full]`
- **Pre-push & CI**: `./mk ci-fast` | `./mk ci-core` | `./mk ci` (full non-iterated `mutants-diff`, `tools`, `actions`, `shell`, `commits`, `ratchet`, `fmt`, `tombi`, `typos`, `lint`, `lints-inherit`, `test`, `doc`, `deny`, `audit`, `machete`, `msrv`, `echoes`, `refquiem`, `semver`, `wasm`; see `docs/GATES.md`)
- **Nightly & setup**: `./mk setup [ci|nightly|all]` | `./mk ci-nightly-checks` | `./mk ci-nightly` | `./mk ci-release` | `./mk coverage-baseline` | `./mk echoes-baseline` | `./mk selftest`
