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

# Git hooks
chmod +x "$REPO_DIR/git-guard/hook.sh"
ln -sf "$REPO_DIR/git-guard/hook.sh" "$GIT_HOOKS_DIR/pre-commit"
ln -sf "$REPO_DIR/git-guard/hook.sh" "$GIT_HOOKS_DIR/pre-push"
git config --global core.hooksPath "$GIT_HOOKS_DIR"
echo "✓ git hooks → $GIT_HOOKS_DIR/"

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

# Sandbox wrapper
chmod +x "$REPO_DIR/sandbox/sandbox.mjs"
ln -sf "$REPO_DIR/sandbox/sandbox.mjs" "$LOCAL_BIN/information-guard-sandbox"
echo "✓ information-guard-sandbox → $LOCAL_BIN/"

echo ""
echo "Done. Add aliases to your shell config:"
echo ""
echo "  alias claude='information-guard-sandbox claude'"
echo "  alias pi='information-guard-sandbox pi'"
echo ""
echo "Config:"
echo "  Protected repos:  $INFORMATION_GUARD_DIR/repos.txt"
echo "  Sandbox paths:    $INFORMATION_GUARD_DIR/sandbox.json"
