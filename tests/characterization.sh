#!/usr/bin/env bash
# Characterization tests pinning observable baseline behavior of mk,
# scripts/adopt.sh, and sample-bin before structural refactoring.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" != "$actual" ]; then
        printf 'FAIL [%s]\n  expected: %s\n  actual:   %s\n' "$label" "$expected" "$actual" >&2
        failures=$((failures + 1))
    else
        printf 'ok   %s\n' "$label"
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if ! grep -qF -- "$needle" <<<"$haystack"; then
        printf 'FAIL [%s]: expected %s in output\n' "$label" "$needle" >&2
        failures=$((failures + 1))
    else
        printf 'ok   %s\n' "$label"
    fi
}

run_in_dir() {
    local dir="$1"
    shift
    (cd "$dir" && "$@")
}

assert_fails_with() {
    local label="$1" marker="$2" out rc=0
    shift 2
    out="$("$@" 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
        printf 'FAIL [%s]: expected non-zero exit\n' "$label" >&2
        failures=$((failures + 1))
    else
        assert_contains "$label" "$marker" "$out"
    fi
}

# 1. ./mk help & --list & unknown command
help_out="$(NO_COLOR=1 ./mk help)"
for token in "Usage: ./mk" "check-changed" "test-changed" "ci-fast" "ci-core" "mutants-plan" "coverage-baseline" "echoes-baseline" "unused-deps"; do
    assert_contains "help contains $token" "$token" "$help_out"
done

list_out="$(NO_COLOR=1 ./mk --list)"
for token in actions audit bench check check-changed ci ci-core ci-fast ci-nightly ci-nightly-checks ci-release commits cov coverage coverage-baseline deny doc dup duplication echoes echoes-baseline feature-powerset fix fmt hack help lint lints-inherit machete miri msrv mutants mutants-affected mutants-diff mutants-plan outdated powerset ratchet refquiem selftest semver setup shell stale-refs test test-changed test-fast tombi toml tools typos udeps unused-deps wasm watch local:docs_boundary; do
    assert_contains "--list contains $token" "$token" "$list_out"
done

assert_fails_with "unknown task prints usage" "Usage: ./mk {" env NO_COLOR=1 ./mk unknown-task-xyz

# 2. Alias smoke checks
toml_out="$(NO_COLOR=1 ./mk toml 2>&1)"
assert_contains "toml alias runs tombi" "files linted successfully" "$toml_out"

# 3. mutants-plan output & validation
plan_diff="$(NO_COLOR=1 ./mk mutants-plan --mode diff)"
assert_eq "mutants-plan diff clean" '{"mode":"diff","mutants":0,"shards":0,"packages":[]}' "$plan_diff"

plan_full="$(NO_COLOR=1 ./mk mutants-plan --mode full)"
assert_eq "mutants-plan full default" '{"mode":"full","mutants":5,"shards":1,"packages":["sample-bin","sample-lib"]}' "$plan_full"

plan_sharded="$(NO_COLOR=1 MUTANTS_TARGET_PER_SHARD=2 ./mk mutants-plan --mode full)"
assert_eq "mutants-plan full sharded" '{"mode":"full","mutants":5,"shards":3,"packages":["sample-bin","sample-lib"]}' "$plan_sharded"

plan_capped="$(NO_COLOR=1 MUTANTS_TARGET_PER_SHARD=1 MUTANTS_MAX_SHARDS=2 ./mk mutants-plan --mode full)"
assert_eq "mutants-plan full capped shards" '{"mode":"full","mutants":5,"shards":2,"packages":["sample-bin","sample-lib"]}' "$plan_capped"

assert_fails_with "mutants-plan rejects invalid mode" "invalid --mode" env NO_COLOR=1 ./mk mutants-plan --mode bogus
assert_fails_with "mutants-plan rejects zero target" "MUTANTS_TARGET_PER_SHARD must be a positive integer" env NO_COLOR=1 MUTANTS_TARGET_PER_SHARD=0 ./mk mutants-plan --mode full
assert_fails_with "mutants-plan rejects zero max shards" "MUTANTS_MAX_SHARDS must be a positive integer" env NO_COLOR=1 MUTANTS_MAX_SHARDS=0 ./mk mutants-plan --mode full

# 4. ratchet numeric validation in isolated workdir
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ratchet_dir="$WORK/ratchet-check"
mkdir -p "$ratchet_dir"
cp "$ROOT_DIR/mk" "$ROOT_DIR/mk.versions" "$ratchet_dir/"
if [ -d "$ROOT_DIR/.mk" ]; then
    cp -R "$ROOT_DIR/.mk" "$ratchet_dir/.mk"
fi
printf 'COVERAGE_FAIL_UNDER_LINES="101"\n' >"$ratchet_dir/mk.local"
assert_fails_with "ratchet rejects >100 coverage" "COVERAGE_FAIL_UNDER_LINES must be an integer 0..=100" \
    run_in_dir "$ratchet_dir" env NO_COLOR=1 ./mk ratchet

printf 'COVERAGE_FAIL_UNDER_LINES="100"\nECHOES_MAX_APPROXIMATE="abc"\n' >"$ratchet_dir/mk.local"
assert_fails_with "ratchet rejects non-integer echoes max" "ECHOES_MAX_APPROXIMATE must be a non-negative integer" \
    run_in_dir "$ratchet_dir" env NO_COLOR=1 ./mk ratchet

# 5. scripts/adopt.sh dry-run & idempotent apply on scratch crate
adopt_dir="$WORK/adopt-scratch"
mkdir -p "$adopt_dir/src"
cat >"$adopt_dir/Cargo.toml" <<'EOF'
[package]
name = "adopt-scratch"
version = "0.1.0"
edition = "2024"
license = "MIT"
EOF
printf '//! Scratch crate.\n' >"$adopt_dir/src/lib.rs"
(cd "$adopt_dir" && cargo generate-lockfile --offline --quiet)

dry_out="$(DRY_RUN=1 "$ROOT_DIR/scripts/adopt.sh" "$adopt_dir")"
assert_contains "adopt dry-run plans mk" "would: add mk" "$dry_out"
if [ -e "$adopt_dir/mk" ]; then
    printf 'FAIL [adopt dry-run wrote mk]\n' >&2
    failures=$((failures + 1))
else
    printf 'ok   adopt dry-run writes nothing\n'
fi

DRY_RUN=0 "$ROOT_DIR/scripts/adopt.sh" "$adopt_dir" >/dev/null
apply_again="$(DRY_RUN=0 "$ROOT_DIR/scripts/adopt.sh" "$adopt_dir")"
assert_contains "adopt second run is no-op" "0 change(s)" "$apply_again"

# 6. sample-bin CLI golden output
bin_out="$(cargo run -q -p sample-bin)"
assert_eq "sample-bin stdout golden" "10 + 20 = 30" "$bin_out"

[ "$failures" -eq 0 ] || {
    printf 'Characterization suite failed (%d failure(s))\n' "$failures" >&2
    exit 1
}
printf '==> characterization suite passed\n'
