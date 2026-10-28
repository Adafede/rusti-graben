//! Deliberately-killed-mutant example test
//! This test exists to demonstrate mutation testing catches logic errors.

use sample_lib::add;

#[test]
fn add_kills_mutants() {
    assert_eq!(add(0, 0), 0);
    assert_eq!(add(1, 2), 3);
    assert_eq!(add(5, 7), 12);
    assert_eq!(add(usize::MAX, 0), usize::MAX);
}
