#!/usr/bin/env bats

load "../setup"

# Skip all tests if tmux is not available
setup() {
  if ! command -v tmux &>/dev/null; then
    skip "tmux not available"
  fi
  create_test_repo
  source_ag
  cd "$TEST_REPO"
}

teardown() {
  cleanup_tmux_sessions "test-repo-"
  cleanup_test_repo
}

@test "tmux: tinit creates session with correct name" {
  "$AGENTIC_DIR/tinit.sh" "$TEST_REPO" --session test-repo-tmuxtest --no-attach
  assert_tmux_session_exists "test-repo-tmuxtest"
  tmux kill-session -t "test-repo-tmuxtest" 2>/dev/null
}

@test "tmux: tinit creates 2 panes" {
  "$AGENTIC_DIR/tinit.sh" "$TEST_REPO" --session test-repo-panes --no-attach
  local pane_count
  pane_count="$(tmux list-panes -t test-repo-panes 2>/dev/null | wc -l)"
  [ "$pane_count" -eq 2 ]
  tmux kill-session -t "test-repo-panes" 2>/dev/null
}

@test "tmux: ag rm kills tmux session" {
  "$AGENTIC_DIR/tinit.sh" "$TEST_REPO" --session test-repo-killme --no-attach
  # Create a worktree so ag rm has something to remove
  ag add killme --no-tmux --no-cd
  # Manually create the session with the right name
  tmux kill-session -t "test-repo-killme" 2>/dev/null
  tmux new-session -d -s "test-repo-killme"
  assert_tmux_session_exists "test-repo-killme"

  ag rm killme <<< "y"
  assert_tmux_session_not_exists "test-repo-killme"
}
