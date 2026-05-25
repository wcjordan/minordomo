#!/usr/bin/env bash
# Reads shared/safety-rules.yaml and regenerates the deny list in shared/agent-settings.json
# and the generated section in shared/pre-bash-guard.sh.
# Run this script after editing safety-rules.yaml, then commit all three files together.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO_ROOT="$REPO_ROOT" python3 - <<'PYEOF'
import json
import sys
import os
import re

repo_root = os.environ['REPO_ROOT']
yaml_path     = os.path.join(repo_root, 'shared', 'safety-rules.yaml')
settings_path = os.path.join(repo_root, 'shared', 'agent-settings.json')
guard_path    = os.path.join(repo_root, 'shared', 'pre-bash-guard.sh')

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. Run: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)

with open(yaml_path) as f:
    config = yaml.safe_load(f)
rules = config['rules']

# --- Build deny list entries ---
deny_entries = []
for rule in rules:
    globs = rule.get('deny_globs') or ([rule['deny_glob']] if 'deny_glob' in rule else [])
    for g in globs:
        deny_entries.append(f'Bash({g})')

# --- Update agent-settings.json ---
with open(settings_path) as f:
    settings = json.load(f)
settings['permissions']['deny'] = deny_entries
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

# --- Build generated guard section ---
lines = []
lines.append('# BEGIN GENERATED SECTION - do not edit manually, run shared/generate-safety-rules.sh')
for rule in rules:
    desc = rule['description']
    patterns = rule.get('bash_pattern_all') or []
    single = rule.get('bash_pattern')
    if single:
        patterns = [single]
    condition_parts = [f"matches '{p}'" for p in patterns]
    condition = ' && \\\n   '.join(condition_parts)
    lines.append(f'if {condition}; then')
    lines.append(f'    block "{desc}"')
    lines.append('fi')
    lines.append('')
lines.append('# END GENERATED SECTION')
generated_section = '\n'.join(lines)

# --- Update pre-bash-guard.sh ---
with open(guard_path) as f:
    guard_content = f.read()

pattern = re.compile(
    r'# BEGIN GENERATED SECTION.*?# END GENERATED SECTION',
    re.DOTALL
)
if not pattern.search(guard_content):
    print("ERROR: Generated section markers not found in pre-bash-guard.sh", file=sys.stderr)
    sys.exit(1)

new_content = pattern.sub(lambda m: generated_section, guard_content)
with open(guard_path, 'w') as f:
    f.write(new_content)

print(f"Generated deny list with {len(deny_entries)} entries.")
print(f"Updated: {settings_path}")
print(f"Updated: {guard_path}")
PYEOF
