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

# Source wt in your shell
echo 'source ~/agentic/gwt.sh' >> ~/.bashrc
source ~/.bashrc
```

## Commands

### `tinit` — Tmux Session Initializer

Creates a tmux session with a vertical split: left pane runs `claude --dangerously-enable-internet-mode --dangerously-skip-permissions`, right pane is a free shell.

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

### `gwt` — Git Worktree Manager

Creates and manages git worktrees for parallel agent workflows. Worktrees are created at `<repo-parent>/<repo>-<name>` with branch `<prefix>/<name>`.

```bash
gwt add task1                      # create worktree, cd into it
gwt add task1 task2 task3 --tmux   # create 3 worktrees with tmux sessions
gwt ls                             # list worktrees
gwt rm task1                       # remove worktree + branch
gwt rm 'task*' --force             # glob remove, force delete
```

| Subcommand | Description |
|------------|-------------|
| `gwt add <name> [...]` | Create worktree(s) |
| `gwt ls` | List worktrees for current repo |
| `gwt rm <pattern> [...]` | Remove worktree(s), kill tmux sessions, delete branches |

**`gwt add` flags:**

| Flag | Description |
|------|-------------|
| `--tmux` / `-t` | Create tmux session(s) via `tinit` |
| `--no-cd` | Don't cd into the worktree |
| `--prefix PFX` | Override branch prefix (default: `$WT_BRANCH_PREFIX`, currently `stephen`) |
| `--branch NAME` | Use exact branch name (single worktree only) |

**`gwt rm` flags:**

| Flag | Description |
|------|-------------|
| `--force` | Force remove with uncommitted changes, force-delete branch |

Tab completion is available via `gwt-completion.bash` (auto-sourced).

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
├── gwt.sh                         # Worktree manager (sourced in .bashrc)
├── gwt-completion.bash            # Tab completion for wt
└── master-claude/                # Multi-agent orchestration
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
