//! Runs the built binary, so its entrypoint is covered and its mutants are caught.

use core::error::Error;
use std::process::Command;

#[test]
#[cfg_attr(miri, ignore = "miri cannot spawn processes")]
fn prints_sum() -> Result<(), Box<dyn Error>> {
    let output = Command::new(env!("CARGO_BIN_EXE_sample-bin")).output()?;
    assert!(
        output.status.success(),
        "binary exited with {}",
        output.status
    );
    assert_eq!(
        String::from_utf8(output.stdout)?,
        "10 + 20 = 30\n",
        "printed sum"
    );
    Ok(())
}
