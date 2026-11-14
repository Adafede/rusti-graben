# Contributing

Contributions to `rusti-graben` run through the same `./mk` entrypoint used by CI.

## Prerequisites

- `git`
- [`rustup`](https://rustup.rs/)
- [`cargo-binstall`](https://github.com/cargo-bins/cargo-binstall)

## Local Setup

1. Run `./mk setup` once to install the pinned toolchains (`stable`, MSRV `1.85`, and `nightly` from [`mk.versions`](./mk.versions)) and pinned gate binaries.
2. Optionally run `prek install` to run fast checks on commit and `./mk ci-fast` on push.

## Workflow

1. During iteration, run `./mk check` (`fmt`, `tombi`, `typos`, `lint`), `./mk fix` for auto-fixable issues, and `./mk test-fast` for unit and integration tests.
2. Add deterministic tests for every new or changed Rust path and confirm `./mk mutants-diff` passes on your branch.
3. Run `./mk ci` before opening a pull request. It runs the exact gate suite enforced in CI.
4. When modifying [`mk`](./mk), [`mk.local`](./mk.local), [`mk.versions`](./mk.versions), or [`scripts/adopt.sh`](./scripts/adopt.sh), also run `./mk selftest` to verify that every gate still fails on an injected violation and `adopt.sh` stays idempotent.

## Conventions & Exceptions

- Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `refactor:`, `chore:`, etc.), enforced by `./mk commits`.
- Never weaken a gate globally or add bare `#[allow(...)]` attributes. Use `#[expect(lint, reason = "...")]` when a local exception is unavoidable, and record every persistent exception with its reason, owner, and removal condition in [`docs/DEBT.md`](./docs/DEBT.md).
- See [`docs/GATES.md`](./docs/GATES.md) for gate behavior and [`docs/ADOPTING.md`](./docs/ADOPTING.md) for repository adoption rules.
