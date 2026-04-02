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

@test "ag add: no name provided shows error" {
  run ag add
  [ "$status" -ne 0 ]
  assert_output_contains "at least one name is required"
}

@test "ag add: --show-all without --team shows error" {
  run ag add foo --show-all --no-tmux
  [ "$status" -ne 0 ]
  assert_output_contains "--show-all requires --team"
}

@test "ag add: --branch with multiple names shows error" {
  run ag add foo bar --branch mybranch --no-tmux
  [ "$status" -ne 0 ]
  assert_output_contains "--branch can only be used with a single worktree"
}

@test "ag add: unknown flag shows error" {
  run ag add foo --invalid-flag
  [ "$status" -ne 0 ]
  assert_output_contains "unknown flag"
}

@test "ag add: creates worktree with correct name" {
  run ag add testwork --no-tmux
  [ "$status" -eq 0 ]
  assert_worktree_exists "$TEST_TMPDIR/test-repo-testwork"
}

@test "ag add: creates worktree with correct branch" {
  ag add testwork --no-tmux
  local branch
  branch="$(git -C "$TEST_TMPDIR/test-repo-testwork" branch --show-current)"
  [ "$branch" = "stephen/testwork" ]
}

@test "ag add: --prefix overrides branch prefix" {
  ag add testwork --no-tmux --prefix custom
  local branch
  branch="$(git -C "$TEST_TMPDIR/test-repo-testwork" branch --show-current)"
  [ "$branch" = "custom/testwork" ]
}

@test "ag add: --branch uses exact branch name" {
  ag add testwork --no-tmux --branch my-exact-branch
  local branch
  branch="$(git -C "$TEST_TMPDIR/test-repo-testwork" branch --show-current)"
  [ "$branch" = "my-exact-branch" ]
}

@test "ag add: duplicate worktree shows already exists message" {
  ag add testwork --no-tmux
  run ag add testwork --no-tmux
  assert_output_contains "already exists"
}

@test "ag add: multiple worktrees created" {
  run ag add work1 work2 --no-tmux
  [ "$status" -eq 0 ]
  assert_worktree_exists "$TEST_TMPDIR/test-repo-work1"
  assert_worktree_exists "$TEST_TMPDIR/test-repo-work2"
}
