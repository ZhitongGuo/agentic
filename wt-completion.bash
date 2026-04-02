#!/bin/bash
# Bash completion for wt (worktree manager)

_wt_completions() {
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
    COMPREPLY=($(compgen -W "add ls rm help" -- "$cur"))
    return
  fi

  case "$subcmd" in
    add)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--no-cd --tmux --prefix --branch" -- "$cur"))
      fi
      ;;
    rm)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--force" -- "$cur"))
      else
        # Complete with existing worktree names
        local names
        names="$(_wt_get_worktree_names 2>/dev/null)"
        COMPREPLY=($(compgen -W "$names" -- "$cur"))
      fi
      ;;
  esac
}

complete -F _wt_completions wt
