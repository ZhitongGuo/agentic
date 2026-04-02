#!/bin/bash
# Bash completion for gwt (worktree manager)

_gwt_completions() {
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
        COMPREPLY=($(compgen -W "--no-cd --no-tmux --team --show-all --prefix --branch" -- "$cur"))
      fi
      ;;
    rm)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--force" -- "$cur"))
      else
        # Complete with existing worktree names
        local names
        names="$(_gwt_get_worktree_names 2>/dev/null)"
        COMPREPLY=($(compgen -W "$names" -- "$cur"))
      fi
      ;;
  esac
}

complete -F _gwt_completions gwt
