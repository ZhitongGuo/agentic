# agentic

Tooling for parallel Claude Code workflows — tmux session management, git worktree helpers, and multi-agent orchestration.

## Quick Setup

```bash
git clone git@github.com:Chef-SWanger/agentic.git ~/agentic
```

Then run:

```bash
~/agentic/setup.sh
```

Or manually:

```bash
# Symlink commands into ~/bin (must be on PATH)
mkdir -p ~/bin
ln -sf ~/agentic/tinit.sh ~/bin/tinit
ln -sf ~/agentic/master-claude/master-claude.sh ~/bin/master-claude

# Source wt in your shell
echo 'source ~/agentic/wt.sh' >> ~/.bashrc
source ~/.bashrc
```

## Commands

### `tinit` — Tmux Session Initializer

Creates a tmux session with a vertical split: left pane runs `cl` (Claude), right pane is a free shell.

```bash
tinit --session work              # create + attach, uses cwd
tinit ~/project --session work    # create + attach, in ~/project
tinit --session work --no-attach  # create without attaching
```

| Flag | Description |
|------|-------------|
| `--session NAME` | **(required)** Session name |
| `--no-attach` | Create session without attaching |

Attaches with `tmux -CC` (iTerm2 control mode).

### `wt` — Git Worktree Manager

Creates and manages git worktrees for parallel agent workflows. Worktrees are created at `<repo-parent>/<repo>-<name>` with branch `<prefix>/<name>`.

```bash
wt add task1                      # create worktree, cd into it
wt add task1 task2 task3 --tmux   # create 3 worktrees with tmux sessions
wt ls                             # list worktrees
wt rm task1                       # remove worktree + branch
wt rm 'task*' --force             # glob remove, force delete
```

| Subcommand | Description |
|------------|-------------|
| `wt add <name> [...]` | Create worktree(s) |
| `wt ls` | List worktrees for current repo |
| `wt rm <pattern> [...]` | Remove worktree(s), kill tmux sessions, delete branches |

**`wt add` flags:**

| Flag | Description |
|------|-------------|
| `--tmux` / `-t` | Create tmux session(s) via `tinit` |
| `--no-cd` | Don't cd into the worktree |
| `--prefix PFX` | Override branch prefix (default: `$WT_BRANCH_PREFIX`, currently `stephen`) |
| `--branch NAME` | Use exact branch name (single worktree only) |

**`wt rm` flags:**

| Flag | Description |
|------|-------------|
| `--force` | Force remove with uncommitted changes, force-delete branch |

Tab completion is available via `wt-completion.bash` (auto-sourced).

### `master-claude` — Multi-Agent Orchestration

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
├── wt.sh                         # Worktree manager (sourced in .bashrc)
├── wt-completion.bash            # Tab completion for wt
└── master-claude/                # Multi-agent orchestration
    ├── master-claude.sh          # Main CLI entrypoint
    ├── README.md                 # Detailed docs
    ├── profiles/                 # Claude CLI settings per agent role
    ├── prompts/                  # System prompts per agent role
    └── utils/                    # Bootstrap and launch scripts
```

## Configuration

| Variable | Where | Default | Purpose |
|----------|-------|---------|---------|
| `WT_BRANCH_PREFIX` | shell env | `stephen` | Branch prefix for `wt add` |
| `CHECKOUT_BASE` | `~/.master-claude/config` | `~/fbsource-multi` | Base dir for master-claude checkouts |
| `CHECKOUT_PREFIX` | `~/.master-claude/config` | `fbsource` | Checkout directory prefix |
