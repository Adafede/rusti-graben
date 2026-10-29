#!/usr/bin/env bash
# Proves every gate can fail. Each case injects one violation into a scratch
# copy of the repo and asserts `./mk <gate>` fails *because of it* (the
# expected marker must appear in the output). A gate that cannot be shown to
# fail is not a gate.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
OUTSIDE="$(mktemp -d)" # crates that must not be workspace members
trap 'rm -rf "$WORK" "$OUTSIDE"' EXIT
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$SRC/target}/selftest"
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@invalid
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@invalid

# Tracked and new (non-ignored) files, as they are now, in a fresh repository.
git -C "$SRC" ls-files -co --exclude-standard -z | (cd "$SRC" && xargs -0 tar cf -) | tar xf - -C "$WORK"
cd "$WORK"
git init -q
git add -A
git commit -qm base
git tag base

LIB=crates/sample-lib/src/lib.rs
LIB_TOML=crates/sample-lib/Cargo.toml
BIN_TOML=crates/sample-bin/Cargo.toml
failed=0
typo="$(printf 't%sh' e)" # spelled at runtime so the typos gate passes on this file

reset() {
    git reset -q --hard base
    git clean -qfdx
    for t in $(git tag -l 'v*'); do git tag -d "$t" >/dev/null; done
}

# expect_fail <task> <marker> <description>; the violation is already applied.
expect_fail() {
    local task="$1" marker="$2" what="$3" out rc=0
    out="$(./mk "$task" 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "NOT CAUGHT   $task: $what"
        failed=1
    elif ! grep -qF -- "$marker" <<<"$out"; then
        echo "WRONG CAUSE  $task: $what (expected '$marker' in output)"
        tail -20 <<<"$out"
        failed=1
    else
        echo "caught       $task: $what"
    fi
    reset
}

append_lib() { printf '\n%s\n' "$1" >>"$LIB"; }

untested_fn='/// Doubles `x`.
#[must_use]
pub const fn double(x: usize) -> usize {
    x * 2
}'

checksum_fn='/// Weighted byte sum.
#[must_use]
pub fn checksum(data: &[u8]) -> u64 {
    let mut acc = 0u64;
    for (i, b) in data.iter().enumerate() {
        acc = acc.wrapping_add((i as u64 + 1).wrapping_mul(u64::from(*b)));
    }
    acc
}'

# --- ci tier ----------------------------------------------------------------

perl -pi -e 's/^TOMBI_VERSION=.*/TOMBI_VERSION="0.0.0"/' mk.versions
expect_fail tools "0.0.0" "tool version differs from mk.versions"

perl -pi -e 's/rust-cache@[0-9a-f]{40}/rust-cache\@v2/' .github/workflows/ci.yml
expect_fail actions "unpinned" "action not pinned to a commit SHA"

append_lib 'fn bad( ){}'
expect_fail fmt "Diff in" "unformatted code"

printf '\n[workspace.metadata.x]\nkey=1\n' >>Cargo.toml
expect_fail tombi "not formatted" "unformatted TOML"

append_lib "// $typo"
expect_fail typos "$typo" "misspelling"

append_lib '/// First byte.
#[must_use]
pub fn first(v: &[u8]) -> u8 {
    *v.first().unwrap()
}'
expect_fail lint "unwrap_used" "unwrap()"

append_lib '/// Nothing.
pub fn nothing() {
    unsafe {}
}'
expect_fail lint 'usage of an `unsafe` block' "unsafe block"

append_lib '#[allow(dead_code)]
fn unused() {}'
expect_fail lint "allow_attributes" "#[allow] instead of #[expect(.., reason)]"

perl -0pi -e 's/\[lints\]\nworkspace = true\n//' "$BIN_TOML"
expect_fail lints-inherit "missing" "crate not inheriting workspace lints"

perl -pi -e 's/assert_eq!\(result, 4\)/assert_eq!(result, 5)/' "$LIB"
expect_fail test "FAILED" "failing unit test"

perl -pi -e 's|^/// Adds two|/// See [`nope`]. Adds two|' "$LIB"
expect_fail doc "unresolved link" "broken intra-doc link"

perl -pi -e 's/^license\.workspace = true/license = "GPL-3.0-only"/' "$LIB_TOML"
expect_fail deny "GPL-3.0-only" "license outside the allow-list"

cat >>Cargo.lock <<'EOF'

[[package]]
name = "smallvec"
version = "1.6.0"
source = "registry+https://github.com/rust-lang/crates.io-index"
EOF
expect_fail audit "RUSTSEC-2021-0003" "dependency with a known advisory"

printf '\n[dependencies]\nitoa = "1"\n' >>"$LIB_TOML"
expect_fail machete "itoa" "unused dependency"

append_lib '/// Whether `n` is even.
#[must_use]
pub const fn even(n: u32) -> bool {
    n.is_multiple_of(2)
}'
expect_fail msrv "is_multiple_of" "API newer than rust-version"

append_lib '/// Weighted byte sum.
#[must_use]
pub fn checksum_a(data: &[u8]) -> u64 {
    let mut acc = 0u64;
    for (i, b) in data.iter().enumerate() {
        acc = acc.wrapping_add((i as u64 + 1).wrapping_mul(u64::from(*b)));
    }
    acc
}

/// Weighted byte sum.
#[must_use]
pub fn checksum_b(data: &[u8]) -> u64 {
    let mut acc = 0u64;
    for (i, b) in data.iter().enumerate() {
        acc = acc.wrapping_add((i as u64 + 1).wrapping_mul(u64::from(*b)));
    }
    acc
}'
expect_fail echoes "checksum_b" "duplicated function"

# A dependency already exports `checksum`; the workspace re-implements it.
mkdir -p "$OUTSIDE/helper/src"
printf '[package]\nname = "helper"\nversion = "0.1.0"\nedition = "2024"\nlicense = "MIT"\n' >"$OUTSIDE/helper/Cargo.toml"
printf '//! Helper.\n\n%s\n' "$checksum_fn" >"$OUTSIDE/helper/src/lib.rs"
printf '\n[dependencies]\nhelper = { path = "%s" }\n' "$OUTSIDE/helper" >>"$LIB_TOML"
append_lib "${checksum_fn/fn checksum/fn local_checksum}"
expect_fail echoes "helper::checksum" "re-implementing a dependency's API"

perl -pi -e 's/^fail-on-findings = true/fail-on-findings = false/' .echoes.toml
expect_fail echoes "fail-on-findings" "weakened .echoes.toml"

append_lib '/// Removes `right` from `left`, saturating at zero.
#[must_use]
pub const fn subtract(left: usize, right: usize) -> usize {
    left.saturating_sub(right)
}'
git commit -qam "add subtract"
git checkout -q base -- "$LIB"
git commit -qam "drop subtract"
echo 'Call `subtract` to take away.' >>README.md
expect_fail refquiem "sample_lib::subtract" "mention of a deleted item"

append_lib "$untested_fn"
git commit -qam "add double"
git tag v0.1.0
git checkout -q base -- "$LIB"
git commit -qam "drop double"
expect_fail semver "function_missing" "public fn removed without a major bump"

append_lib 'pub use std::os::unix::ffi::OsStrExt;'
expect_fail wasm "unix" "code that does not build for wasm32"

append_lib "// $typo"
expect_fail ci "FAIL  typos" "ci tier propagates a failing gate"

# --- nightly tier -----------------------------------------------------------

append_lib "$untested_fn"
expect_fail mutants "MISSED" "untested function (surviving mutant)"

append_lib "$untested_fn"
expect_fail coverage "coverage" "line coverage below the floor"

[ "$failed" = 0 ] || { echo "selftest: some gates cannot fail as they should" >&2; exit 1; }
echo "==> every gate failed on its injected violation"
