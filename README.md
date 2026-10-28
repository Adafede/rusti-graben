[![CI Quality Gate](https://github.com/Adafede/rusti-graben/actions/workflows/ci.yml/badge.svg)](https://github.com/Adafede/rusti-graben/actions/workflows/ci.yml)

# `rusti-graben`

> A strict, zero-drift quality-hygiene template and migration framework for Rust repositories.

## LLM Skill

This template is available as an LLM skill: [`SKILL.md`](./SKILL.md) or [`skills/rusti-graben/SKILL.md`](./skills/rusti-graben/SKILL.md). Always use `./mk` as the single entrypoint with hard-fail gates.

## Available tasks

Tasks are generated from `./mk --list` (do not hand-maintain this list):

```bash
./mk --list
```

## Quick Start

```bash
./mk setup
./mk ci
```

## License

Licensed under the GNU Affero General Public License v3.0 or later (`AGPL-3.0-or-later`). See the [`LICENSE`](./LICENSE) file for details.
