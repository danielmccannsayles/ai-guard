#!/usr/bin/env node
// ai-guard sandbox — wraps a command in @anthropic-ai/sandbox-runtime
//
// Blocks file reads/writes to protected paths at the kernel level (macOS Seatbelt).
// Network is unrestricted. Works with any command (claude, pi, etc.).
//
// Usage: ai-guard-sandbox <command> [args...]
// Config: ~/.config/ai-guard/sandbox.json ({ "protectedPaths": ["~/path/..."] })

import { execSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { spawn } from 'node:child_process';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

const CONFIG_PATH = join(homedir(), '.config', 'ai-guard', 'sandbox.json');

// Resolve @anthropic-ai/sandbox-runtime from the local node_modules (pinned)
function resolveSrt() {
  const candidates = [
    // Local install (pinned lockfile, SHA-512 verified)
    join(__dirname, 'node_modules', '@anthropic-ai', 'sandbox-runtime', 'dist', 'index.js'),
    // Global install (fallback)
    join(execSync('npm root -g', { encoding: 'utf8' }).trim(), '@anthropic-ai', 'sandbox-runtime', 'dist', 'index.js'),
  ];
  for (const p of candidates) {
    if (existsSync(p)) return p;
  }
  console.error('ai-guard: @anthropic-ai/sandbox-runtime not found.');
  console.error('  Run the install script: ./install.sh');
  process.exit(1);
}

// Expand ~ in paths
function expandPath(p) {
  if (p.startsWith('~/')) return join(homedir(), p.slice(2));
  if (p === '~') return homedir();
  return p;
}

// Load protected paths from config
function loadProtectedPaths() {
  if (!existsSync(CONFIG_PATH)) {
    console.error(`ai-guard: No config found at ${CONFIG_PATH}`);
    console.error('  Run the install script or create it with:');
    console.error(`    mkdir -p ~/.config/ai-guard`);
    console.error(`    echo '{"protectedPaths":["~/agents/pi/agent/memory"]}' > ${CONFIG_PATH}`);
    process.exit(1);
  }

  const config = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
  const paths = (config.protectedPaths || []).map(expandPath);

  if (paths.length === 0) {
    console.error('ai-guard: No protectedPaths in config. Nothing to sandbox.');
    process.exit(1);
  }

  return paths;
}

async function main() {
  const command = process.argv.slice(2);
  if (command.length === 0) {
    console.error('Usage: ai-guard-sandbox <command> [args...]');
    process.exit(1);
  }

  const protectedPaths = loadProtectedPaths();
  const srtPath = resolveSrt();
  const { SandboxManager } = await import(srtPath);

  // network: {} → no allowedDomains key → no network restriction (allow all)
  // This is the key insight: omitting allowedDomains entirely skips the proxy,
  // while empty arrays would block all network.
  const config = {
    network: {},
    filesystem: {
      denyRead: protectedPaths,
      denyWrite: protectedPaths,
      allowRead: [],
      allowWrite: [],
    },
  };

  await SandboxManager.initialize(config);

  const commandStr = command.map(arg => {
    if (/^[\w./=-]+$/.test(arg)) return arg;
    return `'${arg.replace(/'/g, "'\\''")}'`;
  }).join(' ');

  const wrapped = await SandboxManager.wrapWithSandbox(commandStr);

  const child = spawn(wrapped, {
    shell: true,
    stdio: 'inherit',
  });

  child.on('exit', (code, signal) => {
    if (signal) {
      if (signal === 'SIGINT' || signal === 'SIGTERM') process.exit(0);
      console.error(`ai-guard: process killed by signal: ${signal}`);
      process.exit(1);
    }
    process.exit(code ?? 0);
  });

  child.on('error', (err) => {
    console.error(`ai-guard: ${err.message}`);
    process.exit(1);
  });
}

main().catch(err => {
  console.error(`ai-guard: ${err.message}`);
  process.exit(1);
});
