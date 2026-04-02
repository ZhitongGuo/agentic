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

@test "worktree: ag add creates at correct path" {
  ag add feature1 --no-tmux
  local expected="$TEST_TMPDIR/test-repo-feature1"
  assert_worktree_exists "$expected"
  # Verify it's a valid git worktree
  run git -C "$expected" rev-parse --is-inside-work-tree
  [ "$output" = "true" ]
}

@test "worktree: ag add creates correct branch" {
  ag add feature1 --no-tmux
  local branch
  branch="$(git -C "$TEST_TMPDIR/test-repo-feature1" branch --show-current)"
  [ "$branch" = "stephen/feature1" ]
}

@test "worktree: ag add with existing branch reuses it" {
  git branch "stephen/reuse-me"
  run ag add reuse-me --no-tmux
  [ "$status" -eq 0 ]
  assert_output_contains "already exists, using it"
  assert_worktree_exists "$TEST_TMPDIR/test-repo-reuse-me"
}

@test "worktree: full lifecycle add -> ls -> rm" {
  # Add
  ag add lifecycle --no-tmux --no-cd
  assert_worktree_exists "$TEST_TMPDIR/test-repo-lifecycle"

  # Ls
  run ag ls
  assert_output_contains "lifecycle"

  # Rm
  ag rm lifecycle <<< "y"
  assert_worktree_not_exists "$TEST_TMPDIR/test-repo-lifecycle"

  # Verify branch deleted
  run git show-ref --verify "refs/heads/stephen/lifecycle"
  [ "$status" -ne 0 ]

  # Ls should show nothing
  run ag ls
  assert_output_contains "No worktrees found"
}

@test "worktree: multiple add and glob rm" {
  ag add task1 task2 task3 --no-tmux --no-cd
  assert_worktree_exists "$TEST_TMPDIR/test-repo-task1"
  assert_worktree_exists "$TEST_TMPDIR/test-repo-task2"
  assert_worktree_exists "$TEST_TMPDIR/test-repo-task3"

  ag rm 'task*' <<< "y"
  assert_worktree_not_exists "$TEST_TMPDIR/test-repo-task1"
  assert_worktree_not_exists "$TEST_TMPDIR/test-repo-task2"
  assert_worktree_not_exists "$TEST_TMPDIR/test-repo-task3"
}

@test "worktree: --no-cd does not change directory" {
  local orig_dir="$(pwd)"
  ag add nocd-test --no-tmux --no-cd
  [ "$(pwd)" = "$orig_dir" ]
  assert_worktree_exists "$TEST_TMPDIR/test-repo-nocd-test"
}
