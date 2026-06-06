#!/usr/bin/env node
'use strict';

// Stub for discord-send.js used in bats tests.
// Writes the message argument to the file path in DISCORD_STUB_OUT env var.

const fs = require('fs');

const message = process.argv[2];
const outFile = process.env.DISCORD_STUB_OUT;
if (outFile && message) {
  fs.appendFileSync(outFile, message + '\n');
}
process.exit(0);
