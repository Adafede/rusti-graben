# Contributing

1. `./mk setup` once (installs the pinned toolchains and tools; needs [cargo-binstall](https://github.com/cargo-bins/cargo-binstall)).
2. Optionally `prek install` to run the fast gates on commit and `./mk ci` on push.
3. Make the change, with tests and docs.
4. `./mk ci` must pass. It is exactly what CI runs.

Commits follow [Conventional Commits](https://www.conventionalcommits.org/). Exceptions to a lint
or gate are recorded with a reason, never by disabling the gate (see `AGENTS.md`).
