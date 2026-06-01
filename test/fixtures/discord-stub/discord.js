'use strict';

// Stub for discord.js WebhookClient used in bats tests.
// Writes each sent message to the file path in DISCORD_STUB_OUT env var.

const fs = require('fs');

class WebhookClient {
  constructor(opts) {
    this.url = opts.url;
  }

  async send(message) {
    const outFile = process.env.DISCORD_STUB_OUT;
    if (outFile) {
      fs.appendFileSync(outFile, message + '\n');
    }
  }
}

module.exports = { WebhookClient };
