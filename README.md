# ai-guard

Protects your system from AI agents. Two layers:

1. **Git guard** — prevents agents from committing/pushing to protected repos. Uses an env var (`AGENT_FLAG_*`) set by the agent's extension, checked by global git hooks (`pre-commit`, `pre-push`). Cooperative protocol: agents tag themselves, hooks check voluntarily.

2. **File sandbox** — prevents agents from reading protected paths (memory, encrypted fragments, extensions). Wraps the entire agent process in [`@anthropic-ai/sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime), which uses macOS Seatbelt (`sandbox-exec`) for kernel-level `open()` denial. No pattern matching — `cat`, `python3`, `node`, everything gets `EPERM`.

## How it works

### Git guard

Agents (pi, Claude Code) set an `AGENT_FLAG_<hash>` env var on every bash command they run. The git hooks check for this env var and block commit/push in repos listed in `~/.config/ai-guard/repos.txt`. Daniel (interactive terminal) never has the env var set, so he's never blocked.

- **pi**: `git-guard.ts` extension prepends `export AGENT_FLAG_5dcb696f6215=pi;` to every bash command
- **Claude Code**: `SessionStart` hook writes `export AGENT_FLAG_5dcb696f6215=claude` to `$CLAUDE_ENV_FILE`
- **Git hooks**: `~/.config/git/hooks/pre-commit` and `pre-push` (identical scripts, symlinked from `git-guard/hook.sh`)

### File sandbox

The sandbox wrapper (`sandbox/sandbox.mjs`) initializes `@anthropic-ai/sandbox-runtime` with deny-read/deny-write paths from `~/.config/ai-guard/sandbox.json`, then spawns the wrapped command inside a Seatbelt sandbox.

```
ai-guard-sandbox claude
└─ sandbox-exec (kernel-level)
   ├─ deny file-read*  (protected paths)
   ├─ deny file-write* (protected paths)
   └─ allow network*   (unrestricted)
   └─ claude
      ├─ Bash tool  → sandboxed
      ├─ Read tool  → sandboxed (open() returns EPERM)
      ├─ Edit tool  → sandboxed
      └─ MCP servers → sandboxed
```

Network is unrestricted — the sandbox only blocks file access to protected paths. This is simpler than configuring domain allowlists and covers the threat model (agent reading files it shouldn't, not agent exfiltrating via network).

## Install

```bash
git clone https://github.com/danielmccannsayles/ai-guard.git
cd ai-guard
./install.sh
```

Requires:
- macOS (uses `sandbox-exec` / Seatbelt)
- Node.js ≥ 20.11
- `@anthropic-ai/sandbox-runtime` (installed by `install.sh` if missing)

Then add aliases to your shell config:

```bash
# ~/.zshrc
alias claude='ai-guard-sandbox claude'
alias pi='ai-guard-sandbox pi'
```

## Config

### `~/.config/ai-guard/repos.txt`

Protected repos — agents can't commit or push here. One path per line, `~` expands to `$HOME`.

```
~/agents
~/Desktop/coding/some-protected-repo
```

### `~/.config/ai-guard/sandbox.json`

Protected paths — agents can't read or write these. Paths are added to both `denyRead` and `denyWrite`.

```json
{
  "protectedPaths": [
    "~/agents/pi/agent/memory",
    "~/agents/fragments/encrypted",
    "~/agents/pi/agent/extensions"
  ]
}
```

## Why not just use Claude Code's built-in `/sandbox`?

Claude's `/sandbox` only wraps the **Bash tool**. The Read/Edit/Write tools run in the Claude process itself, unsandboxed. `ai-guard-sandbox` wraps the entire process — every tool, every MCP server, every hook. One mechanism, not two. And it works with any agent (pi, Codex), not just Claude.

Both use the same `@anthropic-ai/sandbox-runtime` library under the hood.

## Why not just use permissions.deny?

Claude Code's `permissions.deny` (e.g. `Read(**/secrets/**)`) is pattern matching on tool invocations. It can be bypassed: `python3 -c "open('secret').read()"` via the Bash tool, or an MCP server reading files directly. The sandbox is kernel-level — the `open()` syscall itself returns `EPERM`, regardless of what process or technique tried to read the file.

## License

MIT
