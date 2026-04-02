#!/bin/bash
# One-command setup for agentic tooling.
# Usage: ~/agentic/setup.sh [--aliases]

set -e

AGENTIC_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/bin"

mkdir -p "$BIN_DIR"

# Symlink CLI commands
ln -sf "$AGENTIC_DIR/tinit.sh" "$BIN_DIR/tinit"

# Clean up stale master-claude symlink if it exists
rm -f "$BIN_DIR/master-claude"

# Add ~/bin to PATH if not already there
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  SHELL_RC="$HOME/.bashrc"
  [[ "$(basename "$SHELL")" == "zsh" ]] && SHELL_RC="$HOME/.zshrc"
  echo "export PATH=\"\$HOME/bin:\$PATH\"" >> "$SHELL_RC"
  echo "Added ~/bin to PATH in $(basename "$SHELL_RC")"
fi

# Determine shell RC file
SHELL_RC="$HOME/.bashrc"
[[ "$(basename "$SHELL")" == "zsh" ]] && SHELL_RC="$HOME/.zshrc"

# Source ag.sh if not already sourced
if ! grep -qF "source $AGENTIC_DIR/ag.sh" "$SHELL_RC" 2>/dev/null && \
   ! grep -qF "source ~/agentic/ag.sh" "$SHELL_RC" 2>/dev/null; then
  echo "source $AGENTIC_DIR/ag.sh" >> "$SHELL_RC"
  echo "Added ag.sh to $(basename "$SHELL_RC")"
fi

# Optionally add aliases (--aliases flag)
if [[ " $* " == *" --aliases "* ]]; then
ALIASES=(
  'alias cl="claude --dangerously-enable-internet-mode --dangerously-skip-permissions"'
  'alias cx="codex --dangerously-enable-internet-mode --sandbox danger-full-access --ask-for-approval never"'
  'alias t="tmux"'
  'alias ts="tmux -CC new -A -s"'
  'alias tk="tmux kill-session -t"'
  'alias v="nvim"'
)

for alias_line in "${ALIASES[@]}"; do
  alias_name="$(echo "$alias_line" | sed 's/alias \([^=]*\)=.*/\1/')"
  alias_cmd="$(echo "$alias_line" | sed 's/alias [^=]*="\([^"]*\)".*/\1/' | awk '{print $1}')"
  if ! grep -qE "alias [^=]+=['\"]${alias_cmd}( |\"|')" "$SHELL_RC" 2>/dev/null; then
    echo "$alias_line" >> "$SHELL_RC"
    echo "Added alias: $alias_name"
  else
    echo "Skipped alias $alias_name: $alias_cmd is already aliased"
  fi
done
fi

echo "Setup complete. Available commands: tinit, ag"
echo "Run 'source $SHELL_RC' or start a new shell to activate."
