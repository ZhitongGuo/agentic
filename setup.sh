#!/bin/bash
# One-command setup for agentic tooling.
# Usage: ~/agentic/setup.sh

set -e

AGENTIC_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/bin"

mkdir -p "$BIN_DIR"

# Symlink CLI commands
ln -sf "$AGENTIC_DIR/tinit.sh" "$BIN_DIR/tinit"
ln -sf "$AGENTIC_DIR/master-claude/master-claude.sh" "$BIN_DIR/master-claude"

# Add ~/bin to PATH if not already there
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  SHELL_RC="$HOME/.bashrc"
  [[ "$(basename "$SHELL")" == "zsh" ]] && SHELL_RC="$HOME/.zshrc"
  echo "export PATH=\"\$HOME/bin:\$PATH\"" >> "$SHELL_RC"
  echo "Added ~/bin to PATH in $(basename "$SHELL_RC")"
fi

# Source wt.sh if not already sourced
SHELL_RC="$HOME/.bashrc"
[[ "$(basename "$SHELL")" == "zsh" ]] && SHELL_RC="$HOME/.zshrc"
if ! grep -qF "source $AGENTIC_DIR/wt.sh" "$SHELL_RC" 2>/dev/null && \
   ! grep -qF "source ~/agentic/wt.sh" "$SHELL_RC" 2>/dev/null; then
  echo "source $AGENTIC_DIR/wt.sh" >> "$SHELL_RC"
  echo "Added wt.sh to $(basename "$SHELL_RC")"
fi

echo "Setup complete. Available commands: tinit, wt, master-claude"
echo "Run 'source $SHELL_RC' or start a new shell to activate."
