#!/bin/bash
# Worktree management for parallel Claude agent workflows.
# Source this file in .bashrc: source ~/agentic/wt.sh
#
# Usage:
#   wt add <name> [name2 ...] [--no-cd] [--tmux]
#   wt ls
#   wt rm <pattern> [pattern2 ...] [--force]

AGENTIC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT_BRANCH_PREFIX="${WT_BRANCH_PREFIX:-stephen}"

wt() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true

  case "$cmd" in
    add)  _wt_add "$@" ;;
    ls)   _wt_ls "$@" ;;
    rm)   _wt_rm "$@" ;;
    help|--help|-h) _wt_usage ;;
    *)
      echo "wt: unknown command '$cmd'"
      _wt_usage
      return 1
      ;;
  esac
}

_wt_usage() {
  cat <<'EOF'
Usage:
  wt add <name> [name2 ...] [--no-cd] [--tmux] [--prefix PREFIX] [--branch BRANCH]
  wt ls                                           List worktrees
  wt rm <pattern> [pattern2 ...] [--force]        Remove worktree(s)

Options:
  --no-cd        (add) Don't cd into the worktree (single worktree only)
  --tmux         (add) Create tmux session(s) via tinit
  --prefix PFX   (add) Override branch prefix (default: $WT_BRANCH_PREFIX)
  --branch NAME  (add) Use exact branch name (single worktree only)
  --force        (rm)  Force remove even with uncommitted changes
EOF
}

_wt_repo_info() {
  local toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "wt: not inside a git repository" >&2
    return 1
  }
  REPO_ROOT="$toplevel"
  REPO_NAME="$(basename "$REPO_ROOT")"
  REPO_PARENT="$(dirname "$REPO_ROOT")"
}

_wt_add() {
  local names=()
  local no_cd=false
  local use_tmux=false
  local prefix="$WT_BRANCH_PREFIX"
  local exact_branch=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-cd)   no_cd=true; shift ;;
      -t|--tmux) use_tmux=true; shift ;;
      --prefix)  prefix="$2"; shift 2 ;;
      --branch)  exact_branch="$2"; shift 2 ;;
      --*)       echo "wt add: unknown flag '$1'"; return 1 ;;
      *)         names+=("$1"); shift ;;
    esac
  done

  if [[ ${#names[@]} -eq 0 ]]; then
    echo "wt add: at least one name is required"
    echo "Usage: wt add <name> [name2 ...] [--no-cd] [--tmux] [--prefix PREFIX] [--branch BRANCH]"
    return 1
  fi

  if [[ -n "$exact_branch" && ${#names[@]} -gt 1 ]]; then
    echo "wt add: --branch can only be used with a single worktree"
    return 1
  fi

  _wt_repo_info || return 1

  local created=()
  for name in "${names[@]}"; do
    local wt_path="${REPO_PARENT}/${REPO_NAME}-${name}"
    local branch
    if [[ -n "$exact_branch" ]]; then
      branch="$exact_branch"
    else
      branch="${prefix}/${name}"
    fi

    if [[ -d "$wt_path" ]]; then
      echo "wt: worktree '${REPO_NAME}-${name}' already exists at $wt_path"
      continue
    fi

    if git show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
      echo "wt: branch '${branch}' already exists, using it"
      git worktree add "$wt_path" "$branch" || {
        echo "wt: failed to create worktree for '$name'"
        continue
      }
    else
      git worktree add -b "$branch" "$wt_path" || {
        echo "wt: failed to create worktree for '$name'"
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
    local wt_path="${REPO_PARENT}/${REPO_NAME}-${name}"

    if [[ "$use_tmux" == true ]]; then
      "$AGENTIC_DIR/tinit.sh" "$wt_path" --session "${REPO_NAME}-${name}"
    elif [[ "$no_cd" == false ]]; then
      cd "$wt_path" || return 1
      echo "Changed directory to $wt_path"
    fi
    return 0
  fi

  # Multiple worktrees: tmux or just list
  if [[ "$use_tmux" == true ]]; then
    local last_idx=$(( ${#created[@]} - 1 ))
    for i in "${!created[@]}"; do
      local name="${created[$i]}"
      local wt_path="${REPO_PARENT}/${REPO_NAME}-${name}"
      local session_name="${REPO_NAME}-${name}"

      if [[ $i -eq $last_idx ]]; then
        "$AGENTIC_DIR/tinit.sh" "$wt_path" --session "$session_name"
      else
        "$AGENTIC_DIR/tinit.sh" "$wt_path" --session "$session_name" --no-attach
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

_wt_ls() {
  _wt_repo_info || return 1

  local prefix="${REPO_PARENT}/${REPO_NAME}-"
  local found=false

  while IFS= read -r line; do
    local wt_path wt_branch
    wt_path="$(echo "$line" | awk '{print $1}')"
    wt_branch="$(echo "$line" | awk '{print $3}' | tr -d '[]')"

    # Skip the main worktree
    if [[ "$wt_path" == "$REPO_ROOT" ]]; then
      continue
    fi

    # Only show worktrees that match our naming convention
    if [[ "$wt_path" == ${prefix}* ]]; then
      local suffix="${wt_path#${prefix}}"
      printf "  %-20s %-30s %s\n" "$suffix" "$wt_branch" "$wt_path"
      found=true
    fi
  done < <(git worktree list)

  if [[ "$found" == false ]]; then
    echo "No worktrees found for ${REPO_NAME}"
  fi
}

_wt_get_worktree_names() {
  _wt_repo_info 2>/dev/null || return 1
  local prefix="${REPO_PARENT}/${REPO_NAME}-"

  git worktree list 2>/dev/null | while IFS= read -r line; do
    local wt_path
    wt_path="$(echo "$line" | awk '{print $1}')"
    if [[ "$wt_path" == ${prefix}* ]]; then
      echo "${wt_path#${prefix}}"
    fi
  done
}

_wt_rm() {
  local patterns=()
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)  force=true; shift ;;
      --*)      echo "wt rm: unknown flag '$1'"; return 1 ;;
      *)        patterns+=("$1"); shift ;;
    esac
  done

  if [[ ${#patterns[@]} -eq 0 ]]; then
    echo "wt rm: at least one name or pattern is required"
    echo "Usage: wt rm <pattern> [pattern2 ...] [--force]"
    return 1
  fi

  _wt_repo_info || return 1

  # Collect matching worktree names
  local all_names
  mapfile -t all_names < <(_wt_get_worktree_names)
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
      echo "wt rm: no worktree matching '$pattern'"
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
    local wt_path="${REPO_PARENT}/${REPO_NAME}-${name}"
    local branch="${WT_BRANCH_PREFIX}/${name}"
    local session_name="${REPO_NAME}-${name}"

    # Kill tmux session if it exists
    if tmux has-session -t "$session_name" 2>/dev/null; then
      tmux kill-session -t "$session_name"
      echo "Killed tmux session: $session_name"
    fi

    # If we're currently inside the worktree being removed, cd out first
    if [[ "$(pwd)" == "$wt_path" || "$(pwd)" == "$wt_path/"* ]]; then
      cd "$REPO_ROOT" || true
      echo "Changed directory back to $REPO_ROOT"
    fi

    # Remove worktree
    if [[ "$force" == true ]]; then
      git worktree remove --force "$wt_path" 2>/dev/null || {
        echo "wt: failed to remove worktree '$name'"
        continue
      }
    else
      git worktree remove "$wt_path" 2>/dev/null || {
        echo "wt: failed to remove worktree '$name' (use --force to override)"
        continue
      }
    fi

    # Delete branch
    if git show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
      if [[ "$force" == true ]]; then
        git branch -D "$branch" 2>/dev/null || true
      else
        git branch -d "$branch" 2>/dev/null || {
          echo "wt: branch '$branch' has unmerged changes (use --force to delete)"
        }
      fi
    fi

    echo "Removed: ${REPO_NAME}-${name}"
  done
}

# Source completion if interactive
if [[ -n "${PS1:-}" ]] && [[ -f "$AGENTIC_DIR/wt-completion.bash" ]]; then
  source "$AGENTIC_DIR/wt-completion.bash"
fi
