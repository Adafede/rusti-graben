#!/usr/bin/env bash
# Fast unit & characterization tests for mk modules, CLI contract, adoption, and sample-bin.
set -euo pipefail

unit_assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" != "$actual" ]; then
        printf 'FAIL [%s]\n  expected: %s\n  actual:   %s\n' "$label" "$expected" "$actual" >&2
        return 1
    fi
    printf 'ok           unit: %s\n' "$label"
}

unit_assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if ! grep -qF -- "$needle" <<<"$haystack"; then
        printf 'FAIL [%s]: expected %s in output\n' "$label" "$needle" >&2
        return 1
    fi
    printf 'ok           unit: %s\n' "$label"
}

unit_run_in_dir() { local dir="$1"; shift; (cd "$dir" && "$@"); }

unit_assert_fails_with() {
    local label="$1" marker="$2" out rc=0
    shift 2
    out="$("$@" 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then printf 'FAIL [%s]: expected non-zero exit\n' "$label" >&2; return 1; fi
    unit_assert_contains "$label" "$marker" "$out"
}

load_mk_modules() {
    local root="$1"
    # shellcheck disable=SC1091  # dynamic repo root path
    . "$root/.mk/catalog.sh"
    # shellcheck disable=SC1091
    . "$root/.mk/core.sh"
    # shellcheck disable=SC1091
    . "$root/.mk/tools.sh"
    # shellcheck disable=SC1091
    . "$root/.mk/mutants.sh"
    # shellcheck disable=SC1091
    . "$root/.mk/mutants_plan.sh"
    # shellcheck disable=SC1091
    . "$root/.mk/gates.sh"
    # shellcheck disable=SC1091
    . "$root/.mk/nightly.sh"
}

test_spec_and_alias_helpers() {
    local root="$1"
    (
        load_mk_modules "$root"
        unit_assert_eq "spec_crate" "dioxus-cli" "$(spec_crate 'dioxus-cli@0.7.10:dx')"
        unit_assert_eq "spec_ver" "0.7.10" "$(spec_ver 'dioxus-cli@0.7.10:dx')"
        unit_assert_eq "spec_tool with bin" "dioxus-cli:dx" "$(spec_tool 'dioxus-cli@0.7.10:dx')"
        unit_assert_eq "spec_tool plain" "cargo-deny" "$(spec_tool 'cargo-deny@0.21.0')"
        unit_assert_eq "tool_bin typos-cli" "typos" "$(tool_bin typos-cli)"
        unit_assert_eq "tool_bin echoes" "cargo-echoes" "$(tool_bin echoes)"
        unit_assert_eq "normalize_cmd_alias toml" "tombi" "$(normalize_cmd_alias toml)"
        unit_assert_eq "normalize_cmd_alias hack" "powerset" "$(normalize_cmd_alias hack)"
        unit_assert_eq "normalize_cmd_alias cov" "coverage" "$(normalize_cmd_alias cov)"
    )
}

test_budget_and_kv_helpers() {
    local root="$1" tmp="$2"
    (
        load_mk_modules "$root"
        local allows_sample kv_file="$tmp/mk.local"
        allows_sample=$'[workspace.lints.clippy]\n# commented = "allow"\nfoo = "allow"\nbar = "warn"'
        unit_assert_eq "count_lint_allows ignores comments" "1" "$(count_lint_allows <<<"$allows_sample")"
        CI=1 mutants_compute_budget 1 8
        unit_assert_eq "budget in-place CI jobs" "1" "$_MK_M_JOBS"
        unit_assert_eq "budget in-place CI threads" "8" "$_MK_M_THREADS"
        CI="" MUTANTS_JOBS="" mutants_compute_budget 0 8
        unit_assert_eq "budget local jobs" "1" "$_MK_M_JOBS"
        unit_assert_eq "budget local threads" "4" "$_MK_M_THREADS"
        printf 'COVERAGE_FAIL_UNDER_LINES="90"\n' >"$kv_file"
        upsert_kv_line "$kv_file" COVERAGE_FAIL_UNDER_LINES '"95"' "# header"
        unit_assert_contains "upsert replaces existing key" 'COVERAGE_FAIL_UNDER_LINES="95"' "$(cat "$kv_file")"
        upsert_kv_line "$kv_file" ECHOES_MAX_REUSE '0'
        unit_assert_contains "upsert appends new key" 'ECHOES_MAX_REUSE=0' "$(cat "$kv_file")"
    )
}

test_cli_surface() {
    local root="$1" help_out list_out toml_out bin_out token
    help_out="$(unit_run_in_dir "$root" env NO_COLOR=1 ./mk help)"
    for token in "Usage: ./mk" "check-changed" "test-changed" "ci-fast" "ci-core" "mutants-plan" "coverage-baseline" "echoes-baseline" "unused-deps"; do
        unit_assert_contains "help contains $token" "$token" "$help_out"
    done
    list_out="$(unit_run_in_dir "$root" env NO_COLOR=1 ./mk --list)"
    for token in actions audit bench check check-changed ci ci-core ci-fast ci-nightly ci-nightly-checks ci-release commits cov coverage coverage-baseline deny doc dup duplication echoes echoes-baseline feature-powerset fix fmt hack help lint lints-inherit machete miri msrv mutants mutants-affected mutants-diff mutants-plan outdated powerset ratchet refquiem selftest semver setup shell stale-refs test test-changed test-fast tombi toml tools typos udeps unused-deps wasm watch local:docs_boundary; do
        unit_assert_contains "--list contains $token" "$token" "$list_out"
    done
    unit_assert_fails_with "unknown task prints usage" "Usage: ./mk {" unit_run_in_dir "$root" env NO_COLOR=1 ./mk unknown-task-xyz
    toml_out="$(unit_run_in_dir "$root" env NO_COLOR=1 ./mk toml 2>&1)"
    unit_assert_contains "toml alias runs tombi" "files linted successfully" "$toml_out"
    bin_out="$(unit_run_in_dir "$root" cargo run -q -p sample-bin)"
    unit_assert_eq "sample-bin stdout golden" "10 + 20 = 30" "$bin_out"
}

test_mutants_plan_cli() {
    local root="$1"
    unit_assert_eq "mutants-plan full default" '{"mode":"full","mutants":5,"shards":1,"packages":["sample-bin","sample-lib"]}' \
        "$(unit_run_in_dir "$root" env NO_COLOR=1 ./mk mutants-plan --mode full)"
    unit_assert_eq "mutants-plan full sharded" '{"mode":"full","mutants":5,"shards":3,"packages":["sample-bin","sample-lib"]}' \
        "$(unit_run_in_dir "$root" env NO_COLOR=1 MUTANTS_TARGET_PER_SHARD=2 ./mk mutants-plan --mode full)"
    unit_assert_eq "mutants-plan full capped" '{"mode":"full","mutants":5,"shards":2,"packages":["sample-bin","sample-lib"]}' \
        "$(unit_run_in_dir "$root" env NO_COLOR=1 MUTANTS_TARGET_PER_SHARD=1 MUTANTS_MAX_SHARDS=2 ./mk mutants-plan --mode full)"
    unit_assert_fails_with "mutants-plan rejects invalid mode" "invalid --mode" unit_run_in_dir "$root" env NO_COLOR=1 ./mk mutants-plan --mode bogus
    unit_assert_fails_with "mutants-plan rejects zero target" "MUTANTS_TARGET_PER_SHARD must be a positive integer" \
        unit_run_in_dir "$root" env NO_COLOR=1 MUTANTS_TARGET_PER_SHARD=0 ./mk mutants-plan --mode full
    unit_assert_fails_with "mutants-plan rejects zero max shards" "MUTANTS_MAX_SHARDS must be a positive integer" \
        unit_run_in_dir "$root" env NO_COLOR=1 MUTANTS_MAX_SHARDS=0 ./mk mutants-plan --mode full
}

test_ratchet_and_adopt_cli() {
    local root="$1" tmp="$2" ratchet_dir="$2/ratchet-check" adopt_dir="$2/adopt-scratch"
    mkdir -p "$ratchet_dir" "$adopt_dir/src"
    cp "$root/mk" "$root/mk.versions" "$ratchet_dir/"
    cp -R "$root/.mk" "$ratchet_dir/.mk"
    printf 'COVERAGE_FAIL_UNDER_LINES="101"\n' >"$ratchet_dir/mk.local"
    unit_assert_fails_with "ratchet rejects >100 coverage" "COVERAGE_FAIL_UNDER_LINES must be an integer 0..=100" \
        unit_run_in_dir "$ratchet_dir" env NO_COLOR=1 ./mk ratchet
    printf 'COVERAGE_FAIL_UNDER_LINES="100"\nECHOES_MAX_APPROXIMATE="abc"\n' >"$ratchet_dir/mk.local"
    unit_assert_fails_with "ratchet rejects non-integer echoes max" "ECHOES_MAX_APPROXIMATE must be a non-negative integer" \
        unit_run_in_dir "$ratchet_dir" env NO_COLOR=1 ./mk ratchet

    printf '[package]\nname = "adopt-scratch"\nversion = "0.1.0"\nedition = "2024"\nlicense = "MIT"\n' >"$adopt_dir/Cargo.toml"
    printf '//! Scratch crate.\n' >"$adopt_dir/src/lib.rs"
    (cd "$adopt_dir" && cargo generate-lockfile --offline --quiet)
    unit_assert_contains "adopt dry-run plans mk" "would: add mk" "$(DRY_RUN=1 "$root/scripts/adopt.sh" "$adopt_dir")"
    [ ! -e "$adopt_dir/mk" ] || { printf 'FAIL [adopt dry-run wrote mk]\n' >&2; return 1; }
    DRY_RUN=0 "$root/scripts/adopt.sh" "$adopt_dir" >/dev/null
    unit_assert_contains "adopt second run is no-op" "0 change(s)" "$(DRY_RUN=0 "$root/scripts/adopt.sh" "$adopt_dir")"
    (cd "$adopt_dir" && git init -q && git add -A && git commit -qm base && git tag base)
    unit_assert_eq "mutants-plan diff clean" '{"mode":"diff","mutants":0,"shards":0,"packages":[]}' \
        "$(unit_run_in_dir "$adopt_dir" env NO_COLOR=1 MK_BASE=base ./mk mutants-plan --mode diff)"
}

run_unit_suite() {
    local root="${SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}" tmp rc=0
    tmp="$(mktemp -d)"
    test_spec_and_alias_helpers "$root" && test_budget_and_kv_helpers "$root" "$tmp" && \
        test_cli_surface "$root" && test_mutants_plan_cli "$root" && \
        test_ratchet_and_adopt_cli "$root" "$tmp" || rc=$?
    rm -rf "$tmp"
    return "$rc"
}

if [ "${BASH_SOURCE[0]:-}" = "$0" ]; then run_unit_suite; fi
