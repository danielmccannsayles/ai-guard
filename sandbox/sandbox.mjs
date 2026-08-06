#!/usr/bin/env node
// information-guard sandbox — wraps a command in a macOS Seatbelt sandbox.
//
// Two layers:
//   1. Protected paths — reads/writes to protected paths are denied at the
//      kernel level (EPERM on open()). Always on.
//   2. Write containment (optional) — writes are denied everywhere except:
//        - the workspace (the directory the agent was launched from)
//        - temp dirs and /dev
//        - home-root dotfiles (~/.claude, ~/.codex, ~/.npm, ...) — agent and
//          tool state, agent-agnostic, no per-agent allowlist to maintain —
//          minus a short deny list of universally-sensitive dotfiles
//        - configured allowWrite paths (escape hatch for weird tools)
//      Mirrors codex's workspace-write sandbox: the agent can read the
//      computer but only mutate the project it was launched in.
//
// Everything else is allowed: network, keychain, TTY, mach IPC, sysctls.
// Uses a raw SBPL profile built on (allow default). Later rules take
// precedence over earlier ones, so the order is: allow default → containment
// deny + allows → sensitive-dotfile denies → protected-path denies (later
// denies win over the allows, e.g. a protected dir inside an allowed
// workspace stays blocked).
//
// Usage: information-guard-sandbox <command> [args...]
//        information-guard-sandbox --print-profile        (show the generated SBPL and exit)
//        information-guard-sandbox --print-codex-config   (emit a codex permissions profile
//                                                          from the same config, to paste into
//                                                          ~/.codex/config.toml — codex has its
//                                                          own Seatbelt sandbox; don't wrap it)
// Config: ~/.config/information-guard/sandbox.json (override with $INFORMATION_GUARD_CONFIG)
//   {
//     "protectedPaths": ["~/path/..."],
//     "writeContainment": { "enabled": true, "allowWrite": [] }
//   }
//
// Known hole: the guard does not defend its own source. An agent working in
// the information-guard repo can edit sandbox.mjs (it's the workspace), and the edit
// takes effect on the next launch. The config and git hooks are write-denied,
// but the wrapper source is only as safe as the repos you point agents at.

import { existsSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { spawn } from "node:child_process";
import { join, dirname } from "node:path";

const CONFIG_PATH =
  process.env.INFORMATION_GUARD_CONFIG ||
  join(homedir(), ".config", "information-guard", "sandbox.json");

// Dotfiles agents may never write, even though dotfiles are writable in
// general: credentials, shell startup (persistence), and the guard's own
// config and git hooks. Stable across agents and years, unlike per-agent
// state-dir allowlists.
const SENSITIVE_DOTFILES = [
  "~/.ssh",
  "~/.gitconfig", // core.hooksPath — git-guard integrity
  "~/.config/git", // the git-guard hooks themselves
  "~/.config/information-guard", // this guard's config
  "~/.zshrc",
  "~/.zprofile",
  "~/.zshenv",
  "~/.zlogin",
  "~/.bashrc",
  "~/.bash_profile",
  "~/.profile",
];

// Expand ~ in paths
function expandPath(p) {
  if (p.startsWith("~/")) return join(homedir(), p.slice(2));
  if (p === "~") return homedir();
  return p;
}

// Contract an absolute path back to ~/ form (for emitting portable config)
function tildePath(p) {
  const home = homedir();
  if (p === home) return "~";
  if (p.startsWith(home + "/")) return "~" + p.slice(home.length);
  return p;
}

// Seatbelt matches on resolved paths (e.g. /tmp → /private/tmp), so resolve
// symlinks where possible. Nonexistent paths are kept as-is.
function realPath(p) {
  try {
    return realpathSync(p);
  } catch {
    return p;
  }
}

// Resolved targets of symlinked home-root dotfiles. Seatbelt matches resolved
// paths, so the dotfile regex alone misses state dirs that are symlinks
// (~/.claude → ~/agents/claude). Enumerate them at launch and allow the
// targets explicitly.
function dotfileSymlinkTargets() {
  const home = homedir();
  const targets = [];
  let entries = [];
  try {
    entries = readdirSync(home);
  } catch {
    return targets;
  }
  for (const name of entries) {
    if (!name.startsWith(".")) continue;
    const p = join(home, name);
    const real = realPath(p);
    if (real !== p) targets.push(real);
  }
  return targets;
}

// Load config from ~/.config/information-guard/sandbox.json
function loadConfig() {
  if (!existsSync(CONFIG_PATH)) {
    console.error(`information-guard: No config found at ${CONFIG_PATH}`);
    console.error("  Run the install script or create it with:");
    console.error(`    mkdir -p ~/.config/information-guard`);
    console.error(
      `    echo '{"protectedPaths":["~/secrets"]}' > ${CONFIG_PATH}`,
    );
    process.exit(1);
  }

  const raw = JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
  const protectedPaths = (raw.protectedPaths || []).map(expandPath);
  const containment = {
    enabled: raw.writeContainment?.enabled === true,
    allowWrite: (raw.writeContainment?.allowWrite || []).map(expandPath),
  };

  if (protectedPaths.length === 0 && !containment.enabled) {
    console.error(
      "information-guard: No protectedPaths and no writeContainment in config. Nothing to sandbox.",
    );
    process.exit(1);
  }

  return { protectedPaths, containment };
}

// Build the SBPL profile. (allow default) permits everything; containment
// (if enabled) denies writes and re-allows specific roots; sensitive-dotfile
// and protected-path denies come last so they take precedence over the
// containment allows.
function buildProfile(protectedPaths, containment) {
  const lines = ["(version 1)", "(allow default)"];

  if (containment.enabled) {
    lines.push(`(deny file-write* (subpath "/"))`);

    // Workspace, temp, /dev, symlinked-dotfile targets, config extras
    const subpathAllows = new Set([
      realPath(process.cwd()),
      "/private/tmp",
      "/dev",
    ]);
    if (process.env.TMPDIR) {
      // $TMPDIR plus its parent (the per-user /private/var/folders dir,
      // which also holds the C/ cache sibling)
      const tmp = realPath(process.env.TMPDIR);
      subpathAllows.add(tmp);
      subpathAllows.add(dirname(tmp));
    }
    for (const t of dotfileSymlinkTargets()) subpathAllows.add(t);
    for (const p of containment.allowWrite) subpathAllows.add(realPath(p));
    for (const p of subpathAllows) {
      lines.push(`(allow file-write* (subpath "${p}"))`);
    }

    // Home-root dotfiles: tool and agent state (~/.claude, ~/.codex, ~/.npm,
    // ~/.local, ...). Visible files in home stay write-denied — that's the
    // data containment protects.
    lines.push(`(allow file-write* (regex #"^${homedir()}/\\.[^/]*(/|$)"))`);

    // Sensitive dotfiles win over the regex allow (later rules take precedence)
    for (const s of SENSITIVE_DOTFILES) {
      lines.push(`(deny file-write* (subpath "${realPath(expandPath(s))}"))`);
    }
  }

  // Deny file-read-data (content + directory listing) but allow file-read-metadata
  // (stat, lstat). This lets git status stat files without reading their contents.
  // git may warn about directories it can't list, but exit code and output are correct.
  // file-write* is fully denied (no writes to protected paths).
  for (const p of protectedPaths) {
    lines.push(
      `(deny file-read-data (subpath "${p}"))`,
      `(deny file-write* (subpath "${p}"))`,
    );
  }

  return lines.join("\n");
}

function main() {
  const command = process.argv.slice(2);
  if (command.length === 0) {
    console.error("Usage: information-guard-sandbox <command> [args...]");
    process.exit(1);
  }

  const { protectedPaths, containment } = loadConfig();
  const profile = buildProfile(protectedPaths, containment);

  if (command[0] === "--print-profile") {
    console.log(profile);
    process.exit(0);
  }

  // Codex has its own Seatbelt sandbox (Apple sandboxes don't nest), so
  // instead of wrapping it, emit an equivalent permissions profile from the
  // same config. ":workspace" already contains writes and disables network;
  // only the protected-path read-denies need syncing.
  if (command[0] === "--print-codex-config") {
    console.log(
      [
        `# Generated by information-guard from ${CONFIG_PATH}`,
        `# Paste into ~/.codex/config.toml. Re-run after changing protectedPaths.`,
        ``,
        `default_permissions = "information-guard"`,
        ``,
        `[permissions.information-guard]`,
        `description = "Workspace-write with deny-read on information-guard protected paths."`,
        `extends = ":workspace"`,
        ``,
        `[permissions.information-guard.filesystem]`,
        ...protectedPaths.map((p) => `"${tildePath(p)}" = "deny"`),
      ].join("\n"),
    );
    process.exit(0);
  }

  // sandbox-exec -p '<profile>' -- <command>
  // The profile is passed as a single argument. sandbox-exec runs the command
  // inside the sandbox. stdio is inherited so TUI apps work normally.
  const child = spawn("/usr/bin/sandbox-exec", ["-p", profile, ...command], {
    stdio: "inherit",
  });

  child.on("exit", (code, signal) => {
    if (signal) {
      if (signal === "SIGINT" || signal === "SIGTERM") process.exit(0);
      console.error(`information-guard: process killed by signal: ${signal}`);
      process.exit(1);
    }
    process.exit(code ?? 0);
  });

  child.on("error", (err) => {
    console.error(`information-guard: ${err.message}`);
    process.exit(1);
  });
}

main();
