#!/bin/bash
# information-guard install — Sets up git hooks + sandbox wrapper
#
# Installs:
#   - Git hooks (pre-commit, pre-push) → ~/.config/git/hooks/ (via core.hooksPath)
#   - Sandbox wrapper → ~/.local/bin/information-guard-sandbox
#   - Default config → ~/.config/information-guard/ (repos.txt, sandbox.json)
#
# Run from the repo root: ./install.sh

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
INFORMATION_GUARD_DIR="$HOME/.config/information-guard"
GIT_HOOKS_DIR="$HOME/.config/git/hooks"
LOCAL_BIN="$HOME/.local/bin"

echo "information-guard install"
echo "================"
echo ""

mkdir -p "$INFORMATION_GUARD_DIR" "$GIT_HOOKS_DIR" "$LOCAL_BIN"

# Git hooks (copied into the write-protected config dir, not symlinked to the repo —
# a symlink target would be writable by sandboxed agents working in ~/Desktop/coding)
# rm -f first: the previous install may have left symlinks, and cp errors with
# "are identical (not copied)" when dest is a symlink to the source.
rm -f "$GIT_HOOKS_DIR/pre-commit" "$GIT_HOOKS_DIR/pre-push"
cp "$REPO_DIR/git-guard/hook.sh" "$GIT_HOOKS_DIR/pre-commit"
cp "$REPO_DIR/git-guard/hook.sh" "$GIT_HOOKS_DIR/pre-push"
chmod +x "$GIT_HOOKS_DIR/pre-commit" "$GIT_HOOKS_DIR/pre-push"
git config --global core.hooksPath "$GIT_HOOKS_DIR"
echo "✓ git hooks → $GIT_HOOKS_DIR/ (copied, not symlinked)"

# Default config (don't overwrite existing)
for f in repos.txt sandbox.json; do
  src="$REPO_DIR/git-guard/repos.default.txt"
  [ "$f" = "sandbox.json" ] && src="$REPO_DIR/sandbox/default-config.json"
  if [ ! -f "$INFORMATION_GUARD_DIR/$f" ]; then
    cp "$src" "$INFORMATION_GUARD_DIR/$f"
    echo "✓ created $INFORMATION_GUARD_DIR/$f"
  else
    echo "✓ $INFORMATION_GUARD_DIR/$f already exists (kept)"
  fi
done

# Sandbox wrapper (copied into the write-protected config dir, not symlinked to the
# repo — the repo source is writable by sandboxed agents; the config dir is SENSITIVE)
rm -f "$INFORMATION_GUARD_DIR/sandbox.mjs"
cp "$REPO_DIR/sandbox/sandbox.mjs" "$INFORMATION_GUARD_DIR/sandbox.mjs"
chmod +x "$INFORMATION_GUARD_DIR/sandbox.mjs"
ln -sf "$INFORMATION_GUARD_DIR/sandbox.mjs" "$LOCAL_BIN/information-guard-sandbox"
echo "✓ information-guard-sandbox → $LOCAL_BIN/ (→ $INFORMATION_GUARD_DIR/sandbox.mjs, copied)"

echo ""
echo "Done. Add aliases to your shell config:"
echo ""
echo "  alias claude='information-guard-sandbox claude'"
echo "  alias pi='information-guard-sandbox pi'"
echo ""
echo "Config:"
echo "  Protected repos:  $INFORMATION_GUARD_DIR/repos.txt"
echo "  Sandbox paths:    $INFORMATION_GUARD_DIR/sandbox.json"
