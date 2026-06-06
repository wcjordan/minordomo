#!/usr/bin/env node
'use strict';

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

let WebhookClient;
try {
  ({ WebhookClient } = require('discord.js'));
} catch (e) {
  process.stderr.write('WARNING: discord.js module is not available; skipping Discord notification\n');
  process.exit(0);
}

const message = process.argv[2];
if (!message) {
  process.stderr.write('WARNING: No message provided; skipping Discord notification\n');
  process.exit(0);
}

(async () => {
  const client = new WebhookClient({ url: webhookUrl });
  try {
    await client.send(message);
  } catch (e) {
    process.stderr.write(`WARNING: Failed to send Discord notification: ${e.message}\n`);
  }
  process.exit(0);
})();
