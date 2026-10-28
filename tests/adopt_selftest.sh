#!/usr/bin/env bash
set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Running adopt self-test (dry-run + structure checks)..."
# Dry run on template itself
DRY_RUN=1 "$REPO_ROOT/scripts/adopt.sh" "$REPO_ROOT"
echo "Self-test basic checks passed"
