#!/bin/bash
# Bash completion for ag (agentic workflow manager)

_ag_completions() {
  local cur prev subcmd
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # Determine subcommand
  subcmd=""
  if [[ ${COMP_CWORD} -ge 2 ]]; then
    subcmd="${COMP_WORDS[1]}"
  fi

  # Complete subcommand
  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=($(compgen -W "add ls wt attach rm update help" -- "$cur"))
    return
  fi

  case "$subcmd" in
    add)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--no-cd --no-tmux --team --show-all --editor --prefix --branch" -- "$cur"))
      fi
      ;;
    ls)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--all" -- "$cur"))
      fi
      ;;
    attach)
      local sessions
      sessions="$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"
      COMPREPLY=($(compgen -W "$sessions" -- "$cur"))
      ;;
    rm)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--force" -- "$cur"))
      else
        # Complete with worktree names + ag-tagged session names
        local names
        names="$(_ag_get_worktree_names 2>/dev/null)"
        # Also add ag-tagged session names (for cross-repo removal)
        local ag_sessions
        ag_sessions="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -r s; do
          [[ "$s" == *"-executor" || "$s" == *"-validator" ]] && continue
          tmux show-environment -t "$s" AG_SESSION 2>/dev/null | grep -q '=' && echo "$s"
          tmux show-environment -t "$s" AG_TEAM_MODE 2>/dev/null | grep -q '=' && echo "$s"
        done | sort -u)"
        COMPREPLY=($(compgen -W "$names $ag_sessions" -- "$cur"))
      fi
      ;;
  esac
}

complete -F _ag_completions ag
