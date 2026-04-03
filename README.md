# agentic

Tooling for parallel Claude Code workflows — tmux session management, git worktree helpers, and multi-agent orchestration.

## Quick Setup

```bash
git clone git@github.com:Chef-SWanger/agentic.git ~/agentic
```

Then run:

```bash
~/agentic/setup.sh              # core setup only
~/agentic/setup.sh --aliases    # also add shell aliases
```

Or manually:

```bash
# Symlink commands into ~/bin (must be on PATH)
mkdir -p ~/bin
ln -sf ~/agentic/tinit.sh ~/bin/tinit

# Source ag in your shell
echo 'source ~/agentic/ag.sh' >> ~/.bashrc
source ~/.bashrc
```

## Commands

### `tinit` — Tmux Session Initializer

Creates a tmux session with a vertical split: left pane runs Claude Code, right pane is a free shell. Supports both simple (single agent) and team (multi-agent) modes.

```bash
tinit --session work              # create + attach, uses cwd
tinit ~/project --session work    # create + attach, in ~/project
tinit --session work --no-attach  # create without attaching
tinit --session work --team       # start a 3-agent team
tinit --session work --team --show-all  # team with all agents visible
```

| Flag | Description |
|------|-------------|
| `--session NAME` | **(required)** Session name |
| `--no-attach` | Create session without attaching |
| `--team` | Start a 3-agent team (Master, Executor, Validator) |
| `--show-all` | Show all agent panes side by side (requires `--team`) |

**Layouts:**

| Mode | Layout |
|------|--------|
| Default | `[Claude] [Terminal]` |
| `--team` | `[Master] [Terminal]` — Executor/Validator in background sessions |
| `--team --show-all` | `[Master] [Executor] [Validator] [Terminal]` |

Attaches with `tmux -CC` (iTerm2 control mode). Each pane is labeled with its role in the terminal/tab title.

### `ag` — Agentic Workflow Manager

Creates and manages git worktrees for parallel agent workflows. Worktrees are created at `<repo-parent>/<repo>-<name>` with branch `<prefix>/<name>`.

```bash
ag add task1                            # create worktree + tmux session (default)
ag add task1 --no-tmux                  # create worktree only, no tmux
ag add task1 task2 task3                # create 3 worktrees with tmux sessions
ag add task1 --team                     # create worktree with 3-agent team
ag add task1 --team --show-all          # team with all agents visible
ag add task1 --team --show-all --editor # team + nvim pane
ag ls                                   # list active sessions (current repo)
ag ls --all                             # list all sessions across all repos
ag wt                                   # list worktrees
ag attach feature                       # attach to a session (fuzzy match)
ag rm task1                             # remove worktree + branch + sessions
ag rm 'task*' --force                   # glob remove, force delete
```

| Subcommand | Description |
|------------|-------------|
| `ag add <name> [...]` | Create worktree(s) with tmux sessions |
| `ag ls [--all]` | List active tmux sessions (type, created, last active) |
| `ag wt` | List worktrees for current repo |
| `ag attach <name>` | Attach to a session (exact, repo-prefixed, or fuzzy match) |
| `ag rm <pattern> [...]` | Remove worktree(s), kill sessions, delete branches |

**`ag add` flags:**

| Flag | Description |
|------|-------------|
| `--no-tmux` | Don't create a tmux session (just create the worktree) |
| `--team` | Start a 3-agent team (Master, Executor, Validator) |
| `--show-all` | Show all agent panes (requires `--team`) |
| `--editor` | Include an nvim pane |
| `--no-cd` | Don't cd into the worktree |
| `--prefix PFX` | Override branch prefix (default: `$WT_BRANCH_PREFIX`) |
| `--branch NAME` | Use exact branch name (single worktree only) |

**`ag rm` flags:**

| Flag | Description |
|------|-------------|
| `--force` | Force remove with uncommitted changes, force-delete branch |

Tab completion is available via `ag-completion.bash` (auto-sourced).

### Agent Teams

When `--team` is passed to `ag add` or `tinit`, three coordinated Claude agents are launched to work together on complex tasks:

```
User ◄──► Master ──► Executor ──► Validator
           │  ◄── escalation ◄── feedback ──┘
           │
           └──► User can also talk directly to Executor/Validator
                (they will update Master to keep it in sync)
```

| Role | Responsibilities |
|------|-----------------|
| **Master** | User-facing. Collaborates with the user to brainstorm, plan, and break down the project into tasks. Creates execution plans and validation plans. Delegates all implementation to the Executor — never writes code itself. Handles escalations when the Executor is blocked or fails validation repeatedly. |
| **Executor** | Receives tasks from Master and implements them. Asks Master for clarification when specs are ambiguous. On completion, notifies the Validator. If validation fails, retries up to 5 times before escalating to Master for help or human intervention. |
| **Validator** | Receives validation specs from Master. When Executor signals task completion, validates the work against the plan. Always performs a mandatory code review (correctness, syntax, quality, security, edge cases) even if not in the validation plan. Reports pass/fail with detailed feedback to Executor. |

#### Example: Building a REST API

```bash
# 1. Create a worktree with a team for a complex feature
ag add rest-api --team

# 2. You now have a Master agent (left) and terminal (right).
#    Tell the Master what you want:
#
#    > "I want to build a REST API for user management with CRUD endpoints,
#      authentication, and input validation. Use Express and PostgreSQL."
#
# 3. Master will:
#    - Brainstorm the architecture with you
#    - Break it into tasks (e.g., "set up Express server", "add user model",
#      "implement POST /users", "add JWT auth", etc.)
#    - Create a validation plan for each task
#    - Delegate tasks one at a time to the Executor
#
# 4. For each task, the flow is automatic:
#    Master writes task spec → Executor implements → Validator reviews
#    If validation fails, Executor retries. After 5 failures, Master steps in.
#
# 5. Master reports back to you after each validated task.

# To see all agents working in real-time:
ag add rest-api --team --show-all

# Clean up when done (kills all agent sessions + worktree)
ag rm rest-api
```

#### Example: Quick Bug Fix with Full Visibility

```bash
# Show all agents side by side
ag add bugfix --team --show-all

# You'll see 4 labeled panes:
#   [MASTER] [EXECUTOR] [VALIDATOR] [TERMINAL]
#
# Tell Master: "Fix the null pointer exception in UserService.getUser()
# when the user ID doesn't exist in the database."
#
# You can also talk directly to Executor or Validator — they'll notify
# Master to stay in sync.
```

#### Example: Multiple Parallel Teams

```bash
# Spin up multiple worktrees with teams for parallel development
ag add frontend backend database --team

# Each worktree gets its own independent team of 3 agents.
# The last one attaches; the others run in background sessions.
#
# Connect to any team's tmux session:
#   tmux -CC attach -t myrepo-frontend
#   tmux -CC attach -t myrepo-backend
```

#### Communication

Agents use a hybrid approach:

- **tmux signals**: Short status messages (`TASK COMPLETE`, `VALIDATION PASSED`, `BLOCKED`, etc.) sent via `tmux send-keys`
- **File-based specs**: Detailed task specs, validation plans, and review feedback written to `.agent-comms/` in the worktree

| File | Direction | Purpose |
|------|-----------|---------|
| `.agent-comms/task-{N}.md` | Master → Executor | Task specification with acceptance criteria |
| `.agent-comms/validation-plan-{N}.md` | Master → Validator | What to verify (tests, behavior, edge cases) |
| `.agent-comms/validation-result-{N}.md` | Validator → Executor | Pass/fail with detailed feedback |

The `.agent-comms/` directory is automatically created and added to `.gitignore` (or `.hgignore` for Sapling repos). It is cleaned up when you run `ag rm`.

#### Direct User Interaction

You can talk directly to any agent, not just the Master. If you interact with the Executor or Validator directly (e.g., to give them additional context or override instructions), they will automatically notify the Master with a summary so it stays in sync.

## File Structure

```
agentic/
├── README.md                     # This file
├── setup.sh                      # One-command setup script
├── tinit.sh                      # Tmux session initializer
├── ag.sh                         # Agentic workflow manager (sourced in .bashrc)
├── ag-completion.bash            # Tab completion for ag
├── team-start.sh                 # Launches agent team sessions
├── team-stop.sh                  # Stops agent team sessions
├── prompts/                      # Agent system prompts
│   ├── master.md                 # Master agent prompt
│   ├── executor.md               # Executor agent prompt
│   ├── validator.md              # Validator agent prompt
│   └── common/                   # Shared prompt fragments
│       ├── compaction.md         # Context preservation rules
│       ├── filesystem-rules.md   # Safe filesystem operation rules
│       ├── git.md                # Git-specific VCS instructions
│       └── sapling.md            # Sapling-specific VCS instructions
└── profiles/                     # Claude CLI settings per agent role
    ├── master.json
    ├── executor.json
    └── validator.json
```

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core) (installed automatically on first run).

```bash
./tests/run.sh              # run all tests
./tests/run.sh unit         # unit tests only (argument parsing, validation)
./tests/run.sh integration  # integration tests (worktree lifecycle, tmux, team agents)
```

## Aliases (optional)

Pass `--aliases` to `setup.sh` to add these to your shell RC (skipped if the command is already aliased):

| Alias | Command |
|-------|---------|
| `cl` | `claude --dangerously-enable-internet-mode --dangerously-skip-permissions` |
| `cx` | `codex --dangerously-enable-internet-mode --sandbox danger-full-access --ask-for-approval never` |
| `t` | `tmux` |
| `ts` | `tmux -CC new -A -s` |
| `tk` | `tmux kill-session -t` |
| `v` | `nvim` |

## Configuration

| Variable | Where | Default | Purpose |
|----------|-------|---------|---------|
| `WT_BRANCH_PREFIX` | shell env | `stephen` | Branch prefix for `ag add` |
