#!/usr/bin/env node
'use strict';

const fs = require('fs');
const { spawnSync } = require('child_process');

// Step 0: scope guard — no-op for non-interactive runs
if (process.env.INTERACTIVE_MODE !== 'true') {
  process.exit(0);
}

let inputData = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { inputData += chunk; });
process.stdin.on('end', () => {
  let hookInput;
  try {
    hookInput = JSON.parse(inputData);
  } catch (e) {
    process.stderr.write(`claude-stop-hook: failed to parse hook input: ${e.message}\n`);
    process.exit(1);
  }

  const transcriptPath = hookInput.transcript_path;
  if (!transcriptPath) {
    process.stderr.write('claude-stop-hook: no transcript_path in hook input\n');
    process.exit(1);
  }

  // Step 1: persist transcript path for Stage 3 log analysis scripts
  fs.writeFileSync('/tmp/claude-transcript-path.txt', transcriptPath);

  // Step 2: read last assistant message from JSONL transcript
  let lastAssistantText = '';
  const lines = fs.readFileSync(transcriptPath, 'utf8').split('\n');
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const entry = JSON.parse(line);
      if (entry.type === 'assistant') {
        const content = entry.message && entry.message.content;
        if (Array.isArray(content)) {
          const text = content
            .filter(c => c.type === 'text')
            .map(c => c.text || '')
            .join('');
          lastAssistantText = text;
        } else if (typeof content === 'string') {
          lastAssistantText = content;
        }
      }
    } catch (_) {
      // skip malformed lines
    }
  }

  const trimmed = lastAssistantText.trim();

  // Step 3: branch on NEEDS_INPUT: prefix
  if (trimmed.startsWith('NEEDS_INPUT:')) {
    const question = trimmed.slice('NEEDS_INPUT:'.length).trim();
    const repo = process.env.REPO || '';
    const ghIssueNumber = process.env.GH_ISSUE_NUMBER || '';
    const beadsTaskId = process.env.BEADS_TASK_ID || '';
    spawnSync('shared/apply-needs-input.sh', [repo, ghIssueNumber, beadsTaskId, question], { stdio: 'inherit' });
  }
  // Signal run-claude.sh to terminate the session (works for both completion
  // and needs-input — in both cases there is nothing more for Claude to do).
  // Exit 0 allows Claude to stop; the monitor in run-claude.sh does the kill.
  fs.writeFileSync('/tmp/claude-session-done', '1');
  process.exit(0);
});
