# Adopting rusti-graben in an existing repository

```bash
git clone https://github.com/Adafede/rusti-graben ~/rusti-graben
~/rusti-graben/scripts/adopt.sh path/to/repo             # dry run: shows every change
DRY_RUN=0 ~/rusti-graben/scripts/adopt.sh path/to/repo   # apply
cd path/to/repo
./mk setup                 # pinned toolchains and tools (needs cargo-binstall)
./mk coverage-baseline     # coverage floor = today's value
./mk ci                    # fix or record each finding (below)
```

## Standard files and `mk.local`

`mk`, `mk.versions` and `.github/actions/setup/action.yml` are standard: identical
in every repository, and synced to the template each time `adopt.sh` runs (re-run
it to update a repository). Everything specific to a repository lives in
`mk.local`, which `adopt.sh` creates once and never overwrites:

| Key | Use |
|---|---|
| `LOCAL_CI_GATES` | the repository's own checks, added to `./mk ci` (cargo-make tasks) |
| `LOCAL_NIGHTLY_GATES` | the same for `./mk ci-nightly` |
| `LOCAL_OVERRIDES` | a standard gate run as the repository's own task: `test`, or `wasm=check-wasm` |
| `LOCAL_CARGO_TOOLS` | extra pinned tools (`cargo-make@0.37.24`), installed and version-checked |
| `LOCAL_SETUP` | cargo-make tasks `./mk setup` runs in every tier, for installs a pin cannot express |
| `LOCAL_SYSTEM_PACKAGES` | apt packages `./mk setup` installs on CI |
| `COVERAGE_FAIL_UNDER_LINES` | the coverage floor (`./mk coverage-baseline`; the `ratchet` gate keeps it from dropping) |

A repository with a `Makefile.toml` keeps its cargo-make tasks: any `./mk` name the
standard runner does not know runs that task (`./mk web-dev`), always with
`--no-workspace`. If the repository's `mk` only wrapped cargo-make, `adopt.sh`
replaces it with the standard one; any other custom `mk` makes it stop.

## What adopt.sh does

`adopt.sh` works for workspaces and single crates and is idempotent:

- syncs the standard files, and creates `mk.local` when missing;
- copies the gate configs, `AGENTS.md`, the CI/nightly/release workflows and the
  Dependabot/Renovate configs, when missing;
- keeps every file that already exists and prints its diff against the template;
- allows the repository's own license in `deny.toml` (not the template's AGPL);
- adds the template's lint tables when the repository has none, and makes every
  workspace member inherit them;
- ignores the gate outputs (`lcov.info`, `mutants.out*/`) in `.gitignore`.

It never copies the template's sample crates or its selftest.

## Recording legacy findings

Every gate stays on. What cannot be fixed yet is recorded where reviewers see it:

| Finding | Where it is recorded |
|---|---|
| Lint | `#[expect(lint, reason = "...")]` at the site (fails once no longer needed) |
| Duplicate dependency versions | `deny.toml` `[bans] skip`, with a reason |
| Intentional duplicate code | `// echoes: allow` above the copy, with a reason |
| Mutant no test can kill | `.cargo/mutants.toml` exclusion, with a comment |
| Coverage below 100% | `./mk coverage-baseline`; the `ratchet` gate then refuses any decrease |

## What adapts to the repository

- `semver` runs for library crates from 1.0.0 on, against the last `v*` tag. Pre-1.0
  crates are in development: breaking changes need no version bump.
- `wasm` runs only when `rust-toolchain.toml` or `Cargo.toml` declares `wasm32`.
- `msrv` needs `rust-version` in `Cargo.toml`.
- `commits`, `ratchet` and `mutants-diff` compare with the base branch
  (`origin/HEAD`, `origin/main` or `origin/master`; override with `MK_BASE`).
