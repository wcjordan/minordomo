#!/usr/bin/env node
'use strict';

const fs = require('fs');

const webhookUrl = process.env.DISCORD_WEBHOOK_URL;
if (webhookUrl === undefined) {
  process.stderr.write('WARNING: DISCORD_WEBHOOK_URL env var is not set; skipping Discord notification\n');
  process.exit(0);
}
if (webhookUrl === '') {
  process.stderr.write('WARNING: DISCORD_WEBHOOK_URL is set but empty — ensure the discord-webhook-url Jenkins credential has a valid value\n');
  process.exit(0);
}
const validPrefixes = ['https://discord.com/api/webhooks/', 'https://discordapp.com/api/webhooks/'];
if (!validPrefixes.some(p => webhookUrl.startsWith(p))) {
  const preview = webhookUrl.slice(0, 30);
  process.stderr.write(`WARNING: DISCORD_WEBHOOK_URL does not look like a Discord webhook URL (starts with: "${preview}"); skipping Discord notification\n`);
  process.exit(0);
}

const logPath = process.argv[2];
if (!logPath) {
  process.stderr.write('WARNING: No run-log path provided; skipping Discord notification\n');
  process.exit(0);
}

let content;
try {
  content = fs.readFileSync(logPath, 'utf8');
} catch (e) {
  process.stderr.write(`WARNING: Could not read run-log file ${logPath}: ${e.message}\n`);
  process.exit(0);
}

// Two-pass JSON extraction (mirrors check-run-errors.py)
function extractRunLog(text) {
  // Pass 1: first ```json code block
  const blockMatch = text.match(/```(?:json)?\s*\n([\s\S]*?)```/);
  if (blockMatch) {
    try {
      return JSON.parse(blockMatch[1]);
    } catch (e) { /* fall through */ }
  }
  // Pass 2: last parseable JSON line
  const lines = text.split('\n').reverse();
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      return JSON.parse(trimmed);
    } catch (e) { continue; }
  }
  return null;
}

const runLog = extractRunLog(content);
if (!runLog) {
  process.stderr.write('WARNING: Could not parse run log JSON; skipping Discord notification\n');
  process.exit(0);
}

const prUrls = [];
if (Array.isArray(runLog.steps)) {
  for (const step of runLog.steps) {
    if (step.pr_url) {
      prUrls.push(step.pr_url);
    }
    if (Array.isArray(step.pr_urls)) {
      prUrls.push(...step.pr_urls);
    }
  }
}

if (prUrls.length === 0) {
  process.exit(0);
}

const stubOut = process.env.DISCORD_STUB_OUT;

async function sendWebhook(url, content) {
  if (stubOut) {
    fs.appendFileSync(stubOut, content + '\n');
    return;
  }
  try {
    await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content }),
    });
  } catch (e) {
    process.stderr.write(`WARNING: Failed to send Discord notification: ${e.message}\n`);
  }
}

(async () => {
  for (const url of prUrls) {
    await sendWebhook(webhookUrl, `New PR opened: ${url}`);
  }
  process.exit(0);
})();
