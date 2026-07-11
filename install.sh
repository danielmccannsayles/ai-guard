#!/bin/bash
# ai-guard install — sets up git hooks + sandbox wrapper
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

# 1. Install pinned sandbox-runtime from local lockfile (SHA-512 verified)
echo "Installing @anthropic-ai/sandbox-runtime from pinned lockfile..."
npm ci --omit=dev 2>&1 | tail -1
echo "✓ sandbox-runtime installed (pinned)"

# 2. Create config directory
mkdir -p "$AI_GUARD_DIR"
mkdir -p "$GIT_HOOKS_DIR"
mkdir -p "$LOCAL_BIN"

# 3. Install git hooks (symlink — updates propagate from the repo)
chmod +x "$REPO_DIR/git-guard/hook.sh"
ln -sf "$REPO_DIR/git-guard/hook.sh" "$GIT_HOOKS_DIR/pre-commit"
ln -sf "$REPO_DIR/git-guard/hook.sh" "$GIT_HOOKS_DIR/pre-push"
echo "✓ git hooks → $GIT_HOOKS_DIR/"

# 4. Set global git hooks path
git config --global core.hooksPath "$GIT_HOOKS_DIR"
echo "✓ git core.hooksPath = $GIT_HOOKS_DIR"

# 5. Install default config (don't overwrite existing)
if [ ! -f "$AI_GUARD_DIR/repos.txt" ]; then
  cp "$REPO_DIR/git-guard/repos.default.txt" "$AI_GUARD_DIR/repos.txt"
  echo "✓ created $AI_GUARD_DIR/repos.txt"
else
  echo "✓ $AI_GUARD_DIR/repos.txt already exists (kept)"
fi

if [ ! -f "$AI_GUARD_DIR/sandbox.json" ]; then
  cp "$REPO_DIR/sandbox/default-config.json" "$AI_GUARD_DIR/sandbox.json"
  echo "✓ created $AI_GUARD_DIR/sandbox.json"
else
  echo "✓ $AI_GUARD_DIR/sandbox.json already exists (kept)"
fi

# 6. Install sandbox wrapper
chmod +x "$REPO_DIR/sandbox/sandbox.mjs"
ln -sf "$REPO_DIR/sandbox/sandbox.mjs" "$LOCAL_BIN/ai-guard-sandbox"
echo "✓ ai-guard-sandbox → $LOCAL_BIN/"

echo ""
echo "Done. To sandbox an agent, run it through ai-guard-sandbox:"
echo ""
echo "  ai-guard-sandbox claude"
echo "  ai-guard-sandbox pi"
echo ""
echo "Or add aliases to your shell config:"
echo ""
echo "  alias claude='ai-guard-sandbox claude'"
echo "  alias pi='ai-guard-sandbox pi'"
echo ""
echo "Config:"
echo "  Protected repos:  $AI_GUARD_DIR/repos.txt"
echo "  Sandbox paths:    $AI_GUARD_DIR/sandbox.json"
