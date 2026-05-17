FROM python:3.13-slim

# Use bash as /bin/sh so Jenkins sh steps and sourced scripts get bash built-ins
RUN ln -sf /bin/bash /bin/sh

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

# Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# uv (fast Python package runner) — used to run the mcp-atlassian MCP server via uvx
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# beads CLI (bd) — agent task coordination; pin to a specific version
RUN BEADS_VERSION=1.0.4 \
    && curl -fsSL "https://github.com/gastownhall/beads/releases/download/v${BEADS_VERSION}/beads_${BEADS_VERSION}_linux_amd64.tar.gz" \
        | tar -xz -C /usr/local/bin bd \
    && bd --version

# Python dependencies
COPY minordomo-container-builder/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
