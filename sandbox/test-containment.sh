#!/bin/bash
# test-containment.sh — end-to-end tests for the sandbox wrapper.
#
# Run from a NORMAL terminal, not inside a sandboxed agent session: Seatbelt
# doesn't nest, so this script refuses to run if it's already sandboxed.
#
# Uses a temp config via $INFORMATION_GUARD_CONFIG — your real config is
# untouched. Test files live under a throwaway dir in $HOME (not temp,
# because temp dirs are allow-listed and would confound the write tests).

set -u
SANDBOX="$(cd "$(dirname "$0")" && pwd)/sandbox.mjs"

# Refuse to run nested (Seatbelt doesn't nest)
if ! /usr/bin/sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null; then
  echo "ERROR: this shell is already sandboxed (Seatbelt doesn't nest)."
  echo "Run from a normal terminal, not from inside a wrapped agent."
  exit 1
fi

WORK=$(mktemp -d "$HOME/ig-test-XXXXXX")
DOTFILE="$HOME/.ig-test-dotfile-$$"
DOTLINK="$HOME/.ig-test-link-$$"
cleanup() {
  rm -rf "$WORK" "$DOTFILE" "$DOTLINK"
  rm -f "$HOME/ig-test-outside-file" "$HOME/.ssh/ig-test-stray-$$"
}
trap cleanup EXIT

mkdir -p "$WORK/protected" "$WORK/allowed" "$WORK/workspace" "$WORK/linktarget"
echo "secret" > "$WORK/protected/secret.txt"
ln -s "$WORK/linktarget" "$DOTLINK"

export INFORMATION_GUARD_CONFIG="$WORK/config.json"
cat > "$INFORMATION_GUARD_CONFIG" <<EOF
{
  "protectedPaths": ["$WORK/protected"],
  "writeContainment": { "enabled": true, "allowWrite": ["$WORK/allowed"] }
}
EOF

pass=0
fail=0

# run <workspace-dir> <cmd...> — run a command through the wrapper with the
# given directory as the launch cwd (= the workspace containment allows).
run() {
  local ws="$1"; shift
  (cd "$ws" && node "$SANDBOX" "$@") >/dev/null 2>&1
}

expect_blocked() {
  local desc="$1"; shift
  if run "$@"; then
    echo "FAIL (should be blocked): $desc"
    fail=$((fail + 1))
  else
    echo "  ok (blocked):  $desc"
    pass=$((pass + 1))
  fi
}

expect_allowed() {
  local desc="$1"; shift
  if run "$@"; then
    echo "  ok (allowed):  $desc"
    pass=$((pass + 1))
  else
    echo "FAIL (should be allowed): $desc"
    fail=$((fail + 1))
  fi
}

WS="$WORK/workspace"

echo "protected paths:"
expect_blocked "read protected file"        "$WS" cat "$WORK/protected/secret.txt"
expect_blocked "list protected dir"         "$WS" ls "$WORK/protected"
expect_blocked "write into protected dir"   "$WS" touch "$WORK/protected/new.txt"
expect_allowed "stat protected file (metadata stays readable)" "$WS" stat "$WORK/protected/secret.txt"

echo "write containment:"
expect_allowed "write in workspace (launch cwd)" "$WS" touch ./in-workspace.txt
expect_blocked "write outside workspace"         "$WS" touch "$WORK/outside.txt"
expect_blocked "write visible file in \$HOME"    "$WS" touch "$HOME/ig-test-outside-file"
expect_allowed "write in allowWrite dir"         "$WS" touch "$WORK/allowed/state.txt"
expect_allowed "write in \$TMPDIR"               "$WS" sh -c 'touch "$TMPDIR/ig-test.txt" && rm "$TMPDIR/ig-test.txt"'
expect_allowed "write to /dev/null"              "$WS" sh -c 'echo hi > /dev/null'

echo "dotfiles:"
expect_allowed "create home-root dotfile"        "$WS" touch "$DOTFILE"
expect_allowed "write through symlinked dotfile (resolved target)" "$WS" touch "$DOTLINK/state.txt"
if [ -d "$HOME/.ssh" ]; then
  expect_blocked "write in ~/.ssh (sensitive)"   "$WS" touch "$HOME/.ssh/ig-test-stray-$$"
fi
if [ -f "$HOME/.zshrc" ]; then
  # ": >>" opens for append without writing bytes — probes the deny harmlessly
  expect_blocked "open ~/.zshrc for append (sensitive)" "$WS" sh -c ": >> '$HOME/.zshrc'"
fi
if [ -d "$HOME/.config/information-guard" ]; then
  expect_blocked "write guard config (sensitive)" "$WS" touch "$HOME/.config/information-guard/ig-test"
fi

echo "untouched surfaces:"
expect_allowed "network (curl example.com)"      "$WS" curl -sS -m 10 https://example.com -o /dev/null

echo "profiles (keyed by command basename):"
cat > "$INFORMATION_GUARD_CONFIG" <<EOF
{
  "protectedPaths": ["$WORK/protected"],
  "writeContainment": { "enabled": true, "allowWrite": [] },
  "profiles": {
    "cat": { "protectedPaths": [] },
    "touch": { "protectedPaths": [] }
  }
}
EOF
expect_allowed "profiled command reads protected (profile drops read-denies)" "$WS" cat "$WORK/protected/secret.txt"
expect_blocked "profiled command still write-contained (inherits containment)" "$WS" touch "$WORK/outside3.txt"
expect_blocked "unprofiled command still read-blocked (default profile)"       "$WS" sh -c "cat '$WORK/protected/secret.txt'"

echo "containment off (protected paths only):"
cat > "$INFORMATION_GUARD_CONFIG" <<EOF
{
  "protectedPaths": ["$WORK/protected"],
  "writeContainment": { "enabled": false }
}
EOF
expect_allowed "write outside workspace"    "$WS" sh -c "touch '$WORK/outside2.txt' && rm '$WORK/outside2.txt'"
expect_blocked "read protected file"        "$WS" cat "$WORK/protected/secret.txt"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
