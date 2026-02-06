# Claw (Noctalia Plugin Source)

This repository is a **Noctalia plugin source** that can be added to the Noctalia plugin manager. It currently contains one plugin: `claw`.

## Install (via Noctalia Plugin Manager)

1. Add this repo as a plugin source:
   - Name: `DigitalPals Plugins`
   - URL: `https://github.com/DigitalPals/Claw`

2. Install the `Claw` plugin from the plugin list.

3. Enable the plugin and add the Claw bar widget to your bar.

## OpenClaw Gateway Setup

Claw talks to the OpenClaw Gateway using the OpenAI-compatible HTTP endpoint:
- `POST /v1/chat/completions`
- Default gateway URL: `http://127.0.0.1:18789`

In OpenClaw Gateway config, enable the endpoint (it is commonly disabled by default):
- `gateway.http.endpoints.chatCompletions.enabled = true`

Token auth is recommended when exposing the gateway remotely.

