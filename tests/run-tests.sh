#!/usr/bin/env bash
# run-tests.sh - run scripts/audit_repo.sh against every fixture and assert
# the exit code (0 clean, 1 WARN, 2 BLOCK) plus the rule label that must fire.
#
# Fixtures are inert text. Cases that need a .git folder get one created at
# runtime inside a temp directory, because a nested .git cannot be committed.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="$HERE/../scripts/audit_repo.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/audit-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# --- runtime setup for fixtures that need a .git folder --------------------

setup_git_hooks() {
  mkdir -p "$1/.git/hooks"
  printf '[core]\n\trepositoryformatversion = 0\n' > "$1/.git/config"
  printf '#!/bin/sh\necho inert fixture\n' > "$1/.git/hooks/post-checkout"
  printf '#!/bin/sh\n' > "$1/.git/hooks/pre-commit.sample"
}

setup_git_config_fsmonitor() {
  mkdir -p "$1/.git/hooks"
  printf '[core]\n\trepositoryformatversion = 0\n\tfsmonitor = ./inert-fixture.sh\n' > "$1/.git/config"
}

setup_clean_git() {
  mkdir -p "$1/.git/hooks"
  printf '[core]\n\trepositoryformatversion = 0\n[remote "origin"]\n\turl = https://github.com/example/example.git\n' > "$1/.git/config"
  printf '#!/bin/sh\n' > "$1/.git/hooks/pre-commit.sample"
}

# --- test runner -----------------------------------------------------------

# check NAME FIXTURE EXPECTED_EXIT EXPECTED_PATTERN
check() {
  local name="$1" fixture="$2" want_code="$3" want_pat="$4"
  local work="$TMP/$name" out code setup

  cp -R "$HERE/fixtures/$fixture" "$work"
  setup="setup_${name//-/_}"
  if declare -F "$setup" > /dev/null; then "$setup" "$work"; fi

  out="$(bash "$AUDIT" "$work" 2>&1)"
  code=$?

  if [ "$code" -ne "$want_code" ]; then
    printf 'FAIL  %-24s exit %s, wanted %s\n' "$name" "$code" "$want_code"
    fail=$((fail + 1))
    return
  fi
  if [ -n "$want_pat" ] && ! printf '%s\n' "$out" | grep -qE "$want_pat"; then
    printf 'FAIL  %-24s output is missing /%s/\n' "$name" "$want_pat"
    fail=$((fail + 1))
    return
  fi
  printf 'ok    %-24s exit %s\n' "$name" "$code"
  pass=$((pass + 1))
}

#     name                    fixture                exit  expected output pattern
check clean                   clean                  0     'SUGGESTED VERDICT: AMAN'
check clean-git               clean                  0     'OK: only \.sample files'
check pipe-to-shell           pipe-to-shell          2     '\[BLOCK\] pipe-to-shell'
check git-hooks               git-hooks              2     '\[BLOCK\] git-hooks'
check git-config-fsmonitor    git-config-fsmonitor   2     '\[BLOCK\] git-config'
check claude-settings-hooks   claude-settings-hooks  2     '\[BLOCK\] claude-hooks'
check npm-postinstall         npm-postinstall        1     '\[WARN\] npm-lifecycle'
check prompt-injection        prompt-injection       1     '\[WARN\] prompt-injection'

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
