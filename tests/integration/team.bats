#!/usr/bin/env bats

load "../setup"

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

@test "team: team-start.sh creates .agent-comms directory" {
  "$AGENTIC_DIR/team-start.sh" "test-repo-comms" "$TEST_REPO" --launchers-only > /dev/null
  [ -d "$TEST_REPO/.agent-comms" ]
}

@test "team: team-start.sh adds .agent-comms to .gitignore" {
  "$AGENTIC_DIR/team-start.sh" "test-repo-ignore" "$TEST_REPO" --launchers-only > /dev/null
  run grep -xF '.agent-comms/' "$TEST_REPO/.gitignore"
  [ "$status" -eq 0 ]
}

@test "team: team-start.sh does not duplicate .gitignore entry" {
  "$AGENTIC_DIR/team-start.sh" "test-repo-dup1" "$TEST_REPO" --launchers-only > /dev/null
  "$AGENTIC_DIR/team-start.sh" "test-repo-dup2" "$TEST_REPO" --launchers-only > /dev/null
  local count
  count="$(grep -cxF '.agent-comms/' "$TEST_REPO/.gitignore")"
  [ "$count" -eq 1 ]
}

@test "team: --launchers-only outputs 3 launcher paths" {
  run "$AGENTIC_DIR/team-start.sh" "test-repo-launchers" "$TEST_REPO" --launchers-only
  [ "$status" -eq 0 ]
  local line_count
  line_count="$(echo "$output" | wc -l)"
  [ "$line_count" -eq 3 ]
}

@test "team: launcher scripts are executable" {
  local launchers
  launchers="$("$AGENTIC_DIR/team-start.sh" "test-repo-exec" "$TEST_REPO" --launchers-only)"
  while IFS= read -r launcher; do
    [ -x "$launcher" ]
  done <<< "$launchers"
}

@test "team: --master-prompt-file outputs a file path" {
  run "$AGENTIC_DIR/team-start.sh" "test-repo-prompt" "$TEST_REPO" --master-prompt-file
  [ "$status" -eq 0 ]
  [ -f "$output" ]
}

@test "team: master prompt contains substituted session names" {
  local prompt_file
  prompt_file="$("$AGENTIC_DIR/team-start.sh" "test-repo-sub" "$TEST_REPO" --master-prompt-file)"
  run grep "test-repo-sub-executor" "$prompt_file"
  [ "$status" -eq 0 ]
  run grep "test-repo-sub-validator" "$prompt_file"
  [ "$status" -eq 0 ]
}

@test "team: team-stop.sh cleans up .agent-comms" {
  "$AGENTIC_DIR/team-start.sh" "test-repo-cleanup" "$TEST_REPO" --launchers-only > /dev/null
  [ -d "$TEST_REPO/.agent-comms" ]
  "$AGENTIC_DIR/team-stop.sh" "test-repo-cleanup" "$TEST_REPO"
  [ ! -d "$TEST_REPO/.agent-comms" ]
}

@test "team: team-stop.sh removes .agent-comms from .gitignore" {
  "$AGENTIC_DIR/team-start.sh" "test-repo-ignclean" "$TEST_REPO" --launchers-only > /dev/null
  run grep -xF '.agent-comms/' "$TEST_REPO/.gitignore"
  [ "$status" -eq 0 ]
  "$AGENTIC_DIR/team-stop.sh" "test-repo-ignclean" "$TEST_REPO"
  run grep -xF '.agent-comms/' "$TEST_REPO/.gitignore"
  [ "$status" -ne 0 ]
}

@test "team: ag rm cleans up .agent-comms and .gitignore" {
  ag add teamrm --no-tmux --no-cd
  local wt_path="$TEST_TMPDIR/test-repo-teamrm"
  "$AGENTIC_DIR/team-start.sh" "test-repo-teamrm" "$wt_path" --launchers-only > /dev/null
  [ -d "$wt_path/.agent-comms" ]
  # team-start modifies .gitignore, so cleanup + remove needs --force
  ag rm teamrm --force <<< "y"
  assert_worktree_not_exists "$wt_path"
}
