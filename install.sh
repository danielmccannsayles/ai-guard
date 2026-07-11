#!/bin/bash
# ai-guard install — Sets up git hooks + sandbox wrapper
#
# Installs:
#   - Git hooks (pre-commit, pre-push) → ~/.config/git/hooks/ (via core.hooksPath)
#   - Sandbox wrapper → ~/.local/bin/ai-guard-sandbox
#   - Default config → ~/.config/ai-guard/ (repos.txt, sandbox.json)
#
# Run from the repo root: ./install.sh

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_GUARD_DIR="$HOME/.config/ai-guard"
GIT_HOOKS_DIR="$HOME/.config/git/hooks"
LOCAL_BIN="$HOME/.local/bin"

echo "ai-guard install"
echo "================"
echo ""

mkdir -p "$AI_GUARD_DIR" "$GIT_HOOKS_DIR" "$LOCAL_BIN"

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
  if [ ! -f "$AI_GUARD_DIR/$f" ]; then
    cp "$src" "$AI_GUARD_DIR/$f"
    echo "✓ created $AI_GUARD_DIR/$f"
  else
    echo "✓ $AI_GUARD_DIR/$f already exists (kept)"
  fi
done

# Sandbox wrapper
chmod +x "$REPO_DIR/sandbox/sandbox.mjs"
ln -sf "$REPO_DIR/sandbox/sandbox.mjs" "$LOCAL_BIN/ai-guard-sandbox"
echo "✓ ai-guard-sandbox → $LOCAL_BIN/"

echo ""
echo "Done. Add aliases to your shell config:"
echo ""
echo "  alias claude='ai-guard-sandbox claude'"
echo "  alias pi='ai-guard-sandbox pi'"
echo ""
echo "Config:"
echo "  Protected repos:  $AI_GUARD_DIR/repos.txt"
echo "  Sandbox paths:    $AI_GUARD_DIR/sandbox.json"
