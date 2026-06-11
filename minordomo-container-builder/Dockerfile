FROM python:3.13-slim

# Use bash as /bin/sh so Jenkins sh steps and sourced scripts get bash built-ins
RUN ln -sf /bin/bash /bin/sh

# Create non-root agent user with UID 1000 to match Jenkins jnlp container convention
# so workspace files checked out by the jnlp container are writable by this user.
RUN useradd -u 1000 -m -s /bin/bash agent

# System deps: git, curl, gettext (for envsubst), Node.js 22, gh CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
        bats \
        curl \
        git \
        gnupg \
        make \
        shellcheck \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Verify script (util-linux) >= 2.37 for -e (exit-code propagation) support
RUN script --version \
    | awk '/util-linux/{ split($NF, v, "."); if (v[1]+0 > 2 || (v[1]+0 == 2 && v[2]+0 >= 37)) exit 0; exit 1 }' \
    || { echo "ERROR: script (util-linux) >= 2.37 required for -e flag"; exit 1; }

# uv (fast Python package runner) — used to run the mcp-atlassian MCP server via uvx
# Install to /usr/local/bin so it's available to all users without a HOME-relative PATH
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# beads CLI (bd) — agent task coordination; pin to a specific version
RUN BEADS_VERSION=1.0.4 \
    && curl -fsSL "https://github.com/gastownhall/beads/releases/download/v${BEADS_VERSION}/beads_${BEADS_VERSION}_linux_amd64.tar.gz" \
        | tar -xz -C /usr/local/bin bd \
    && bd --version

# discord.js — used by shared/notify-pr-discord.js for PR notifications
RUN mkdir -p /opt/discord-notify && \
    printf '{"name":"discord-notify","version":"1.0.0","dependencies":{"discord.js":"^14.16.3"}}' \
        > /opt/discord-notify/package.json && \
    npm install --prefix /opt/discord-notify --omit=dev
ENV NODE_PATH=/opt/discord-notify/node_modules

# Python dependencies
COPY minordomo-container-builder/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Switch to non-root agent user for Claude Code install and all runtime execution.
# --dangerously-skip-permissions requires non-root; this is the primary motivation.
# ENV HOME must be set explicitly — Docker's USER directive does not update $HOME,
# so without it shell expansions like ~/.claude write to /.claude (permission denied).
USER agent
ENV HOME=/home/agent
ENV PATH="/home/agent/.local/bin:$PATH"

# Claude Code CLI — installed as agent user so it lands in /home/agent/.local/bin
RUN curl -fsSL https://claude.ai/install.sh | bash
