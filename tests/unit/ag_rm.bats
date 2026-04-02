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

@test "ag rm: no pattern provided shows error" {
  run ag rm
  [ "$status" -ne 0 ]
  assert_output_contains "at least one name or pattern is required"
}

@test "ag rm: unknown flag shows error" {
  run ag rm --invalid
  [ "$status" -ne 0 ]
  assert_output_contains "unknown flag"
}

@test "ag rm: non-matching pattern shows message" {
  run ag rm nonexistent <<< "y"
  assert_output_contains "no worktree matching"
}

@test "ag rm: removes worktree" {
  ag add testwork --no-tmux --no-cd
  assert_worktree_exists "$TEST_TMPDIR/test-repo-testwork"
  ag rm testwork <<< "y"
  assert_worktree_not_exists "$TEST_TMPDIR/test-repo-testwork"
}

@test "ag rm: removes branch after worktree removal" {
  ag add testwork --no-tmux --no-cd
  ag rm testwork <<< "y"
  run git show-ref --verify "refs/heads/stephen/testwork"
  [ "$status" -ne 0 ]
}

@test "ag rm: aborts on no confirmation" {
  ag add testwork --no-tmux --no-cd
  ag rm testwork <<< "n"
  assert_worktree_exists "$TEST_TMPDIR/test-repo-testwork"
}

@test "ag rm: glob pattern matches multiple worktrees" {
  ag add work1 work2 work3 --no-tmux --no-cd
  ag rm 'work*' <<< "y"
  assert_worktree_not_exists "$TEST_TMPDIR/test-repo-work1"
  assert_worktree_not_exists "$TEST_TMPDIR/test-repo-work2"
  assert_worktree_not_exists "$TEST_TMPDIR/test-repo-work3"
}

@test "ag rm: --force removes dirty worktree" {
  ag add testwork --no-tmux --no-cd
  echo "dirty" > "$TEST_TMPDIR/test-repo-testwork/newfile.txt"
  ag rm testwork --force <<< "y"
  assert_worktree_not_exists "$TEST_TMPDIR/test-repo-testwork"
}
