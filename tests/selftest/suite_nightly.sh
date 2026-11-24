# shellcheck shell=bash
# shellcheck disable=SC2154  # LIB_TOML, WORK, untested_fn from harness.sh / gate_selftest.sh
# Nightly tier gate violation-injection tests.

run_nightly_suite() {
    append_lib "$untested_fn"
    expect_fail mutants "MISSED" "untested function (surviving mutant)"

    MUTANTS_MIN_FREE_DISK_GB=1000000 expect_fail mutants "not starting cargo-mutants" "free disk below the mutants floor"

    printf 'LOCAL_OVERRIDES=(mutants)\n' >>mk.local
    expect_fail mutants "cannot replace mutants" "a repository task replacing the bounded mutants runner"

    append_lib "$untested_fn"
    expect_fail coverage "coverage" "line coverage below the floor"

    printf '\n[features]\nextra = []\n' >>"$LIB_TOML"
    append_lib '#[cfg(feature = "extra")]
pub fn feature_broken() -> usize {
    "wrong"
}'
    expect_fail powerset "mismatched types" "feature-only compilation error"

    append_lib '#[cfg(test)]
mod miri_leak {
    #[test]
    fn leak() {
        std::mem::forget(Box::new(1u8));
    }
}'
    # cargo-miri bakes the current temp $WORK path into test runner stubs.
    CARGO_TARGET_DIR="$WORK/target-miri" expect_fail miri "memory leaked" "memory leak under Miri"

    printf '\n[dependencies]\nitoa = "0.4"\n' >>"$LIB_TOML"
    expect_fail outdated "itoa" "outdated dependency"
}
