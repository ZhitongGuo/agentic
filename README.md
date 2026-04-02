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
ln -sf ~/agentic/master-claude/master-claude.sh ~/bin/master-claude

# Source gwt in your shell
echo 'source ~/agentic/gwt.sh' >> ~/.bashrc
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

### `gwt` — Git Worktree Manager

Creates and manages git worktrees for parallel agent workflows. Worktrees are created at `<repo-parent>/<repo>-<name>` with branch `<prefix>/<name>`.

```bash
gwt add task1                      # create worktree, cd into it
gwt add task1 task2 task3 --tmux   # create 3 worktrees with tmux sessions
gwt add task1 --team               # create worktree with 3-agent team
gwt add task1 --team --show-all    # team with all agents visible
gwt ls                             # list worktrees
gwt rm task1                       # remove worktree + branch + agent sessions
gwt rm 'task*' --force             # glob remove, force delete
```

| Subcommand | Description |
|------------|-------------|
| `gwt add <name> [...]` | Create worktree(s) |
| `gwt ls` | List worktrees for current repo |
| `gwt rm <pattern> [...]` | Remove worktree(s), kill tmux/agent sessions, delete branches |

**`gwt add` flags:**

| Flag | Description |
|------|-------------|
| `--tmux` / `-t` | Create tmux session(s) via `tinit` |
| `--team` | Start a 3-agent team (implies `--tmux`) |
| `--show-all` | Show all agent panes (requires `--team`) |
| `--no-cd` | Don't cd into the worktree |
| `--prefix PFX` | Override branch prefix (default: `$WT_BRANCH_PREFIX`) |
| `--branch NAME` | Use exact branch name (single worktree only) |

**`gwt rm` flags:**

| Flag | Description |
|------|-------------|
| `--force` | Force remove with uncommitted changes, force-delete branch |

Tab completion is available via `gwt-completion.bash` (auto-sourced).

### Agent Teams

When `--team` is passed to `gwt add` or `tinit`, three coordinated Claude agents are launched to work together on complex tasks:

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
gwt add rest-api --team

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
gwt add rest-api --team --show-all

# Clean up when done (kills all agent sessions + worktree)
gwt rm rest-api
```

#### Example: Quick Bug Fix with Full Visibility

```bash
# Show all agents side by side
gwt add bugfix --team --show-all

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
gwt add frontend backend database --team

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

The `.agent-comms/` directory is automatically created and added to `.gitignore` (or `.hgignore` for Sapling repos). It is cleaned up when you run `gwt rm`.

#### Direct User Interaction

You can talk directly to any agent, not just the Master. If you interact with the Executor or Validator directly (e.g., to give them additional context or override instructions), they will automatically notify the Master with a summary so it stays in sync.

### `master-claude` — Legacy Multi-Agent Orchestration

Spins up coordinated teams of Claude agents (Manager, Engineer, Reviewer) across isolated repo checkouts. See [`master-claude/README.md`](master-claude/README.md) for full documentation.

```bash
master-claude setup ~/myrepo 3    # create 3 checkouts
master-claude start 1             # start team 1
master-claude connect 1           # attach to team 1 manager
master-claude stop-all            # tear everything down
```

## File Structure

```
agentic/
├── README.md                     # This file
├── setup.sh                      # One-command setup script
├── tinit.sh                      # Tmux session initializer
├── gwt.sh                        # Worktree manager (sourced in .bashrc)
├── gwt-completion.bash           # Tab completion for gwt
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
├── profiles/                     # Claude CLI settings per agent role
│   ├── master.json
│   ├── executor.json
│   └── validator.json
└── master-claude/                # Legacy multi-agent orchestration
    ├── master-claude.sh          # Main CLI entrypoint
    ├── README.md                 # Detailed docs
    ├── profiles/                 # Claude CLI settings per agent role
    ├── prompts/                  # System prompts per agent role
    └── utils/                    # Bootstrap and launch scripts
```

## Aliases (optional)

Pass `--aliases` to `setup.sh` to add these to your shell RC (skipped if the command is already aliased):

| Alias | Command |
|-------|---------|
| `cl` | `claude --dangerously-enable-internet-mode --dangerously-skip-permissions` |
| `cx` | `codex --dangerously-enable-internet-mode --sandbox danger-full-access --ask-for-approval never` |
| `mc` | `master-claude` |
| `t` | `tmux` |
| `ts` | `tmux -CC new -A -s` |
| `tk` | `tmux kill-session -t` |
| `v` | `nvim` |

## Configuration

| Variable | Where | Default | Purpose |
|----------|-------|---------|---------|
| `WT_BRANCH_PREFIX` | shell env | `stephen` | Branch prefix for `gwt add` |
| `CHECKOUT_BASE` | `~/.master-claude/config` | `~/fbsource-multi` | Base dir for master-claude checkouts |
| `CHECKOUT_PREFIX` | `~/.master-claude/config` | `fbsource` | Checkout directory prefix |
