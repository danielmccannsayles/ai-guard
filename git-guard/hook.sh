#!/bin/bash
# ai-guard — git hook (pre-commit and pre-push)
#
# Blocks git commit/push when an AI agent is running the command.
# Detection: checks for AGENT_FLAG_* env vars (set by agent extensions
# like pi's git-guard.ts, or Claude's SessionStart hook).
# Scope: only blocks in repos listed in ~/.config/ai-guard/repos.txt.
#
# This is a cooperative protocol. Agents set the env var voluntarily;
# this hook checks it voluntarily. Daniel (interactive terminal) never
# has AGENT_FLAG_* set, so he's never blocked.

# Check if any AGENT_FLAG_* env var is set
agent_flag=$(env | grep '^AGENT_FLAG_' | head -1)
if [ -z "$agent_flag" ]; then
  exit 0  # Not an agent — allow
fi

agent_name=$(echo "$agent_flag" | cut -d= -f2)

repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$repo_root" ]; then
  exit 0  # Not in a git repo — allow
fi

repos_file="$HOME/.config/ai-guard/repos.txt"
if [ ! -f "$repos_file" ]; then
  protected_repos="$HOME/agents"
else
  protected_repos=$(grep -v '^#' "$repos_file" | grep -v '^$' | sed "s|^~/|$HOME/|")
fi

echo "$protected_repos" | while IFS= read -r protected; do
  protected=$(echo "$protected" | xargs)
  if [ -z "$protected" ]; then continue; fi
  if [ "$repo_root" = "$protected" ]; then
    echo "" >&2
    echo "Blocked: AI agent ($agent_name) attempted git operation in protected repo." >&2
    echo "  Repo: $repo_root" >&2
    echo "  Protected repos list: $repos_file" >&2
    echo "" >&2
    exit 1
  fi
done

status=$?
if [ $status -ne 0 ]; then
  exit $status
fi

exit 0
