#!/bin/bash
# Tmux startup script for agentic workflow
# Usage: tinit [path] --session NAME [--no-attach] [--team [--show-all] [--editor]]
#   path           - directory to cd into (default: current directory)
#   --session NAME - tmux session name (required)
#   --no-attach    - create session without attaching (for batch creation)
#   --team         - start a 4-agent team (Master, Researcher, Executor, Validator)
#   --show-all     - show all agent panes (requires --team)
#   --editor       - include an nvim pane (requires --show-all)

AGENTIC_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

SESSION=""
DIR=""
NO_ATTACH=false
TEAM_MODE=false
SHOW_ALL=false
EDITOR_PANE=false

_tinit_usage() {
  cat <<'EOF'
Usage: tinit [path] --session NAME [--no-attach] [--team [--show-all] [--editor]]

Create a tmux session with Claude Code (left pane) and a shell (right pane).

Arguments:
  path             Directory to cd into (default: current directory)

Options:
  --session NAME   Tmux session name (required)
  --no-attach      Create session without attaching (for batch creation)
  --team           Start a 4-agent team (Master, Researcher, Executor, Validator)
  --show-all       Show all agent panes side by side (requires --team)
  --editor         Include an nvim pane
  --help, -h       Show this help message

Layouts:
  Default:           [Claude] [Terminal]
  --editor:          [Claude] [Nvim] [Terminal]
  --team:            [Master] [Terminal]  (agents in background)
  --team --editor:   [Master] [Nvim] [Terminal]
  --team --show-all:
    +----------+----------+-----------+
    |          | EXECUTOR | RESEARCHER|
    |  MASTER  +----------+-----------+
    |          | VALIDATOR| TERMINAL  |
    +----------+----------+-----------+
  --team --show-all --editor:
    +----------+------------+-----------+
    |          | RESEARCHER |   NVIM    |
    |  MASTER  | EXECUTOR   +-----------+
    |          | VALIDATOR  | TERMINAL  |
    +----------+------------+-----------+
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) _tinit_usage; exit 0 ;;
    --session) SESSION="$2"; shift 2 ;;
    --no-attach) NO_ATTACH=true; shift ;;
    --team) TEAM_MODE=true; shift ;;
    --show-all) SHOW_ALL=true; shift ;;
    --editor) EDITOR_PANE=true; shift ;;
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
  tmux new-session -d -s "$SESSION" -c "$DIR"
  tmux set-environment -t "$SESSION" AG_SESSION "solo"

  if [[ "$EDITOR_PANE" == true ]]; then
    # Layout: [Claude] [Nvim] [Terminal]
    #         left      mid    right
    tmux split-window -h -t "$SESSION:0.0" -c "$DIR" -p 66
    tmux split-window -h -t "$SESSION:0.1" -c "$DIR" -p 50

    sleep 1

    tmux send-keys -t "$SESSION:0.0" 'claude --dangerously-enable-internet-mode --dangerously-skip-permissions' C-m
    tmux send-keys -t "$SESSION:0.1" "nvim" C-m
    tmux select-pane -t "$SESSION:0.2"
  else
    # Layout: [Claude] [Terminal]
    tmux split-window -h -t "$SESSION" -c "$DIR"

    sleep 1

    tmux send-keys -t "$SESSION:0.0" 'claude --dangerously-enable-internet-mode --dangerously-skip-permissions' C-m
    tmux select-pane -t "$SESSION:0.1"
  fi

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
  # All agents run directly in panes (no background sessions, no nesting).

  if [[ "$EDITOR_PANE" == true ]]; then
    # Get launcher scripts with editor pane layout
    PANE_LAYOUT=editor mapfile -t LAUNCHERS < <("$AGENTIC_DIR/team-start.sh" "$SESSION" "$DIR" --launchers-only --pane-mode)
  else
    PANE_LAYOUT=no-editor mapfile -t LAUNCHERS < <("$AGENTIC_DIR/team-start.sh" "$SESSION" "$DIR" --launchers-only --pane-mode)
  fi
  MASTER_LAUNCHER="${LAUNCHERS[0]}"
  RESEARCHER_LAUNCHER="${LAUNCHERS[1]}"
  EXECUTOR_LAUNCHER="${LAUNCHERS[2]}"
  VALIDATOR_LAUNCHER="${LAUNCHERS[3]}"

  # Create session — pane 0 is Master (full height left)
  tmux new-session -d -s "$SESSION" -c "$DIR"

  # Tag as a team session so ag ls can identify it
  tmux set-environment -t "$SESSION" AG_TEAM_MODE "show-all"

  if [[ "$EDITOR_PANE" == true ]]; then
    # Layout with --editor:
    # +----------+------------+-----------+
    # |          | RESEARCHER |           |
    # |          +------------+   NVIM    |
    # |  MASTER  | EXECUTOR   |           |
    # |          +------------+-----------+
    # |          | VALIDATOR  | TERMINAL  |
    # +----------+------------+-----------+

    # Split right 2/3 for middle+right columns
    tmux split-window -h -t "$SESSION:0.0" -c "$DIR" -p 66

    # Split that into middle and right columns
    tmux split-window -h -t "$SESSION:0.1" -c "$DIR" -p 50

    # Split middle column into 3: Researcher / Executor / Validator
    tmux split-window -v -t "$SESSION:0.1" -c "$DIR" -p 66
    tmux split-window -v -t "$SESSION:0.2" -c "$DIR" -p 50

    # Split right column: Nvim (top) / Terminal (bottom)
    tmux split-window -v -t "$SESSION:0.4" -c "$DIR" -p 50

    # Panes:
    #   0 = Master (left, full height)
    #   1 = Researcher (top-middle)
    #   2 = Executor (mid-middle)
    #   3 = Validator (bottom-middle)
    #   4 = Nvim (top-right)
    #   5 = Terminal (bottom-right)

    sleep 1

    tmux send-keys -t "$SESSION:0.0" "'$MASTER_LAUNCHER'" C-m
    tmux send-keys -t "$SESSION:0.1" "'$RESEARCHER_LAUNCHER'" C-m
    tmux send-keys -t "$SESSION:0.2" "'$EXECUTOR_LAUNCHER'" C-m
    tmux send-keys -t "$SESSION:0.3" "'$VALIDATOR_LAUNCHER'" C-m
    tmux send-keys -t "$SESSION:0.4" "nvim" C-m

    # Select the terminal pane
    tmux select-pane -t "$SESSION:0.5"

  else
    # Layout without --editor:
    # +----------+----------+-----------+
    # |          | EXECUTOR | RESEARCHER|
    # |  MASTER  +----------+-----------+
    # |          | VALIDATOR| TERMINAL  |
    # +----------+----------+-----------+

    # Split into 3 columns
    tmux split-window -h -t "$SESSION:0.0" -c "$DIR" -p 66
    tmux split-window -h -t "$SESSION:0.1" -c "$DIR" -p 50

    # Split middle column: Executor (top) / Validator (bottom)
    tmux split-window -v -t "$SESSION:0.1" -c "$DIR" -p 50

    # Split right column: Researcher (top) / Terminal (bottom)
    tmux split-window -v -t "$SESSION:0.3" -c "$DIR" -p 50

    # Panes:
    #   0 = Master (left, full height)
    #   1 = Executor (top-middle)
    #   2 = Validator (bottom-middle)
    #   3 = Researcher (top-right)
    #   4 = Terminal (bottom-right)

    sleep 1

    tmux send-keys -t "$SESSION:0.0" "'$MASTER_LAUNCHER'" C-m
    tmux send-keys -t "$SESSION:0.1" "'$EXECUTOR_LAUNCHER'" C-m
    tmux send-keys -t "$SESSION:0.2" "'$VALIDATOR_LAUNCHER'" C-m
    tmux send-keys -t "$SESSION:0.3" "'$RESEARCHER_LAUNCHER'" C-m

    # Select the terminal pane
    tmux select-pane -t "$SESSION:0.4"
  fi

else
  # --- 2-pane layout: Master | Terminal ---
  # Executor and Validator run in background tmux sessions.

  # Get the Master prompt file (does not launch agents)
  MASTER_PROMPT_FILE="$("$AGENTIC_DIR/team-start.sh" "$SESSION" "$DIR" --master-prompt-file)"

  # Create a launcher script for the Master agent
  MASTER_LAUNCHER="$(mktemp "/tmp/agent-launcher-master-XXXXXX.sh")"
  cat > "$MASTER_LAUNCHER" <<LAUNCHER_EOF
#!/bin/bash
echo ""
echo "+------------------------+"
echo "|  MASTER                |"
echo "+------------------------+"
echo ""
exec claude --dangerously-enable-internet-mode --dangerously-skip-permissions \\
  --settings '${AGENTIC_DIR}/profiles/master.json' \\
  --append-system-prompt "\$(cat '${MASTER_PROMPT_FILE}')"
LAUNCHER_EOF
  chmod +x "$MASTER_LAUNCHER"

  # Start Executor and Validator in background tmux sessions
  "$AGENTIC_DIR/team-start.sh" "$SESSION" "$DIR"

  # Create session with pane 0 (will be Master)
  tmux new-session -d -s "$SESSION" -c "$DIR"

  # Tag as a team session so ag ps can identify it
  tmux set-environment -t "$SESSION" AG_TEAM_MODE "background"

  if [[ "$EDITOR_PANE" == true ]]; then
    # Layout: [Master] [Nvim] [Terminal]
    tmux split-window -h -t "$SESSION:0.0" -c "$DIR" -p 66
    tmux split-window -h -t "$SESSION:0.1" -c "$DIR" -p 50

    sleep 1

    tmux send-keys -t "$SESSION:0.0" "'$MASTER_LAUNCHER'" C-m
    tmux send-keys -t "$SESSION:0.1" "nvim" C-m
    tmux select-pane -t "$SESSION:0.2"
  else
    # Layout: [Master] [Terminal]
    tmux split-window -h -t "$SESSION" -c "$DIR"

    sleep 1

    tmux send-keys -t "$SESSION:0.0" "'$MASTER_LAUNCHER'" C-m
    tmux select-pane -t "$SESSION:0.1"
  fi
fi

if [[ "$NO_ATTACH" == false ]]; then
  tmux -CC attach-session -t "$SESSION"
fi
