#!/bin/bash
# Tmux startup script for agentic workflow
# Usage: tinit [path] --session NAME [--no-attach] [--team [--show-all]]
#   path           - directory to cd into (default: current directory)
#   --session NAME - tmux session name (required)
#   --no-attach    - create session without attaching (for batch creation)
#   --team         - start a 3-agent team (Master, Executor, Validator)
#   --show-all     - show all agent panes (requires --team)

AGENTIC_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

SESSION=""
DIR=""
NO_ATTACH=false
TEAM_MODE=false
SHOW_ALL=false

_tinit_usage() {
  cat <<'EOF'
Usage: tinit [path] --session NAME [--no-attach] [--team [--show-all]]

Create a tmux session with Claude Code (left pane) and a shell (right pane).

Arguments:
  path             Directory to cd into (default: current directory)

Options:
  --session NAME   Tmux session name (required)
  --no-attach      Create session without attaching (for batch creation)
  --team           Start a 3-agent team (Master, Executor, Validator)
  --show-all       Show all agent panes side by side (requires --team)
  --help, -h       Show this help message

Layouts:
  Default:         [Claude] [Terminal]
  --team:          [Master] [Terminal]        (Executor/Validator in background)
  --team --show-all: [Master] [Executor] [Validator] [Terminal]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) _tinit_usage; exit 0 ;;
    --session) SESSION="$2"; shift 2 ;;
    --no-attach) NO_ATTACH=true; shift ;;
    --team) TEAM_MODE=true; shift ;;
    --show-all) SHOW_ALL=true; shift ;;
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
  echo "Usage: tinit [path] --session NAME [--no-attach] [--team [--show-all]]"
  echo "  --session NAME  required: tmux session name"
  exit 1
fi

if [[ "$SHOW_ALL" == true && "$TEAM_MODE" == false ]]; then
  echo "tinit: --show-all requires --team" >&2
  exit 1
fi

# Kill existing session if it exists
tmux kill-session -t "$SESSION" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Simple mode (no --team): Claude + terminal
# ---------------------------------------------------------------------------
if [[ "$TEAM_MODE" == false ]]; then
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
  exit 0
fi

# ---------------------------------------------------------------------------
# Team mode: Master + Executor + Validator
# ---------------------------------------------------------------------------

EXECUTOR_SESSION="${SESSION}-executor"
VALIDATOR_SESSION="${SESSION}-validator"

if [[ "$SHOW_ALL" == true ]]; then
  # --- 4-pane layout: Master | Executor | Validator | Terminal ---
  # All agents run directly in panes (no background sessions, no nesting).

  # Get launcher scripts for all 3 roles
  mapfile -t LAUNCHERS < <("$AGENTIC_DIR/team-start.sh" "$SESSION" "$DIR" --launchers-only)
  MASTER_LAUNCHER="${LAUNCHERS[0]}"
  EXECUTOR_LAUNCHER="${LAUNCHERS[1]}"
  VALIDATOR_LAUNCHER="${LAUNCHERS[2]}"

  # Create session with pane 0 (will be Master)
  tmux new-session -d -s "$SESSION" -c "$DIR"

  # Split into 4 equal vertical panes
  tmux split-window -h -t "$SESSION" -c "$DIR"
  tmux split-window -h -t "$SESSION:0.1" -c "$DIR"
  tmux split-window -h -t "$SESSION:0.2" -c "$DIR"

  # Even out the layout
  tmux select-layout -t "$SESSION" even-horizontal

  # Show pane titles in borders (for regular tmux users)
  tmux select-pane -t "$SESSION:0.0" -T "MASTER"
  tmux select-pane -t "$SESSION:0.1" -T "EXECUTOR"
  tmux select-pane -t "$SESSION:0.2" -T "VALIDATOR"
  tmux select-pane -t "$SESSION:0.3" -T "TERMINAL"
  tmux set-option -t "$SESSION" pane-border-status top
  tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "
  tmux set-option -t "$SESSION" set-titles on

  sleep 1

  # Set pane titles and launch agents.
  # Each pane: echo a visible banner, set terminal title, then launch.
  # The banner stays visible at the top of the pane scrollback.
  tmux send-keys -t "$SESSION:0.0" "echo '=== MASTER ===' && '$MASTER_LAUNCHER'" C-m
  tmux send-keys -t "$SESSION:0.1" "echo '=== EXECUTOR ===' && '$EXECUTOR_LAUNCHER'" C-m
  tmux send-keys -t "$SESSION:0.2" "echo '=== VALIDATOR ===' && '$VALIDATOR_LAUNCHER'" C-m
  tmux send-keys -t "$SESSION:0.3" "echo '=== TERMINAL ==='" C-m

  # Select the terminal pane
  tmux select-pane -t "$SESSION:0.3"

else
  # --- 2-pane layout: Master | Terminal ---
  # Executor and Validator run in background tmux sessions.

  # Get the Master prompt file (does not launch agents)
  MASTER_PROMPT_FILE="$("$AGENTIC_DIR/team-start.sh" "$SESSION" "$DIR" --master-prompt-file)"

  # Create a launcher script for the Master agent
  MASTER_LAUNCHER="$(mktemp "/tmp/agent-launcher-master-XXXXXX.sh")"
  cat > "$MASTER_LAUNCHER" <<LAUNCHER_EOF
#!/bin/bash
printf '\\033]2;MASTER\\007'
exec claude --dangerously-enable-internet-mode --dangerously-skip-permissions \\
  --settings '${AGENTIC_DIR}/profiles/master.json' \\
  --append-system-prompt "\$(cat '${MASTER_PROMPT_FILE}')"
LAUNCHER_EOF
  chmod +x "$MASTER_LAUNCHER"

  # Start Executor and Validator in background tmux sessions
  "$AGENTIC_DIR/team-start.sh" "$SESSION" "$DIR"

  # Create session with pane 0 (will be Master)
  tmux new-session -d -s "$SESSION" -c "$DIR"

  # Split vertically (left/right)
  tmux split-window -h -t "$SESSION" -c "$DIR"

  # Label panes
  tmux select-pane -t "$SESSION:0.0" -T "MASTER"
  tmux select-pane -t "$SESSION:0.1" -T "TERMINAL"

  # Show pane titles in the border
  tmux set-option -t "$SESSION" pane-border-status top
  tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "

  sleep 1

  # Pane 0: Master agent (via launcher script)
  tmux send-keys -t "$SESSION:0.0" "echo '=== MASTER ===' && '$MASTER_LAUNCHER'" C-m

  # Pane 1: Terminal banner
  tmux send-keys -t "$SESSION:0.1" "echo '=== TERMINAL ==='" C-m

  # Select the right pane (terminal)
  tmux select-pane -t "$SESSION:0.1"
fi

if [[ "$NO_ATTACH" == false ]]; then
  tmux -CC attach-session -t "$SESSION"
fi
