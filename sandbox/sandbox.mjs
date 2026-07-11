#!/usr/bin/env node
// ai-guard sandbox — wraps a command in a macOS Seatbelt sandbox.
//
// Blocks file reads/writes to protected paths at the kernel level (EPERM on open()).
// Everything else is allowed: network, keychain, TTY, mach IPC, sysctls.
// Uses a raw SBPL profile with (allow default) + deny specific paths, instead of
// the sandbox-runtime's (deny default) + allow specific paths. This is simpler and
// doesn't break keychain, TCC, or other system services that check for sandboxing.
//
// Usage: ai-guard-sandbox <command> [args...]
// Config: ~/.config/ai-guard/sandbox.json ({ "protectedPaths": ["~/path/..."] })

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { spawn } from "node:child_process";
import { join } from "node:path";

const CONFIG_PATH = join(homedir(), ".config", "ai-guard", "sandbox.json");

// Expand ~ in paths
function expandPath(p) {
  if (p.startsWith("~/")) return join(homedir(), p.slice(2));
  if (p === "~") return homedir();
  return p;
}

// Load config from ~/.config/ai-guard/sandbox.json
function loadConfig() {
  if (!existsSync(CONFIG_PATH)) {
    console.error(`ai-guard: No config found at ${CONFIG_PATH}`);
    console.error("  Run the install script or create it with:");
    console.error(`    mkdir -p ~/.config/ai-guard`);
    console.error(
      `    echo '{"protectedPaths":["~/secrets"]}' > ${CONFIG_PATH}`,
    );
    process.exit(1);
  }

  const raw = JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
  const paths = (raw.protectedPaths || []).map(expandPath);

  if (paths.length === 0) {
    console.error("ai-guard: No protectedPaths in config. Nothing to sandbox.");
    process.exit(1);
  }

  return paths;
}

// Build an SBPL profile that denies reads/writes to protected paths.
// (allow default) permits everything; the deny rules carve out protected paths.
// macOS resolves symlinks before matching, so /tmp → /private/tmp is handled
// automatically — deny the real path.
function buildProfile(protectedPaths) {
  const lines = [
    "(version 1)",
    "(allow default)",
  ];

  for (const p of protectedPaths) {
    lines.push(
      `(deny file-read* (subpath "${p}"))`,
      `(deny file-write* (subpath "${p}"))`,
    );
  }

  return lines.join("\n");
}

function main() {
  const command = process.argv.slice(2);
  if (command.length === 0) {
    console.error("Usage: ai-guard-sandbox <command> [args...]");
    process.exit(1);
  }

  const protectedPaths = loadConfig();
  const profile = buildProfile(protectedPaths);

  // sandbox-exec -p '<profile>' -- <command>
  // The profile is passed as a single argument. sandbox-exec runs the command
  // inside the sandbox. stdio is inherited so TUI apps work normally.
  const child = spawn("/usr/bin/sandbox-exec", ["-p", profile, ...command], {
    stdio: "inherit",
  });

  child.on("exit", (code, signal) => {
    if (signal) {
      if (signal === "SIGINT" || signal === "SIGTERM") process.exit(0);
      console.error(`ai-guard: process killed by signal: ${signal}`);
      process.exit(1);
    }
    process.exit(code ?? 0);
  });

  child.on("error", (err) => {
    console.error(`ai-guard: ${err.message}`);
    process.exit(1);
  });
}

main();
