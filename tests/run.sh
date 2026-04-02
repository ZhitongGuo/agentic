#!/bin/bash
# Test runner for agentic tooling
# Usage: ./tests/run.sh [unit|integration]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTIC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BATS_DIR="$AGENTIC_DIR/.bats"
BATS_BIN="$BATS_DIR/bats-core/bin/bats"

# Install bats-core locally if not present
if [[ ! -x "$BATS_BIN" ]]; then
  echo "Installing bats-core..."
  mkdir -p "$BATS_DIR"
  git clone --depth 1 https://github.com/bats-core/bats-core.git "$BATS_DIR/bats-core" 2>/dev/null
  echo "bats-core installed at $BATS_DIR/bats-core"
fi

SUITE="${1:-all}"

case "$SUITE" in
  unit)
    echo "Running unit tests..."
    "$BATS_BIN" "$SCRIPT_DIR/unit/"*.bats
    ;;
  integration)
    echo "Running integration tests..."
    "$BATS_BIN" "$SCRIPT_DIR/integration/"*.bats
    ;;
  all)
    echo "Running all tests..."
    "$BATS_BIN" "$SCRIPT_DIR/unit/"*.bats "$SCRIPT_DIR/integration/"*.bats
    ;;
  *)
    echo "Usage: $0 [unit|integration|all]"
    exit 1
    ;;
esac
