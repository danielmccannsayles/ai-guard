> [!CAUTION]
> Not extensively reviewed or tested. The sandbox uses macOS `sandbox-exec` with `(allow default)` (fail-open). It blocks file access to protected paths but does not restrict network, process execution, or other operations.

# information-guard

Protects your system from AI agents, with two layers:

1. **Git guard** — prevents agents from committing/pushing to protected repos. Uses an env var (`AGENT_FLAG`) set by the agent's extension, checked by global git hooks.

2. **File sandbox** — prevents agents from reading protected paths with Kernel-level `open()` denial, using macOS Seatbelt sandboxing.

## How it works

### Git guard

Agents (pi, Claude Code, etc.) set an `AGENT_FLAG` env var on every bash command they run. The git hooks check for this env var and block commit/push in repos listed in `~/.config/information-guard/repos.txt`.

- **pi**: `git-guard.ts` extension prepends `export AGENT_FLAG=pi;` to every bash command
- **Claude Code**: `SessionStart` hook writes `export AGENT_FLAG=claude` to `$CLAUDE_ENV_FILE`
- **Git hooks**: `~/.config/git/hooks/pre-commit` and `pre-push` (identical scripts, symlinked from `git-guard/hook.sh`)

To add a new agent: set `AGENT_FLAG=<name>` in the agent's environment before it runs bash commands.

### File sandbox

The sandbox wrapper (`sandbox/sandbox.mjs`) generates a Seatbelt profile that denies reads/writes to protected paths, then runs the command via `sandbox-exec -p`:

```
information-guard-sandbox claude
└─ sandbox-exec -p '(allow default) (deny file-read* ...)'
   └─ claude
      ├─ Bash tool  → sandboxed (EPERM on protected paths)
      ├─ Read tool  → sandboxed (EPERM on protected paths)
      ├─ Edit tool  → sandboxed (EPERM on protected paths)
      └─ MCP servers → sandboxed
```

Everything except file access to protected paths is allowed: network, keychain, TTY, mach IPC. The profile is `(allow default)` with deny rules for each protected path.

## Install

_Requires macOS (uses `sandbox-exec` / Seatbelt)._

```bash
./install.sh
```

```bash
# ~/.zshrc
alias claude='information-guard-sandbox claude'
alias pi='information-guard-sandbox pi'
```

## Config

Set protected repos (no git push & commit) and paths (no read/write)

### `~/.config/information-guard/repos.txt`

```
~/agents
~/Desktop/coding/some-protected-repo
```

### `~/.config/information-guard/sandbox.json`

```json
{
  "protectedPaths": ["~/secrets", "~/agent-config/memory"]
}
```

### Why not Claude Code's built-in `/sandbox`?

Claude's `/sandbox` only wraps the **Bash tool**. The Read/Edit/Write tools run in the Claude process itself, unsandboxed.

### Why not permissions.deny?

Claude Code's `permissions.deny` (e.g. `Read(**/secrets/**)`) is pattern matching on tool invocations. It can be bypassed: `python3 -c "open('secret').read()"` via the Bash tool, or an MCP server reading files directly.

### Codex / other sandboxed tools

Apple sandboxes do not nest. If you're using e.g. Codex, which has it's own apple sandbox, you should just add your configuration directly to Codex's sandbox.

## License

MIT
