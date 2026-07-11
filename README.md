# ai-guard

Protects your system from AI agents. Two layers:

1. **Git guard** — prevents agents from committing/pushing to protected repos. Uses an env var (`AGENT_FLAG_*`) set by the agent's extension, checked by global git hooks (`pre-commit`, `pre-push`). Cooperative protocol: agents tag themselves, hooks check voluntarily.

2. **File sandbox** — prevents agents from reading protected paths (secrets, memory, configs). Wraps the entire agent process in [`@anthropic-ai/sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime), which uses macOS Seatbelt (`sandbox-exec`) for kernel-level `open()` denial. No pattern matching — `cat`, `python3`, `node`, everything gets `EPERM`.

## How it works

### Git guard

Agents (pi, Claude Code, etc.) set an `AGENT_FLAG_<hash>` env var on every bash command they run. The git hooks check for this env var and block commit/push in repos listed in `~/.config/ai-guard/repos.txt`. A human at the terminal never has the env var set, so they're never blocked.

- **pi**: `git-guard.ts` extension prepends `export AGENT_FLAG_5dcb696f6215=pi;` to every bash command
- **Claude Code**: `SessionStart` hook writes `export AGENT_FLAG_5dcb696f6215=claude` to `$CLAUDE_ENV_FILE`
- **Git hooks**: `~/.config/git/hooks/pre-commit` and `pre-push` (identical scripts, symlinked from `git-guard/hook.sh`)

To add a new agent: set `AGENT_FLAG_5dcb696f6215=<name>` in the agent's environment before it runs bash commands. That's it — the hooks do the rest.

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

Network is unrestricted — the sandbox only blocks file access to protected paths. This covers the threat model (agent reading files it shouldn't) without the complexity of domain allowlists.

## Install

```bash
git clone https://github.com/danielmccannsayles/ai-guard.git
cd ai-guard
./install.sh
```

Requires:
- macOS (uses `sandbox-exec` / Seatbelt)
- Node.js ≥ 20.11

The install script:
- Runs `npm ci` to install `@anthropic-ai/sandbox-runtime` from the pinned lockfile (`package-lock.json` contains SHA-512 integrity hashes, verified on install)
- Symlinks git hooks to `~/.config/git/hooks/` and sets `core.hooksPath`
- Symlinks the sandbox wrapper to `~/.local/bin/ai-guard-sandbox`
- Copies default config to `~/.config/ai-guard/` (existing config is preserved)

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
    "~/secrets",
    "~/agent-config/memory"
  ]
}
```

## Why not just use Claude Code's built-in `/sandbox`?

Claude's `/sandbox` only wraps the **Bash tool**. The Read/Edit/Write tools run in the Claude process itself, unsandboxed. `ai-guard-sandbox` wraps the entire process — every tool, every MCP server, every hook. One mechanism, not two. And it works with any agent (pi, Codex), not just Claude.

Both use the same `@anthropic-ai/sandbox-runtime` library under the hood.

## Why not just use permissions.deny?

Claude Code's `permissions.deny` (e.g. `Read(**/secrets/**)`) is pattern matching on tool invocations. It can be bypassed: `python3 -c "open('secret').read()"` via the Bash tool, or an MCP server reading files directly. The sandbox is kernel-level — the `open()` syscall itself returns `EPERM`, regardless of what process or technique tried to read the file.

## Updating sandbox-runtime

The version is pinned in `package.json`. To update:

```bash
cd ai-guard
npm install @anthropic-ai/sandbox-runtime@latest   # or @0.0.66
git add package.json package-lock.json
git commit -m "Bump sandbox-runtime to 0.0.66"
```

The lockfile pins every transitive dependency with integrity hashes. `npm ci` verifies them on install.

## License

MIT
