#!/bin/bash
# Worktree management for parallel Claude agent workflows.
# Source this file in .bashrc: source ~/agentic/ag.sh
#
# Usage:
#   ag add <name> [name2 ...] [--no-tmux] [--no-cd] [--team [--show-all]]
#   ag ls
#   ag rm <pattern> [pattern2 ...] [--force]

AGENTIC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT_BRANCH_PREFIX="${WT_BRANCH_PREFIX:-stephen}"

ag() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true

  case "$cmd" in
    add)  _ag_add "$@" ;;
    ls)   _ag_ps "$@" ;;
    wt)   _ag_wt "$@" ;;
    attach) _ag_attach "$@" ;;
    rm)   _ag_rm "$@" ;;
    help|--help|-h) _ag_usage ;;
    *)
      echo "ag: unknown command '$cmd'"
      _ag_usage
      return 1
      ;;
  esac
}

_ag_usage() {
  cat <<'EOF'
Usage:
  ag add <name> [name2 ...] [--no-tmux] [--no-cd] [--team [--show-all]]
                            [--prefix PREFIX] [--branch BRANCH]
  ag ls [--all]                                    List active sessions
  ag wt                                           List worktrees
  ag attach <name>                                Attach to a session
  ag rm <pattern> [pattern2 ...] [--force]        Remove worktree(s)

Options:
  --no-cd        (add) Don't cd into the worktree (single worktree only)
  --no-tmux      (add) Don't create a tmux session (just create the worktree)
  --team         (add) Start a 4-agent team (Master, Researcher, Executor, Validator)
  --show-all     (add) Show all agent panes (requires --team)
  --editor       (add) Include an nvim pane
  --prefix PFX   (add) Override branch prefix (default: $WT_BRANCH_PREFIX)
  --branch NAME  (add) Use exact branch name (single worktree only)
  --force        (rm)  Force remove even with uncommitted changes
EOF
}

_ag_repo_info() {
  local toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ag: not inside a git repository" >&2
    return 1
  }
  REPO_ROOT="$toplevel"
  REPO_NAME="$(basename "$REPO_ROOT")"
  REPO_PARENT="$(dirname "$REPO_ROOT")"
}

_ag_add() {
  local names=()
  local no_cd=false
  local use_tmux=true
  local use_team=false
  local show_all=false
  local editor_pane=false
  local prefix="$WT_BRANCH_PREFIX"
  local exact_branch=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-cd)     no_cd=true; shift ;;
      --no-tmux)   use_tmux=false; shift ;;
      -t|--tmux)   use_tmux=true; shift ;;
      --team)      use_team=true; use_tmux=true; shift ;;
      --show-all)  show_all=true; shift ;;
      --editor)    editor_pane=true; shift ;;
      --prefix)    prefix="$2"; shift 2 ;;
      --branch)    exact_branch="$2"; shift 2 ;;
      --*)         echo "ag add: unknown flag '$1'"; return 1 ;;
      *)           names+=("$1"); shift ;;
    esac
  done

  if [[ "$show_all" == true && "$use_team" == false ]]; then
    echo "ag add: --show-all requires --team"
    return 1
  fi


  if [[ ${#names[@]} -eq 0 ]]; then
    echo "ag add: at least one name is required"
    echo "Usage: ag add <name> [name2 ...] [--no-tmux] [--no-cd] [--prefix PREFIX] [--branch BRANCH]"
    return 1
  fi

  if [[ -n "$exact_branch" && ${#names[@]} -gt 1 ]]; then
    echo "ag add: --branch can only be used with a single worktree"
    return 1
  fi

  _ag_repo_info || return 1

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
      echo "ag: worktree '${REPO_NAME}-${name}' already exists at $wt_path"
      continue
    fi

    if git show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
      echo "ag: branch '${branch}' already exists, using it"
      git worktree add "$wt_path" "$branch" || {
        echo "ag: failed to create worktree for '$name'"
        continue
      }
    else
      git worktree add -b "$branch" "$wt_path" || {
        echo "ag: failed to create worktree for '$name'"
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
      local tinit_args=("$wt_path" --session "${REPO_NAME}-${name}")
      if [[ "$use_team" == true ]]; then
        tinit_args+=(--team)
        if [[ "$show_all" == true ]]; then
          tinit_args+=(--show-all)
        fi
      fi
      if [[ "$editor_pane" == true ]]; then
        tinit_args+=(--editor)
      fi
      "$AGENTIC_DIR/tinit.sh" "${tinit_args[@]}"
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

      local tinit_args=("$wt_path" --session "$session_name")
      if [[ "$use_team" == true ]]; then
        tinit_args+=(--team)
        if [[ "$show_all" == true ]]; then
          tinit_args+=(--show-all)
        fi
      fi
      if [[ "$editor_pane" == true ]]; then
        tinit_args+=(--editor)
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

_ag_wt() {
  _ag_repo_info || return 1

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

_ag_ps() {
  local show_all=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all|-a) show_all=true; shift ;;
      --*)      echo "ag ls: unknown flag '$1'"; return 1 ;;
      *)        shift ;;
    esac
  done

  _ag_repo_info 2>/dev/null
  local repo_name="${REPO_NAME:-}"
  if [[ "$show_all" == true ]]; then
    repo_name=""
  fi
  local session_data
  session_data="$(tmux list-sessions -F '#{session_name}|#{session_created}|#{session_activity}' 2>/dev/null)" || {
    echo "No tmux sessions running."
    return 0
  }

  # Filter sessions and collect output (avoid subshell so found propagates)
  local found=false
  local output=""

  while IFS='|' read -r sess created activity; do
    # Check ag tags
    local ag_session ag_team_mode
    ag_session="$(tmux show-environment -t "$sess" AG_SESSION 2>/dev/null | cut -d= -f2-)"
    ag_team_mode="$(tmux show-environment -t "$sess" AG_TEAM_MODE 2>/dev/null | cut -d= -f2-)"
    local is_ag=false
    [[ -n "$ag_session" || -n "$ag_team_mode" ]] && is_ag=true

    # Filter: without --all, show ag-tagged sessions OR sessions matching repo prefix
    if [[ "$show_all" == false ]]; then
      if [[ -n "$repo_name" ]]; then
        # Inside a repo: show tagged sessions OR sessions matching repo-name prefix
        if [[ "$is_ag" == false && "$sess" != "${repo_name}-"* ]]; then
          continue
        fi
      else
        # Outside a repo: only show tagged sessions
        if [[ "$is_ag" == false ]]; then
          continue
        fi
      fi
    fi

    # Determine type
    local type="-"
    if [[ "$is_ag" == true ]]; then
      type="solo"
      if [[ "$ag_team_mode" == "show-all" ]]; then
        type="team"
      elif [[ "$ag_team_mode" == "background" ]]; then
        type="master"
      elif [[ "$ag_session" == "executor" ]]; then
        type="executor"
      elif [[ "$ag_session" == "validator" ]]; then
        type="validator"
      fi
    fi

    # Format timestamps
    local created_fmt activity_fmt
    created_fmt="$(date -d "@$created" '+%m/%d %H:%M' 2>/dev/null || date -r "$created" '+%m/%d %H:%M' 2>/dev/null || echo "$created")"
    activity_fmt="$(date -d "@$activity" '+%m/%d %H:%M' 2>/dev/null || date -r "$activity" '+%m/%d %H:%M' 2>/dev/null || echo "$activity")"

    output+="$(printf "  %-25s %-8s %-18s %-18s\n" "$sess" "$type" "$created_fmt" "$activity_fmt")"$'\n'
    found=true
  done < <(echo "$session_data" | sort)

  if [[ "$found" == true ]]; then
    printf "  %-25s %-8s %-18s %-18s\n" "SESSION" "TYPE" "CREATED" "LAST ACTIVE"
    printf "  %-25s %-8s %-18s %-18s\n" "-------" "----" "-------" "-----------"
    printf "%s" "$output"
  else
    if [[ -n "$repo_name" ]]; then
      echo "No ag sessions found for ${repo_name}"
    else
      echo "No tmux sessions running."
    fi
  fi
}

_ag_attach() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "ag attach: session name required"
    echo "Usage: ag attach <name>"
    echo ""
    echo "Tip: run 'ag ls' to see available sessions"
    return 1
  fi

  # Try exact match first
  if tmux has-session -t "$name" 2>/dev/null; then
    tmux -CC attach-session -t "$name"
    return 0
  fi

  # Try with repo prefix (e.g. "feature" → "myrepo-feature")
  _ag_repo_info 2>/dev/null
  if [[ -n "${REPO_NAME:-}" ]]; then
    local prefixed="${REPO_NAME}-${name}"
    if tmux has-session -t "$prefixed" 2>/dev/null; then
      tmux -CC attach-session -t "$prefixed"
      return 0
    fi
  fi

  # Fuzzy match: find sessions containing the name
  local matches
  matches="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -F "$name" || true)"
  local count
  count="$(echo "$matches" | grep -c . 2>/dev/null || echo 0)"

  if [[ "$count" -eq 1 ]]; then
    tmux -CC attach-session -t "$matches"
    return 0
  elif [[ "$count" -gt 1 ]]; then
    echo "ag attach: multiple sessions match '$name':"
    echo "$matches" | while read -r s; do echo "  $s"; done
    echo ""
    echo "Be more specific, or use the full session name."
    return 1
  fi

  echo "ag attach: no session matching '$name'"
  echo "Run 'ag ls' to see available sessions."
  return 1
}

_ag_get_worktree_names() {
  _ag_repo_info 2>/dev/null || return 1
  local prefix="${REPO_PARENT}/${REPO_NAME}-"

  git worktree list 2>/dev/null | while IFS= read -r line; do
    local wt_path
    wt_path="$(echo "$line" | awk '{print $1}')"
    if [[ "$wt_path" == ${prefix}* ]]; then
      echo "${wt_path#${prefix}}"
    fi
  done
}

_ag_rm() {
  local patterns=()
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)  force=true; shift ;;
      --*)      echo "ag rm: unknown flag '$1'"; return 1 ;;
      *)        patterns+=("$1"); shift ;;
    esac
  done

  if [[ ${#patterns[@]} -eq 0 ]]; then
    echo "ag rm: at least one name or pattern is required"
    echo "Usage: ag rm <pattern> [pattern2 ...] [--force]"
    return 1
  fi

  _ag_repo_info 2>/dev/null
  local repo_name="${REPO_NAME:-}"

  # Build list of known worktrees from two sources:
  # 1. git worktree list (if inside a repo)
  # 2. ag-tagged tmux sessions (works from anywhere)
  local all_entries=()  # each: "name|wt_path|branch|session_name"

  # Source 1: git worktree list
  if [[ -n "$repo_name" ]]; then
    local prefix="${REPO_PARENT}/${REPO_NAME}-"
    while IFS= read -r line; do
      local wt_path
      wt_path="$(echo "$line" | awk '{print $1}')"
      if [[ "$wt_path" == ${prefix}* && "$wt_path" != "$REPO_ROOT" ]]; then
        local suffix="${wt_path#${prefix}}"
        all_entries+=("${suffix}|${wt_path}|${WT_BRANCH_PREFIX}/${suffix}|${REPO_NAME}-${suffix}")
      fi
    done < <(git worktree list 2>/dev/null)
  fi

  # Source 2: ag-tagged tmux sessions (catches worktrees from other repos)
  local sessions
  sessions="$(tmux list-sessions -F '#{session_name}|#{session_path}' 2>/dev/null || true)"
  while IFS='|' read -r sess sess_path; do
    [[ -z "$sess" ]] && continue
    # Skip executor/validator sessions
    [[ "$sess" == *"-executor" || "$sess" == *"-validator" ]] && continue
    # Only ag-tagged sessions
    local ag_tag
    ag_tag="$(tmux show-environment -t "$sess" AG_SESSION 2>/dev/null | cut -d= -f2-)"
    local ag_team
    ag_team="$(tmux show-environment -t "$sess" AG_TEAM_MODE 2>/dev/null | cut -d= -f2-)"
    [[ -z "$ag_tag" && -z "$ag_team" ]] && continue

    # Extract the short name from the session name (repo-name → name)
    local short_name="$sess"
    # Check if already added from git worktree list
    local already=false
    for existing in "${all_entries[@]:-}"; do
      if [[ "$existing" == *"|${sess}" ]]; then
        already=true
        break
      fi
    done
    if [[ "$already" == false ]]; then
      local wt_path="$sess_path"
      all_entries+=("${short_name}|${wt_path}|unknown|${sess}")
    fi
  done <<< "$sessions"

  # Match patterns against entries
  local to_remove=()

  for pattern in "${patterns[@]}"; do
    local matched=false
    for entry in "${all_entries[@]:-}"; do
      local entry_name="${entry%%|*}"
      local entry_session="${entry##*|}"
      # Match against: short name, full session name, or suffix
      local does_match=false
      # shellcheck disable=SC2254
      case "$entry_name" in $pattern|*-$pattern) does_match=true ;; esac
      # shellcheck disable=SC2254
      case "$entry_session" in $pattern) does_match=true ;; esac

      if [[ "$does_match" == true ]]; then
        local already=false
        for existing in "${to_remove[@]:-}"; do
          if [[ "$existing" == "$entry" ]]; then
            already=true
            break
          fi
        done
        if [[ "$already" == false ]]; then
          to_remove+=("$entry")
        fi
        matched=true
      fi
    done
    if [[ "$matched" == false ]]; then
      echo "ag rm: no worktree matching '$pattern'"
    fi
  done

  if [[ ${#to_remove[@]} -eq 0 ]]; then
    echo "Nothing to remove."
    return 0
  fi

  # Confirm
  echo "Will remove the following worktrees:"
  for entry in "${to_remove[@]}"; do
    IFS='|' read -r name wt_path branch session_name <<< "$entry"
    if [[ "$branch" != "unknown" ]]; then
      echo "  ${session_name} (branch: ${branch})"
    else
      echo "  ${session_name} (${wt_path})"
    fi
  done
  echo ""
  read -r -p "Proceed? [y/N] " confirm
  if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
    echo "Aborted."
    return 0
  fi

  # Remove
  for entry in "${to_remove[@]}"; do
    IFS='|' read -r name wt_path branch session_name <<< "$entry"
    _ag_rm_worktree "$name" "$wt_path" "$branch" "$session_name" "$force"
  done
}

# Shared worktree removal logic used by both _ag_rm and _ag_rm_anywhere.
_ag_rm_worktree() {
  local name="$1"
  local wt_path="$2"
  local branch="$3"
  local session_name="$4"
  local force="$5"

  # Kill team agent sessions
  "$AGENTIC_DIR/team-stop.sh" "$session_name" "$wt_path" || true

  # Clean up .agent-comms artifacts that prevent worktree removal
  if [[ -d "$wt_path/.agent-comms" ]]; then
    rm -rf "$wt_path/.agent-comms"
  fi
  # Remove the .agent-comms/ line we appended to ignore files
  if [[ -f "$wt_path/.gitignore" ]]; then
    sed -i '/^\.agent-comms\/$/d' "$wt_path/.gitignore"
  fi
  if [[ -f "$wt_path/.hgignore" ]]; then
    sed -i '/^\.agent-comms\/$/d' "$wt_path/.hgignore"
  fi

  # Kill tmux session if it exists
  if tmux has-session -t "$session_name" 2>/dev/null; then
    tmux kill-session -t "$session_name"
    echo "Killed tmux session: $session_name"
  fi

  # If we're currently inside the worktree being removed, cd out first
  if [[ "$(pwd)" == "$wt_path" || "$(pwd)" == "$wt_path/"* ]]; then
    cd "$(dirname "$wt_path")" || true
    echo "Changed directory to $(dirname "$wt_path")"
  fi

  # Remove worktree
  if [[ "$force" == true ]]; then
    git -C "$wt_path" worktree remove --force "$wt_path" 2>/dev/null || \
    git worktree remove --force "$wt_path" 2>/dev/null || {
      echo "ag: failed to remove worktree '$name'"
      return 1
    }
  else
    git -C "$wt_path" worktree remove "$wt_path" 2>/dev/null || \
    git worktree remove "$wt_path" 2>/dev/null || {
      echo "ag: failed to remove worktree '$name' (use --force to override)"
      return 1
    }
  fi

  # Delete branch (need to run from the main repo, not the worktree)
  local main_repo
  main_repo="$(git -C "$wt_path" worktree list 2>/dev/null | head -1 | awk '{print $1}')" || true
  if [[ -z "$main_repo" ]]; then
    # Worktree already removed, try to find main repo from parent dir
    for d in "$(dirname "$wt_path")"/*/; do
      if git -C "$d" rev-parse --show-toplevel &>/dev/null 2>&1; then
        main_repo="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || true
        break
      fi
    done
  fi

  if [[ -n "$main_repo" ]] && git -C "$main_repo" show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
    if [[ "$force" == true ]]; then
      git -C "$main_repo" branch -D "$branch" 2>/dev/null || true
    else
      git -C "$main_repo" branch -d "$branch" 2>/dev/null || {
        echo "ag: branch '$branch' has unmerged changes (use --force to delete)"
      }
    fi
  fi

  echo "Removed: $(basename "$wt_path")"
}

# Source completion if interactive
if [[ -n "${PS1:-}" ]] && [[ -f "$AGENTIC_DIR/ag-completion.bash" ]]; then
  source "$AGENTIC_DIR/ag-completion.bash"
fi
