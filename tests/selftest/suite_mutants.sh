# shellcheck shell=bash
# Mutation testing, package-graph scoping, cap_lints, and planner selftests.

run_mutants_suite() {
    append_lib "$untested_fn"
    expect_fail mutants-diff "MISSED" "untested function added on the branch"

    printf '\npub mod extra;\n' >>"$LIB"
    printf '%s\n' "$untested_fn" >crates/sample-lib/src/extra.rs
    expect_fail mutants-diff "MISSED" "untested function in an untracked .rs file"

    printf 'MUTANTS_PACKAGES=(sample-lib)\n' >>mk.local
    printf '\nfn excluded_helper() -> usize { 1 }\n' >>crates/sample-bin/src/main.rs
    expect_rc_and_output 0 "no Rust changes in mutation scope against base" \
        "mutants-diff: fast-skips when only an excluded package changes" \
        ./mk mutants-diff

    printf '\nignored_mutants/\n' >>.gitignore
    mkdir -p ignored_mutants
    printf '%s\n' "$untested_fn" >ignored_mutants/extra.rs
    expect_rc_and_output 0 "no Rust changes in mutation scope against base" \
        "mutants-diff: ignores gitignored .rs files under --gitignore=true" \
        ./mk mutants-diff

    expect_pass "mutants: MUTANTS_IN_PLACE=1 succeeds without --jobs conflict" env MUTANTS_IN_PLACE=1 ./mk mutants -p sample-lib
    expect_pass "mutants: explicit --in-place succeeds without --jobs conflict" ./mk mutants -p sample-lib --in-place

    perl -0pi -e 's/\[workspace\.lints\.rust\]/[workspace.lints.rust]\ndead_code = "deny"/' Cargo.toml
    append_lib 'const fn masked_helper() -> usize {
    42
}

/// Exposes the masked helper.
#[must_use]
pub const fn exposed_masked_helper() -> usize {
    masked_helper()
}'
    expect_rc_and_output 0 "unviable" \
        "mutants: cap_lints=false masks dead_code-denied mutant as unviable" \
        ./mk mutants -p sample-lib --cap-lints=false -F 'replace exposed_masked_helper'

    # Re-apply fixture after reset inside expect_rc_and_output.
    perl -0pi -e 's/\[workspace\.lints\.rust\]/[workspace.lints.rust]\ndead_code = "deny"/' Cargo.toml
    append_lib 'const fn masked_helper() -> usize {
    42
}

/// Exposes the masked helper.
#[must_use]
pub const fn exposed_masked_helper() -> usize {
    masked_helper()
}'
    expect_fail_cmd "MISSED" "cap_lints=true prevents dead_code=deny from masking mutant as Unviable" \
        ./mk mutants -p sample-lib -F 'replace exposed_masked_helper'

    printf '\nfn downstream_untested() -> usize {\n    7\n}\n' >>crates/sample-bin/src/main.rs
    perl -pi -e 's/println!\(/let _ = downstream_untested();\n    println!(/' crates/sample-bin/src/main.rs
    git commit -qam "test: add downstream helper"
    local upstream_base
    upstream_base="$(git rev-parse HEAD)"
    printf '\n// upstream edit\n' >>"$LIB"
    MK_BASE="$upstream_base" expect_fail mutants-affected "MISSED" "upstream change mutates downstream dependent"

    expect_json_expr "mutants-plan: empty diff emits 0 mutants and 0 shards" \
        'd == {"mode":"diff","mutants":0,"shards":0,"packages":[]}' \
        "$(./mk mutants-plan --mode diff)"

    append_lib "$untested_fn"
    expect_json_expr "mutants-plan: diff plan outputs compact JSON with touched package" \
        'd["mode"]=="diff" and d["mutants"]>0 and d["shards"]==1 and d["packages"]==["sample-lib"]' \
        "$(./mk mutants-plan --mode diff)"

    expect_json_expr "mutants-plan: full plan computes multi-shard matrix JSON" \
        'd["mode"]=="full" and d["mutants"]>=5 and d["shards"]>=3 and d["packages"]==["sample-bin","sample-lib"]' \
        "$(MUTANTS_TARGET_PER_SHARD=2 ./mk mutants-plan --mode full)"
}
