# Discord Webhook Setup Guide

This guide walks through the one-time Discord and Jenkins configuration required for PR open notifications.

---

## Overview

The `shared/notify-pr-discord.js` script sends a Discord message whenever a PR is opened by the pipeline. It requires:

1. A Discord webhook URL from your Discord server
2. A Jenkins credential containing the webhook URL

---

## Step 1: Create a Discord Webhook

1. In Discord, open your server and navigate to the channel where you want PR notifications.
2. Click the gear icon next to the channel name to open **Edit Channel**.
3. Go to **Integrations** → **Webhooks** → **New Webhook**.
4. Give the webhook a name (e.g. `minordomo-prs`) and copy the **Webhook URL**.

---

## Step 2: Add a Jenkins Credential

In your Jenkins instance, create a **Secret text** credential:

| Credential ID         | Value                  |
|-----------------------|------------------------|
| `discord-webhook-url` | The Discord webhook URL |

**How to add:**
1. Go to **Jenkins** → **Manage Jenkins** → **Credentials** → **(global)** → **Add Credentials**.
2. Set **Kind** to `Secret text`.
3. Enter the credential ID exactly as `discord-webhook-url`.
4. Paste the webhook URL and save.

---

## Notes

- If the `discord-webhook-url` credential does not exist, Jenkins will fail to inject it and the build will fail. The credential must be created before deploying the Jenkinsfile changes that bind it.
- The notification script always exits 0 — a Discord delivery failure will not break builds.
- Notifications fire for all PRs opened by the pipeline: planning spec PRs, stage implementation PRs, and feature→main PRs.
