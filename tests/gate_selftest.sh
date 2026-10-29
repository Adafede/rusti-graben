#!/usr/bin/env bash
# Proves every gate can fail. Each case injects one violation into a scratch
# copy of the repo and asserts `./mk <gate>` fails *because of it* (the
# expected marker must appear in the output). A gate that cannot be shown to
# fail is not a gate.
# Rust and Markdown snippets are single-quoted on purpose: their backticks are literal.
# shellcheck disable=SC2016
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
# Branch-relative gates (commits, mutants-diff) compare with the base commit.
export MK_BASE=base

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

perl -pi -e 's/checkout@[0-9a-f]{40}/checkout\@v7/' .github/workflows/ci.yml
expect_fail actions "unpinned" "action not pinned to a commit SHA"

printf '\necho $1\n' >>scripts/adopt.sh
expect_fail shell "SC2086" "unquoted variable in a shell script"

echo "// change" >>"$LIB"
git commit -qam "Update the library"
expect_fail commits "not a conventional commit" "commit message outside Conventional Commits"

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

append_lib '/// Prints a greeting.
pub fn greet() {
    println!("hi");
}'
expect_fail lint "print_stdout" "println! in a library"

perl -0pi -e 's/\[lints\]\nworkspace = true\n//' "$BIN_TOML"
expect_fail lints-inherit "missing" "crate not inheriting workspace lints"

perl -pi -e 's/assert_eq!\(result, 4,/assert_eq!(result, 5,/' "$LIB"
expect_fail test "FAILED" "failing unit test"

perl -pi -e 's|^/// Adds two|/// See [`nope`]. Adds two|' "$LIB"
expect_fail doc "unresolved link" "broken intra-doc link"

perl -pi -e 's|^/// Adds two|/// Adds `two|' "$LIB"
expect_fail doc "unescaped backtick" "unbalanced backtick in docs"

perl -pi -e 's/assert_eq!\(total, 6,/assert_eq!(total, 7,/' crates/sample-lib/README.md
expect_fail test "README.md" "failing README example"

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
expect_fail refquiem "sample_lib::subtract" "mention of a deleted item (experimental gate)"

# Semver applies from 1.0.0 on; pre-1.0 crates are in development.
perl -pi -e 's/^version = "0\.1\.0"/version = "1.0.0"/' Cargo.toml
perl -pi -e 's/version = "0\.1\.0"/version = "1.0.0"/' crates/sample-bin/Cargo.toml
cargo update --workspace --offline --quiet
append_lib "$untested_fn"
git commit -qam "add double"
git tag v1.0.0
git checkout -q base -- "$LIB"
git commit -qam "drop double"
expect_fail semver "function_missing" "public fn removed without a major bump"

printf 'targets = ["wasm32-unknown-unknown"]\n' >>rust-toolchain.toml
append_lib 'pub use std::os::unix::ffi::OsStrExt;'
expect_fail wasm "unix" "code that does not build for wasm32"

perl -pi -e 's/^COVERAGE_FAIL_UNDER_LINES=.*/COVERAGE_FAIL_UNDER_LINES="1"/' mk.local
expect_fail ratchet "went down" "coverage floor lowered"

append_lib "// $typo"
expect_fail ci "FAIL  typos" "ci tier propagates a failing gate"

append_lib "$untested_fn"
expect_fail mutants-diff "MISSED" "untested function added on the branch"

# --- nightly tier -----------------------------------------------------------

append_lib "$untested_fn"
expect_fail mutants "MISSED" "untested function (surviving mutant)"

append_lib "$untested_fn"
expect_fail coverage "coverage" "line coverage below the floor"

# --- scripts/adopt.sh ------------------------------------------------------

# check <description> <command...>: the command must succeed.
check() {
    local what="$1"
    shift
    if "$@" >/dev/null 2>&1; then echo "ok           adopt: $what"; else echo "FAILED       adopt: $what"; failed=1; fi
}
adopt() { DRY_RUN="$1" "$SRC/scripts/adopt.sh" "$2"; }
# Everything adopt.sh may touch, to prove dry runs and re-runs change nothing.
fingerprint() { (cd "$1" && find . -path ./target -prune -o -type f -print | LC_ALL=C sort | xargs cksum | cksum); }

legacy="$OUTSIDE/legacy-workspace"
mkdir -p "$legacy/crates/core/src"
printf '[workspace]\nmembers = ["crates/core"]\nresolver = "3"\n' >"$legacy/Cargo.toml"
printf '[package]\nname = "core-x"\nversion = "0.1.0"\nedition = "2024"\nlicense = "MIT"\n' >"$legacy/crates/core/Cargo.toml"
echo '//! Core.' >"$legacy/crates/core/src/lib.rs"
printf '# legacy policy\n' >"$legacy/.typos.toml"
(cd "$legacy" && cargo generate-lockfile --offline --quiet)
before="$(fingerprint "$legacy")"
check "dry run succeeds" adopt 1 "$legacy"
check "dry run writes nothing" test "$before" = "$(fingerprint "$legacy")"
check "apply succeeds" adopt 0 "$legacy"
for f in mk mk.versions mk.local deny.toml .echoes.toml .github/workflows/ci.yml .github/actions/setup/action.yml .github/dependabot.yml; do
    check "copies $f" test -f "$legacy/$f"
done
check "mk is executable" test -x "$legacy/mk"
check "does not copy the template selftest" test ! -e "$legacy/.github/workflows/selftest.yml"
check "keeps an existing config" grep -qx '# legacy policy' "$legacy/.typos.toml"
check "adds workspace lints" grep -q '^\[workspace\.lints\.clippy\]' "$legacy/Cargo.toml"
check "members inherit them" bash -c 'cd "$1" && git init -q && ./mk lints-inherit' _ "$legacy"
check "deny no longer allows the template's AGPL license" bash -c '! grep -q AGPL "$1/deny.toml"' _ "$legacy"
before="$(fingerprint "$legacy")"
check "second apply succeeds" adopt 0 "$legacy"
check "second apply changes nothing" test "$before" = "$(fingerprint "$legacy")"

check "mk.local does not inherit the template's coverage floor" bash -c '! grep -q "^COVERAGE_FAIL_UNDER_LINES" "$1/mk.local"' _ "$legacy"
check "a stale standard file is synced" bash -c 'echo "# stale" >>"$1/mk.versions" && DRY_RUN=0 "$2/scripts/adopt.sh" "$1" && ! grep -q "# stale" "$1/mk.versions"' _ "$legacy" "$SRC"

wrapped="$OUTSIDE/cargo-make-repo"
mkdir -p "$wrapped/src"
printf '[package]\nname = "wrapped"\nversion = "0.1.0"\nedition = "2024"\nlicense = "MIT"\n' >"$wrapped/Cargo.toml"
echo '//! Wrapped.' >"$wrapped/src/lib.rs"
printf '[tasks.hello]\nscript = "echo hello"\n' >"$wrapped/Makefile.toml"
printf '#!/usr/bin/env bash\nexec cargo make --no-workspace "$@"\n' >"$wrapped/mk"
chmod +x "$wrapped/mk"
check "cargo-make wrapper: apply succeeds" adopt 0 "$wrapped"
check "cargo-make wrapper: replaced by the standard mk" grep -q "rusti-graben standard runner" "$wrapped/mk"
check "cargo-make wrapper: cargo-make pinned in mk.local" grep -q "^LOCAL_CARGO_TOOLS=(cargo-make@" "$wrapped/mk.local"

custom="$OUTSIDE/custom-runner"
mkdir -p "$custom/src"
printf '[package]\nname = "custom"\nversion = "0.1.0"\nedition = "2024"\n' >"$custom/Cargo.toml"
printf '#!/bin/sh\necho mine\n' >"$custom/mk"
check "own runner: adopt refuses" bash -c '! DRY_RUN=0 "$2/scripts/adopt.sh" "$1"' _ "$custom" "$SRC"
check "own runner: left untouched" grep -qx 'echo mine' "$custom/mk"

single="$OUTSIDE/single-crate"
mkdir -p "$single/src"
printf '[package]\nname = "single"\nversion = "0.1.0"\nedition = "2024"\nlicense = "MPL-2.0"\n' >"$single/Cargo.toml"
echo '//! Single.' >"$single/src/lib.rs"
check "single crate: apply succeeds" adopt 0 "$single"
check "single crate: adds [lints.*] tables" grep -q '^\[lints\.clippy\]' "$single/Cargo.toml"
check "single crate: lints gate passes" bash -c 'cd "$1" && git init -q && ./mk lints-inherit' _ "$single"
check "single crate: deny allows its own license" grep -q '"MPL-2.0", # this project' "$single/deny.toml"

[ "$failed" = 0 ] || { echo "selftest: some gates cannot fail as they should" >&2; exit 1; }
echo "==> every gate failed on its injected violation"
