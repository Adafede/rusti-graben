[![CI Quality Gate](https://github.com/Adafede/rusti-graben/actions/workflows/ci.yml/badge.svg)](https://github.com/Adafede/rusti-graben/actions/workflows/ci.yml)
[![Template Selftest](https://github.com/Adafede/rusti-graben/actions/workflows/selftest.yml/badge.svg)](https://github.com/Adafede/rusti-graben/actions/workflows/selftest.yml)

# `rusti-graben`

> A strict, zero-drift quality-hygiene template and migration framework for Rust repositories.

- **One entrypoint.** `./mk <task>` runs every gate; CI calls the same tasks, so local and CI cannot disagree.
- **Every gate blocks.** A gate skips only when it cannot apply, and says why. A missing tool, or one at another version than [`mk.versions`](./mk.versions), fails.
- **Every gate is proven.** `./mk selftest` injects one violation per gate and checks that the gate fails because of it.

## Use it

**New repository:** "Use this template" on GitHub, replace the sample crates in `crates/`, then:

```bash
./mk setup   # pinned toolchains and tools (needs cargo-binstall)
./mk ci
```

**Existing repository** (workspace or single crate):

```bash
scripts/adopt.sh path/to/repo             # dry run
DRY_RUN=0 scripts/adopt.sh path/to/repo   # apply
```

See [`docs/ADOPTING.md`](./docs/ADOPTING.md) for what it changes and how to record legacy findings without weakening a gate.

## Tiers

| Tier | When | Gates |
|---|---|---|
| `./mk ci` | Every PR and push, and the pre-push hook | Formatting, lints, tests, docs, licenses and advisories, MSRV, duplicated code (incl. against dependencies), semver, mutation testing of the changed code, workflow and shell checks |
| `./mk ci-nightly` | Daily | Full mutation testing, coverage floor, feature powerset, miri, outdated dependencies |
| `./mk ci-release` | `v*` tags | `./mk ci` and a publish dry run |
| `./mk ci-experimental` | On demand | Gates kept ready but not enforced (refquiem) |

[`docs/GATES.md`](./docs/GATES.md) lists each gate, what it catches and the violation the selftest injects. `./mk --list` shows every task.

## LLM skill

[`skills/rusti-graben/SKILL.md`](./skills/rusti-graben/SKILL.md) (also at [`SKILL.md`](./SKILL.md)) teaches an agent to work through `./mk`.

## License

Licensed under the GNU Affero General Public License v3.0 or later (`AGPL-3.0-or-later`). See [`LICENSE`](./LICENSE). Repositories adopting the gates keep their own license: `adopt.sh` sets it in their `deny.toml`.
