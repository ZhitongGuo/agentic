#!/usr/bin/env bats

load "../setup"

@test "tinit: no --session shows error" {
  run "$AGENTIC_DIR/tinit.sh"
  [ "$status" -ne 0 ]
  assert_output_contains "--session NAME"
}

@test "tinit: --help prints usage and exits 0" {
  run "$AGENTIC_DIR/tinit.sh" --help
  [ "$status" -eq 0 ]
  assert_output_contains "Usage:"
  assert_output_contains "--session NAME"
}

@test "tinit: -h prints usage and exits 0" {
  run "$AGENTIC_DIR/tinit.sh" -h
  [ "$status" -eq 0 ]
  assert_output_contains "Usage:"
}

@test "tinit: --show-all without --team shows error" {
  run "$AGENTIC_DIR/tinit.sh" --session test --show-all
  [ "$status" -ne 0 ]
  assert_output_contains "--show-all requires --team"
}

@test "tinit: nonexistent directory shows error" {
  run "$AGENTIC_DIR/tinit.sh" /nonexistent/path --session test
  [ "$status" -ne 0 ]
  assert_output_contains "does not exist"
}
