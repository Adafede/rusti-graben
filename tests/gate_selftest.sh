#!/usr/bin/env bash
# Proves every gate can fail. Injects one violation per gate into a scratch copy
# of the repo and asserts `./mk <gate>` fails with the expected marker.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
OUTSIDE="$(mktemp -d)" # crates that must not be workspace members
trap 'rm -rf "$WORK" "$OUTSIDE"' EXIT
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$SRC/target}/selftest"
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@invalid
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@invalid

git -C "$SRC" ls-files -co --exclude-standard -z | (cd "$SRC" && xargs -0 tar cf -) | tar xf - -C "$WORK"
cd "$WORK"
git init -q
git add -A
git commit -qm base
git tag base
export MK_BASE=base

# shellcheck source=tests/selftest/harness.sh
. "$SRC/tests/selftest/harness.sh"
# shellcheck source=tests/selftest/suite_unit.sh
. "$SRC/tests/selftest/suite_unit.sh"
# shellcheck source=tests/selftest/suite_tools_ci.sh
. "$SRC/tests/selftest/suite_tools_ci.sh"
# shellcheck source=tests/selftest/suite_mutants.sh
. "$SRC/tests/selftest/suite_mutants.sh"
# shellcheck source=tests/selftest/suite_nightly.sh
. "$SRC/tests/selftest/suite_nightly.sh"
# shellcheck source=tests/selftest/suite_adopt.sh
. "$SRC/tests/selftest/suite_adopt.sh"

if ! run_unit_suite; then failed=1; fi
run_tools_and_ci_suite
run_mutants_suite
run_nightly_suite
run_adopt_suite

[ "$failed" = 0 ] || { echo "selftest: some gates cannot fail as they should" >&2; exit 1; }
echo "==> every gate failed on its injected violation"
