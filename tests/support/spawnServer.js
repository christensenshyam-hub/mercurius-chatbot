'use strict';

// Boots server.js as a child process on an OS-assigned port (PORT=0) and
// resolves with its base URL once it prints its ready line. The suites run
// in parallel, and the random port ranges they used to pick overlapped.
//
// The model is always the in-process mock with no key: a developer's
// exported ANTHROPIC_API_KEY (or Discord webhook) must never reach a test
// server, whatever the caller passes. `discordWebhookUrl` may point the
// alerts at a local stub (127.0.0.1 only).

const { spawn } = require('node:child_process');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const READY_RE = /Mercurius ready on (http:\/\/localhost:(\d+))/;

function spawnServer(env = {}, { timeoutMs = 15000, discordWebhookUrl = '' } = {}) {
  if (discordWebhookUrl && !discordWebhookUrl.startsWith('http://127.0.0.1:')) {
    throw new Error('spawnServer: discordWebhookUrl must be a local stub');
  }
  const proc = spawn(process.execPath, ['server.js'], {
    cwd: ROOT,
    env: {
      ...process.env,
      NODE_ENV: 'test',
      DATABASE_URL: '',
      ...env,
      ANTHROPIC_MOCK: '1',
      ANTHROPIC_API_KEY: '',
      DISCORD_WEBHOOK_URL: discordWebhookUrl,
      PORT: '0',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  const ready = new Promise((resolve, reject) => {
    let settled = false;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fn(value);
    };
    const timer = setTimeout(
      () => finish(reject, new Error(`server not ready within ${timeoutMs} ms\n${stderr.slice(-2000)}`)),
      timeoutMs,
    );
    proc.stdout.on('data', (chunk) => {
      if (settled) return;
      stdout += chunk;
      const m = stdout.match(READY_RE);
      if (m) finish(resolve, { base: m[1], port: Number(m[2]) });
    });
    proc.stderr.on('data', (chunk) => { if (stderr.length < 100_000) stderr += chunk; });
    proc.on('error', (err) => finish(reject, err));
    proc.on('exit', (code, signal) => finish(reject, new Error(`server exited before it was ready (code ${code}, signal ${signal})\n${stderr.slice(-2000)}`)));
  });
  return { proc, ready };
}

module.exports = { spawnServer, ROOT };
