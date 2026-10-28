#[test]
fn all_crates_have_workspace_lints() {
    let lib = std::fs::read_to_string("crates/sample-lib/Cargo.toml").unwrap();
    let bin = std::fs::read_to_string("crates/sample-bin/Cargo.toml").unwrap();
    assert!(lib.contains("[lints]"));
    assert!(lib.contains("workspace = true"));
    assert!(bin.contains("[lints]"));
    assert!(bin.contains("workspace = true"));
}
