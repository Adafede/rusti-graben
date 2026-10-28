# `rusti-graben`

> A strict, zero-drift quality-hygiene template and migration framework for Rust repositories.

`rusti-graben` establishes a hard boundary against unformatted code, sloppy lints, security vulnerabilities, and supply-chain drift. It provides a unified execution model where local development and CI pipelines run the exact same checks with zero divergence.

## What's Included

* **Unified Local & CI Entrypoint (`./mk`)**: A single script pinned to specific tool requirements. Run `./mk ci` locally to mirror your CI pipeline exactly.
* **Strict Workspace Lints**: Enforces `#![forbid(unsafe_code)]`, strict Clippy lints (`unwrap_used = "deny"`), and workspace-level package metadata.
* **Supply-Chain Protection (`cargo-deny`, `cargo-audit`)**: Blocks known vulnerabilities, unmaintained dependencies, and unexpected licenses.
* **Formatters & Linters**: Integrated `rustfmt`, `typos`, `cargo-machete` (unused dependency pruning), and Taplo (TOML formatting).
* **Multi-Platform CI Workflows**: Ready-to-use **GitHub Actions** (SHA-pinned with caching) and **Forgejo/Codeberg** workflows.
* **Adoption Script (`scripts/adopt.sh`)**: An idempotent migration tool to roll out hygiene gates progressively to existing repositories.

## Quick Start

### 1. Initialize & Setup

Clone or use this repository as a template, then install the required tools and components:

```bash
./mk setup
```

### 2. Run the Local CI Gate

Execute the full quality-hygiene pipeline locally:

```bash
./mk ci
```

## Available Commands (`./mk`)

All checks are orchestrated through the `./mk` runner:

| Command | Description |
| :--- | :--- |
| `./mk setup` | Installs required Rust toolchains, target components, and standalone cargo tools |
| `./mk fmt` | Checks code formatting (`rustfmt`) and spelling (`typos`) |
| `./mk lint` | Runs strict `cargo clippy` with workspace lints and prunes dead dependencies (`cargo-machete`) |
| `./mk test` | Runs the test suite across all workspace members |
| `./mk doc` | Builds documentation with broken-link checks enforced (`-D warnings`) |
| `./mk deny` | Audits dependencies and licenses (`cargo deny` & `cargo audit`) |
| `./mk ci` | Executes the complete local quality gate sequence |

## Adopting in Existing Repositories

To port the `rusti-graben` baseline to an existing Rust project without breaking builds on day one:

1. Copy `scripts/adopt.sh` into your target repository.
2. Run a dry-run analysis:
   ```bash
   DRY_RUN=1 ./scripts/adopt.sh /path/to/repo
   ```
3. Apply the baseline files:
   ```bash
   DRY_RUN=0 ./scripts/adopt.sh /path/to/repo
   ```
4. Run `./mk ci` and introduce any legacy allowlists incrementally.

## License

Licensed under the GNU Affero General Public License v3.0 or later (`AGPL-3.0-or-later`). See the [`LICENSE`](./LICENSE) file for details.

## Available tasks

Run `./mk` to see available commands, or `./mk --list-all-steps` if supported. The task list is not duplicated here to avoid drift.
