# shellcheck shell=bash
# Shared assertion harness, reset helper, and code fixtures for gate_selftest.sh.

# shellcheck disable=SC2034  # shared constants read by sourced suite_*.sh files
LIB=crates/sample-lib/src/lib.rs
# shellcheck disable=SC2034
LIB_TOML=crates/sample-lib/Cargo.toml
# shellcheck disable=SC2034
BIN_TOML=crates/sample-bin/Cargo.toml
failed=0
# shellcheck disable=SC2034  # spelled at runtime so the typos gate passes
typo="$(printf 't%sh' e)"

reset() {
    git reset -q --hard base
    git clean -qfdx
    local t
    for t in $(git tag -l 'v*'); do git tag -d "$t" >/dev/null; done
}

# expect_fail_cmd <marker> <description> <cmd...>; the violation is already applied.
expect_fail_cmd() {
    local marker="$1" what="$2" out rc=0
    shift 2
    out="$("$@" 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "NOT CAUGHT   $what"
        failed=1
    elif ! grep -qF -- "$marker" <<<"$out"; then
        echo "WRONG CAUSE  $what (expected '$marker' in output)"
        tail -20 <<<"$out"
        failed=1
    else
        echo "caught       $what"
    fi
    reset
}

expect_fail() {
    expect_fail_cmd "$2" "$1: $3" ./mk "$1"
}

expect_pass() {
    local what="$1" out rc=0
    shift
    out="$("$@" 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "FAILED       $what (exit $rc)"
        tail -20 <<<"$out"
        failed=1
    else
        echo "ok           $what"
    fi
    reset
}

# Assert exact exit code and expected substring in combined stdout/stderr, then reset.
expect_rc_and_output() {
    local expected_rc="$1" marker="$2" what="$3" out rc=0
    shift 3
    out="$("$@" 2>&1)" || rc=$?
    if [ "$rc" -eq "$expected_rc" ] && grep -qF -- "$marker" <<<"$out"; then
        echo "ok           $what"
    else
        echo "FAILED       $what (rc=$rc, expected $expected_rc with '$marker')"
        printf '%s\n' "$out"
        failed=1
    fi
    reset
}

expect_json_expr() {
    local what="$1" expr="$2" payload="$3"
    if python3 -c "import json, sys; d = json.loads(sys.argv[1]); assert ($expr), d" "$payload"; then
        echo "ok           $what"
    else
        echo "FAILED       $what (payload='$payload')"
        failed=1
    fi
    reset
}

check() {
    local what="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "ok           $what"
    else
        echo "FAILED       $what"
        failed=1
    fi
}

append_lib() { printf '\n%s\n' "$1" >>"$LIB"; }

# shellcheck disable=SC2034
untested_fn='/// Doubles `x`.
#[must_use]
pub const fn double(x: usize) -> usize {
    x * 2
}'

# shellcheck disable=SC2034
checksum_fn='/// Weighted byte sum.
#[must_use]
pub fn checksum(data: &[u8]) -> u64 {
    let mut acc = 0u64;
    for (i, b) in data.iter().enumerate() {
        acc = acc.wrapping_add((i as u64 + 1).wrapping_mul(u64::from(*b)));
    }
    acc
}'
