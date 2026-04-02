#!/bin/bash
# Tmux startup script for agentic workflow
# Usage: tinit [path] --session NAME [--no-attach]
#   path           - directory to cd into (default: current directory)
#   --session NAME - tmux session name (required)
#   --no-attach    - create session without attaching (for batch creation)

SESSION=""
DIR=""
NO_ATTACH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    --no-attach) NO_ATTACH=true; shift ;;
    *) DIR="$1"; shift ;;
  esac
done

DIR="${DIR:-.}"
_orig_dir="$DIR"
DIR="$(cd "$DIR" && pwd)" || {
  echo "tinit: directory '${_orig_dir}' does not exist" >&2
  exit 1
}

if [[ -z "$SESSION" ]]; then
  echo "Usage: tinit [path] --session NAME [--no-attach]"
  echo "  --session NAME  required: tmux session name"
  exit 1
fi

# Kill existing session if it exists
tmux kill-session -t "$SESSION" 2>/dev/null

# Create new session, left pane
tmux new-session -d -s "$SESSION" -c "$DIR"

# Split vertically (left/right)
tmux split-window -h -t "$SESSION" -c "$DIR"

# Wait for shell to initialize before sending command
sleep 1

# Send claude command to the left pane (pane 0)
tmux send-keys -t "$SESSION:0.0" 'claude --dangerously-enable-internet-mode --dangerously-skip-permissions' C-m

# Select the right pane
tmux select-pane -t "$SESSION:0.1"

if [[ "$NO_ATTACH" == false ]]; then
  tmux -CC attach-session -t "$SESSION"
fi
