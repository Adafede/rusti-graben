#!/usr/bin/env bash
set -eo pipefail

TARGET_DIR="${1:-.}"
DRY_RUN="${DRY_RUN:-1}"

echo "==> Analyzing repository structure at: $TARGET_DIR"
if [ -f "$TARGET_DIR/Cargo.toml" ] && grep -q "\[workspace\]" "$TARGET_DIR/Cargo.toml"; then
    echo "    Detected: Cargo Workspace"
else
    echo "    Detected: Single Crate / Package"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> DRY-RUN mode active. Set DRY_RUN=0 to apply changes."
    echo "    Would apply deny.toml, rust-toolchain.toml, clippy.toml, and ./mk runner."
else
    echo "==> Applying hygiene files..."
    cp -n deny.toml "$TARGET_DIR/deny.toml"
    cp -n rust-toolchain.toml "$TARGET_DIR/rust-toolchain.toml"
    cp -n clippy.toml "$TARGET_DIR/clippy.toml"
    cp mk "$TARGET_DIR/mk"
    chmod +x "$TARGET_DIR/mk"
    echo "==> Adoption complete! Run ./mk ci to verify."
fi