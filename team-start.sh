#!/bin/bash
# Launches a team of 3 agents (Master, Executor, Validator) for a worktree.
# Called by tinit.sh when --team is passed.
#
# Usage: team-start.sh <session-base> <worktree-path>
#        team-start.sh <session-base> <worktree-path> --master-prompt-file
#   session-base       - base name for tmux sessions (e.g. "myrepo-feature")
#   worktree-path      - absolute path to the worktree directory
#   --master-prompt-file - only write the master prompt to a temp file and
#                          print the file path; do not launch agents
#
# Creates tmux sessions:
#   <session-base>-executor
#   <session-base>-validator
#
# The Master agent runs in the main tinit session (pane 0), not managed here.
# This script only starts the Executor and Validator background sessions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

SESSION_BASE="$1"
WORKTREE_PATH="$2"

MASTER_SESSION="$SESSION_BASE"
EXECUTOR_SESSION="${SESSION_BASE}-executor"
VALIDATOR_SESSION="${SESSION_BASE}-validator"

# --- Detect VCS and select common prompt ---
VCS_PROMPT=""
if [[ -d "$WORKTREE_PATH/.sl" ]]; then
  VCS_PROMPT="$SCRIPT_DIR/prompts/common/sapling.md"
elif git -C "$WORKTREE_PATH" rev-parse --git-dir &>/dev/null; then
  VCS_PROMPT="$SCRIPT_DIR/prompts/common/git.md"
fi

# --- Create .agent-comms directory ---
COMMS_DIR="$WORKTREE_PATH/.agent-comms"
mkdir -p "$COMMS_DIR"

# Add .agent-comms to .gitignore if not already there
if [[ -d "$WORKTREE_PATH/.sl" ]]; then
  # Sapling repo — use .hgignore
  IGNOREFILE="$WORKTREE_PATH/.hgignore"
  if [[ -f "$IGNOREFILE" ]]; then
    if ! grep -qxF '.agent-comms/' "$IGNOREFILE" 2>/dev/null; then
      echo '.agent-comms/' >> "$IGNOREFILE"
    fi
  else
    printf 'syntax: glob\n.agent-comms/\n' > "$IGNOREFILE"
  fi
else
  # Git repo — use .gitignore
  IGNOREFILE="$WORKTREE_PATH/.gitignore"
  if [[ -f "$IGNOREFILE" ]]; then
    if ! grep -qxF '.agent-comms/' "$IGNOREFILE" 2>/dev/null; then
      echo '.agent-comms/' >> "$IGNOREFILE"
    fi
  else
    echo '.agent-comms/' > "$IGNOREFILE"
  fi
fi

# --- Assemble system prompts ---
assemble_prompt() {
  local role="$1"
  local prompt=""

  # Role-specific prompt
  prompt="$(cat "$SCRIPT_DIR/prompts/${role}.md")"

  # Common prompts
  for f in "$SCRIPT_DIR/prompts/common/compaction.md" \
           "$SCRIPT_DIR/prompts/common/filesystem-rules.md"; do
    if [[ -f "$f" ]]; then
      prompt="$prompt"$'\n\n'"$(cat "$f")"
    fi
  done

  # VCS-specific prompt
  if [[ -n "$VCS_PROMPT" && -f "$VCS_PROMPT" ]]; then
    prompt="$prompt"$'\n\n'"$(cat "$VCS_PROMPT")"
  fi

  # Substitute placeholders
  prompt="${prompt//SESSION_NAME/$SESSION_BASE}"
  prompt="${prompt//WORKTREE_PATH/$WORKTREE_PATH}"
  prompt="${prompt//MASTER_SESSION/$MASTER_SESSION}"
  prompt="${prompt//EXECUTOR_SESSION/$EXECUTOR_SESSION}"
  prompt="${prompt//VALIDATOR_SESSION/$VALIDATOR_SESSION}"

  echo "$prompt"
}

# Write a prompt to a temp file and return the path
write_prompt_file() {
  local role="$1"
  local prompt_file
  prompt_file="$(mktemp "/tmp/agent-prompt-${role}-XXXXXX.md")"
  assemble_prompt "$role" > "$prompt_file"
  echo "$prompt_file"
}

# Write a launcher script that reads the prompt from a file
write_launcher() {
  local role="$1"
  local prompt_file="$2"
  local launcher
  launcher="$(mktemp "/tmp/agent-launcher-${role}-XXXXXX.sh")"
  local label
  label="$(echo "$role" | tr '[:lower:]' '[:upper:]')"
  cat > "$launcher" <<LAUNCHER_EOF
#!/bin/bash
echo ""
echo "╔══════════════════════════╗"
echo "║  ${label}$(printf '%*s' $((18 - ${#label})) '')║"
echo "╚══════════════════════════╝"
echo ""
exec claude --dangerously-enable-internet-mode --dangerously-skip-permissions \\
  --settings '${SCRIPT_DIR}/profiles/${role}.json' \\
  --append-system-prompt "\$(cat '${prompt_file}')"
LAUNCHER_EOF
  chmod +x "$launcher"
  echo "$launcher"
}

# --- Launch an agent in a background tmux session ---
launch_agent() {
  local role="$1"
  local session="$2"

  # Write prompt to a file and create a launcher script
  local prompt_file
  prompt_file="$(write_prompt_file "$role")"
  local launcher
  launcher="$(write_launcher "$role" "$prompt_file")"

  # Kill existing session if any
  tmux kill-session -t "$session" 2>/dev/null || true

  # Create new session in the worktree directory
  tmux new-session -d -s "$session" -c "$WORKTREE_PATH"

  # Wait for shell to initialize
  sleep 1

  # Launch Claude via the launcher script (avoids quoting issues with tmux send-keys)
  tmux send-keys -t "$session" "'$launcher'" C-m
}

# --- Main ---

MODE="${3:-}"

case "$MODE" in
  --master-prompt-file)
    # Only write the master prompt file and print its path
    write_prompt_file "master"
    exit 0
    ;;

  --launchers-only)
    # Write launcher scripts for all 3 roles and print their paths (one per line).
    # Does NOT create any tmux sessions. Used by tinit --show-all.
    for role in master executor validator; do
      prompt_file="$(write_prompt_file "$role")"
      write_launcher "$role" "$prompt_file"
    done
    exit 0
    ;;

  "")
    # Default: launch Executor and Validator in background tmux sessions
    echo "Starting Executor agent (session: $EXECUTOR_SESSION)..."
    launch_agent "executor" "$EXECUTOR_SESSION"

    echo "Starting Validator agent (session: $VALIDATOR_SESSION)..."
    launch_agent "validator" "$VALIDATOR_SESSION"

    echo "Team agents started."
    echo "  Executor: $EXECUTOR_SESSION"
    echo "  Validator: $VALIDATOR_SESSION"
    ;;

  *)
    echo "team-start.sh: unknown flag '$MODE'" >&2
    exit 1
    ;;
esac
