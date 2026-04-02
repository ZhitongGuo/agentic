#!/bin/bash
# Stops team agents (Executor and Validator) for a given session base name.
# Optionally cleans up .agent-comms/ and ignore file entries in the worktree.
# Called during gwt rm to clean up agent sessions.
#
# Usage: team-stop.sh <session-base> [worktree-path]
#   session-base  - base name used when starting the team (e.g. "myrepo-feature")
#   worktree-path - (optional) path to the worktree to clean up artifacts from

SESSION_BASE="$1"
WORKTREE_PATH="${2:-}"

if [[ -z "$SESSION_BASE" ]]; then
  echo "Usage: team-stop.sh <session-base> [worktree-path]"
  exit 1
fi

# Kill agent tmux sessions
for suffix in executor validator; do
  session="${SESSION_BASE}-${suffix}"
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux kill-session -t "$session"
    echo "Stopped: $session"
  fi
done

# Clean up worktree artifacts if path provided
if [[ -n "$WORKTREE_PATH" && -d "$WORKTREE_PATH" ]]; then
  # Remove .agent-comms directory
  if [[ -d "$WORKTREE_PATH/.agent-comms" ]]; then
    rm -rf "$WORKTREE_PATH/.agent-comms"
  fi

  # Remove the .agent-comms/ line from ignore files
  if [[ -f "$WORKTREE_PATH/.gitignore" ]]; then
    sed -i '/^\.agent-comms\/$/d' "$WORKTREE_PATH/.gitignore"
  fi
  if [[ -f "$WORKTREE_PATH/.hgignore" ]]; then
    sed -i '/^\.agent-comms\/$/d' "$WORKTREE_PATH/.hgignore"
  fi
fi
