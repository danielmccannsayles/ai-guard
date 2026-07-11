> ⚠️ **DRAFT — work in progress.** This is a personal project, not production-ready. The sandbox uses macOS `sandbox-exec` with `(allow default)` (fail-open) — it blocks file access to protected paths but does not restrict network, process execution, or other operations. See [How it works](#how-it-works) for details.

# ai-guard

Protects your system from AI agents. Two layers:

1. **Git guard** — prevents agents from committing/pushing to protected repos. Uses an env var (`AGENT_FLAG_*`) set by the agent's extension, checked by global git hooks. Cooperative protocol: agents tag themselves, hooks check voluntarily.

2. **File sandbox** — prevents agents from reading protected paths (secrets, memory, configs). Wraps the agent process in a macOS Seatbelt sandbox using `sandbox-exec`. Kernel-level `open()` denial — `cat`, `python3`, `node`, everything gets `EPERM`. No pattern matching, no bypass.

## How it works

### Git guard

Agents (pi, Claude Code, etc.) set an `AGENT_FLAG_<hash>` env var on every bash command they run. The git hooks check for this env var and block commit/push in repos listed in `~/.config/ai-guard/repos.txt`. A human at the terminal never has the env var set, so they're never blocked.

- **pi**: `git-guard.ts` extension prepends `export AGENT_FLAG_5dcb696f6215=pi;` to every bash command
- **Claude Code**: `SessionStart` hook writes `export AGENT_FLAG_5dcb696f6215=claude` to `$CLAUDE_ENV_FILE`
- **Git hooks**: `~/.config/git/hooks/pre-commit` and `pre-push` (identical scripts, symlinked from `git-guard/hook.sh`)

To add a new agent: set `AGENT_FLAG_5dcb696f6215=<name>` in the agent's environment before it runs bash commands. That's it — the hooks do the rest.

### File sandbox

The sandbox wrapper (`sandbox/sandbox.mjs`) generates a Seatbelt profile that denies reads/writes to protected paths, then runs the command via `sandbox-exec -p`:

```
ai-guard-sandbox claude
└─ sandbox-exec -p '(allow default) (deny file-read* ...)'
   └─ claude
      ├─ Bash tool  → sandboxed (EPERM on protected paths)
      ├─ Read tool  → sandboxed (EPERM on protected paths)
      ├─ Edit tool  → sandboxed (EPERM on protected paths)
      └─ MCP servers → sandboxed
```

Everything except file access to protected paths is allowed: network, keychain, TTY, mach IPC. The profile is `(allow default)` with deny rules for each protected path — simple and complete.

## Install

```bash
git clone https://github.com/danielmccannsayles/ai-guard.git
cd ai-guard
./install.sh
```

Requires macOS (uses `sandbox-exec` / Seatbelt).

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

Protected paths — agents can't read or write these.

```json
{
  "protectedPaths": ["~/secrets", "~/agent-config/memory"]
}
```

## Why not Claude Code's built-in `/sandbox`?

Claude's `/sandbox` only wraps the **Bash tool**. The Read/Edit/Write tools run in the Claude process itself, unsandboxed. `ai-guard-sandbox` wraps the entire process — every tool, every MCP server, every hook. And it works with any agent (pi, Codex), not just Claude.

## Why not permissions.deny?

Claude Code's `permissions.deny` (e.g. `Read(**/secrets/**)`) is pattern matching on tool invocations. It can be bypassed: `python3 -c "open('secret').read()"` via the Bash tool, or an MCP server reading files directly. The sandbox is kernel-level — the `open()` syscall itself returns `EPERM`.

## License

MIT
