#!/bin/bash
# Worktree management for parallel Claude agent workflows.
# Source this file in .bashrc: source ~/agentic/gwt.sh
#
# Usage:
#   gwt add <name> [name2 ...] [--no-tmux] [--no-cd] [--team [--show-all]]
#   gwt ls
#   gwt rm <pattern> [pattern2 ...] [--force]

AGENTIC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT_BRANCH_PREFIX="${WT_BRANCH_PREFIX:-stephen}"

gwt() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true

  case "$cmd" in
    add)  _gwt_add "$@" ;;
    ls)   _gwt_ls "$@" ;;
    rm)   _gwt_rm "$@" ;;
    help|--help|-h) _gwt_usage ;;
    *)
      echo "gwt: unknown command '$cmd'"
      _gwt_usage
      return 1
      ;;
  esac
}

_gwt_usage() {
  cat <<'EOF'
Usage:
  gwt add <name> [name2 ...] [--no-tmux] [--no-cd] [--team [--show-all]]
                             [--prefix PREFIX] [--branch BRANCH]
  gwt ls                                           List worktrees
  gwt rm <pattern> [pattern2 ...] [--force]        Remove worktree(s)

Options:
  --no-cd        (add) Don't cd into the worktree (single worktree only)
  --no-tmux      (add) Don't create a tmux session (just create the worktree)
  --team         (add) Start a 3-agent team (Master, Executor, Validator)
  --show-all     (add) Show all agent panes (requires --team)
  --prefix PFX   (add) Override branch prefix (default: $WT_BRANCH_PREFIX)
  --branch NAME  (add) Use exact branch name (single worktree only)
  --force        (rm)  Force remove even with uncommitted changes
EOF
}

_gwt_repo_info() {
  local toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "gwt: not inside a git repository" >&2
    return 1
  }
  REPO_ROOT="$toplevel"
  REPO_NAME="$(basename "$REPO_ROOT")"
  REPO_PARENT="$(dirname "$REPO_ROOT")"
}

_gwt_add() {
  local names=()
  local no_cd=false
  local use_tmux=true
  local use_team=false
  local show_all=false
  local prefix="$WT_BRANCH_PREFIX"
  local exact_branch=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-cd)     no_cd=true; shift ;;
      --no-tmux)   use_tmux=false; shift ;;
      -t|--tmux)   use_tmux=true; shift ;;
      --team)      use_team=true; use_tmux=true; shift ;;
      --show-all)  show_all=true; shift ;;
      --prefix)    prefix="$2"; shift 2 ;;
      --branch)    exact_branch="$2"; shift 2 ;;
      --*)         echo "gwt add: unknown flag '$1'"; return 1 ;;
      *)           names+=("$1"); shift ;;
    esac
  done

  if [[ "$show_all" == true && "$use_team" == false ]]; then
    echo "gwt add: --show-all requires --team"
    return 1
  fi

  if [[ ${#names[@]} -eq 0 ]]; then
    echo "gwt add: at least one name is required"
    echo "Usage: gwt add <name> [name2 ...] [--no-cd] [--tmux] [--prefix PREFIX] [--branch BRANCH]"
    return 1
  fi

  if [[ -n "$exact_branch" && ${#names[@]} -gt 1 ]]; then
    echo "gwt add: --branch can only be used with a single worktree"
    return 1
  fi

  _gwt_repo_info || return 1

  local created=()
  for name in "${names[@]}"; do
    local gwt_path="${REPO_PARENT}/${REPO_NAME}-${name}"
    local branch
    if [[ -n "$exact_branch" ]]; then
      branch="$exact_branch"
    else
      branch="${prefix}/${name}"
    fi

    if [[ -d "$gwt_path" ]]; then
      echo "gwt: worktree '${REPO_NAME}-${name}' already exists at $gwt_path"
      continue
    fi

    if git show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
      echo "gwt: branch '${branch}' already exists, using it"
      git worktree add "$gwt_path" "$branch" || {
        echo "gwt: failed to create worktree for '$name'"
        continue
      }
    else
      git worktree add -b "$branch" "$gwt_path" || {
        echo "gwt: failed to create worktree for '$name'"
        continue
      }
    fi

    echo "Created worktree: ${REPO_NAME}-${name} (branch: ${branch})"
    created+=("$name")
  done

  if [[ ${#created[@]} -eq 0 ]]; then
    return 1
  fi

  # Single worktree: cd or tmux
  if [[ ${#created[@]} -eq 1 ]]; then
    local name="${created[0]}"
    local gwt_path="${REPO_PARENT}/${REPO_NAME}-${name}"

    if [[ "$use_tmux" == true ]]; then
      local tinit_args=("$gwt_path" --session "${REPO_NAME}-${name}")
      if [[ "$use_team" == true ]]; then
        tinit_args+=(--team)
        if [[ "$show_all" == true ]]; then
          tinit_args+=(--show-all)
        fi
      fi
      "$AGENTIC_DIR/tinit.sh" "${tinit_args[@]}"
    elif [[ "$no_cd" == false ]]; then
      cd "$gwt_path" || return 1
      echo "Changed directory to $gwt_path"
    fi
    return 0
  fi

  # Multiple worktrees: tmux or just list
  if [[ "$use_tmux" == true ]]; then
    local last_idx=$(( ${#created[@]} - 1 ))
    for i in "${!created[@]}"; do
      local name="${created[$i]}"
      local gwt_path="${REPO_PARENT}/${REPO_NAME}-${name}"
      local session_name="${REPO_NAME}-${name}"

      local tinit_args=("$gwt_path" --session "$session_name")
      if [[ "$use_team" == true ]]; then
        tinit_args+=(--team)
        if [[ "$show_all" == true ]]; then
          tinit_args+=(--show-all)
        fi
      fi

      if [[ $i -eq $last_idx ]]; then
        "$AGENTIC_DIR/tinit.sh" "${tinit_args[@]}"
      else
        "$AGENTIC_DIR/tinit.sh" "${tinit_args[@]}" --no-attach
        echo "Created tmux session: $session_name (attach with: tmux -CC attach -t $session_name)"
      fi
    done
  else
    echo ""
    echo "Created ${#created[@]} worktrees. cd into any of them:"
    for name in "${created[@]}"; do
      echo "  cd ${REPO_PARENT}/${REPO_NAME}-${name}"
    done
  fi
}

_gwt_ls() {
  _gwt_repo_info || return 1

  local prefix="${REPO_PARENT}/${REPO_NAME}-"
  local found=false

  while IFS= read -r line; do
    local gwt_path gwt_branch
    gwt_path="$(echo "$line" | awk '{print $1}')"
    gwt_branch="$(echo "$line" | awk '{print $3}' | tr -d '[]')"

    # Skip the main worktree
    if [[ "$gwt_path" == "$REPO_ROOT" ]]; then
      continue
    fi

    # Only show worktrees that match our naming convention
    if [[ "$gwt_path" == ${prefix}* ]]; then
      local suffix="${gwt_path#${prefix}}"
      printf "  %-20s %-30s %s\n" "$suffix" "$gwt_branch" "$gwt_path"
      found=true
    fi
  done < <(git worktree list)

  if [[ "$found" == false ]]; then
    echo "No worktrees found for ${REPO_NAME}"
  fi
}

_gwt_get_worktree_names() {
  _gwt_repo_info 2>/dev/null || return 1
  local prefix="${REPO_PARENT}/${REPO_NAME}-"

  git worktree list 2>/dev/null | while IFS= read -r line; do
    local gwt_path
    gwt_path="$(echo "$line" | awk '{print $1}')"
    if [[ "$gwt_path" == ${prefix}* ]]; then
      echo "${gwt_path#${prefix}}"
    fi
  done
}

_gwt_rm() {
  local patterns=()
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)  force=true; shift ;;
      --*)      echo "gwt rm: unknown flag '$1'"; return 1 ;;
      *)        patterns+=("$1"); shift ;;
    esac
  done

  if [[ ${#patterns[@]} -eq 0 ]]; then
    echo "gwt rm: at least one name or pattern is required"
    echo "Usage: gwt rm <pattern> [pattern2 ...] [--force]"
    return 1
  fi

  _gwt_repo_info || return 1

  # Collect matching worktree names
  local all_names
  mapfile -t all_names < <(_gwt_get_worktree_names)
  local to_remove=()

  for pattern in "${patterns[@]}"; do
    local matched=false
    for name in "${all_names[@]}"; do
      # shellcheck disable=SC2254
      case "$name" in
        $pattern)
          # Avoid duplicates
          local already=false
          for existing in "${to_remove[@]:-}"; do
            if [[ "$existing" == "$name" ]]; then
              already=true
              break
            fi
          done
          if [[ "$already" == false ]]; then
            to_remove+=("$name")
          fi
          matched=true
          ;;
      esac
    done
    if [[ "$matched" == false ]]; then
      echo "gwt rm: no worktree matching '$pattern'"
    fi
  done

  if [[ ${#to_remove[@]} -eq 0 ]]; then
    echo "Nothing to remove."
    return 0
  fi

  # Confirm
  echo "Will remove the following worktrees:"
  for name in "${to_remove[@]}"; do
    echo "  ${REPO_NAME}-${name} (branch: ${WT_BRANCH_PREFIX}/${name})"
  done
  echo ""
  read -r -p "Proceed? [y/N] " confirm
  if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
    echo "Aborted."
    return 0
  fi

  # Remove
  for name in "${to_remove[@]}"; do
    local gwt_path="${REPO_PARENT}/${REPO_NAME}-${name}"
    local branch="${WT_BRANCH_PREFIX}/${name}"
    local session_name="${REPO_NAME}-${name}"

    # Kill team agent sessions
    "$AGENTIC_DIR/team-stop.sh" "$session_name" "$gwt_path" || true

    # Clean up .agent-comms artifacts that prevent worktree removal
    if [[ -d "$gwt_path/.agent-comms" ]]; then
      rm -rf "$gwt_path/.agent-comms"
    fi
    # Remove the .agent-comms/ line we appended to ignore files
    if [[ -f "$gwt_path/.gitignore" ]]; then
      sed -i '/^\.agent-comms\/$/d' "$gwt_path/.gitignore"
    fi
    if [[ -f "$gwt_path/.hgignore" ]]; then
      sed -i '/^\.agent-comms\/$/d' "$gwt_path/.hgignore"
    fi

    # Kill tmux session if it exists
    if tmux has-session -t "$session_name" 2>/dev/null; then
      tmux kill-session -t "$session_name"
      echo "Killed tmux session: $session_name"
    fi

    # If we're currently inside the worktree being removed, cd out first
    if [[ "$(pwd)" == "$gwt_path" || "$(pwd)" == "$gwt_path/"* ]]; then
      cd "$REPO_ROOT" || true
      echo "Changed directory back to $REPO_ROOT"
    fi

    # Remove worktree
    if [[ "$force" == true ]]; then
      git worktree remove --force "$gwt_path" 2>/dev/null || {
        echo "gwt: failed to remove worktree '$name'"
        continue
      }
    else
      git worktree remove "$gwt_path" 2>/dev/null || {
        echo "gwt: failed to remove worktree '$name' (use --force to override)"
        continue
      }
    fi

    # Delete branch
    if git show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
      if [[ "$force" == true ]]; then
        git branch -D "$branch" 2>/dev/null || true
      else
        git branch -d "$branch" 2>/dev/null || {
          echo "gwt: branch '$branch' has unmerged changes (use --force to delete)"
        }
      fi
    fi

    echo "Removed: ${REPO_NAME}-${name}"
  done
}

# Source completion if interactive
if [[ -n "${PS1:-}" ]] && [[ -f "$AGENTIC_DIR/gwt-completion.bash" ]]; then
  source "$AGENTIC_DIR/gwt-completion.bash"
fi
