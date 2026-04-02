#!/usr/bin/env bats

load "../setup"

setup() {
  create_test_repo
  source_ag
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "ag ls: no worktrees shows message" {
  run ag ls
  [ "$status" -eq 0 ]
  assert_output_contains "No worktrees found"
}

@test "ag ls: lists created worktrees" {
  ag add work1 --no-tmux
  run ag ls
  [ "$status" -eq 0 ]
  assert_output_contains "work1"
}

@test "ag ls: lists multiple worktrees" {
  ag add work1 work2 --no-tmux
  run ag ls
  [ "$status" -eq 0 ]
  assert_output_contains "work1"
  assert_output_contains "work2"
}

@test "ag ls: shows branch name" {
  ag add myfeature --no-tmux --no-cd
  run ag ls
  assert_output_contains "stephen/myfeature"
}
