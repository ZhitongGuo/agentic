#!/bin/bash
# Shared test helpers for bats tests

AGENTIC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create a temporary git repo for testing
create_test_repo() {
  TEST_TMPDIR="$(mktemp -d)"
  TEST_REPO="$TEST_TMPDIR/test-repo"
  mkdir -p "$TEST_REPO"
  git -C "$TEST_REPO" init -b main
  git -C "$TEST_REPO" config user.email "test@test.com"
  git -C "$TEST_REPO" config user.name "Test"
  echo "initial" > "$TEST_REPO/file.txt"
  git -C "$TEST_REPO" add file.txt
  git -C "$TEST_REPO" commit -m "Initial commit"
}

# Source ag.sh in the test environment
source_ag() {
  source "$AGENTIC_DIR/ag.sh"
}

# Clean up temp repos, worktrees, and tmux sessions created during tests
cleanup_test_repo() {
  if [[ -n "${TEST_REPO:-}" ]]; then
    # Remove any worktrees we created
    git -C "$TEST_REPO" worktree list 2>/dev/null | while IFS= read -r line; do
      local wt_path
      wt_path="$(echo "$line" | awk '{print $1}')"
      if [[ "$wt_path" != "$TEST_REPO" && -d "$wt_path" ]]; then
        git -C "$TEST_REPO" worktree remove --force "$wt_path" 2>/dev/null || true
      fi
    done
  fi
  if [[ -n "${TEST_TMPDIR:-}" && -d "${TEST_TMPDIR:-}" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# Kill any tmux sessions matching a pattern
cleanup_tmux_sessions() {
  local pattern="${1:-test-repo-}"
  tmux list-sessions -F "#{session_name}" 2>/dev/null | while IFS= read -r sess; do
    if [[ "$sess" == ${pattern}* ]]; then
      tmux kill-session -t "$sess" 2>/dev/null || true
    fi
  done
}

# Assert a worktree directory exists
assert_worktree_exists() {
  local path="$1"
  [[ -d "$path" ]] || {
    echo "Expected worktree at $path to exist" >&2
    return 1
  }
}

# Assert a worktree directory does not exist
assert_worktree_not_exists() {
  local path="$1"
  [[ ! -d "$path" ]] || {
    echo "Expected worktree at $path to not exist" >&2
    return 1
  }
}

# Assert a tmux session exists
assert_tmux_session_exists() {
  local session="$1"
  tmux has-session -t "$session" 2>/dev/null || {
    echo "Expected tmux session '$session' to exist" >&2
    return 1
  }
}

# Assert a tmux session does not exist
assert_tmux_session_not_exists() {
  local session="$1"
  ! tmux has-session -t "$session" 2>/dev/null || {
    echo "Expected tmux session '$session' to not exist" >&2
    return 1
  }
}

# Assert output contains a string
assert_output_contains() {
  local expected="$1"
  [[ "$output" == *"$expected"* ]] || {
    echo "Expected output to contain '$expected'" >&2
    echo "Got: $output" >&2
    return 1
  }
}
