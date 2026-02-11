# OpenClaw Chat (Noctalia Plugin)

OpenClaw Chat adds a menu bar widget that opens a chat panel. The panel connects to an OpenClaw Gateway (local or remote) via the OpenAI-compatible `POST /v1/chat/completions` endpoint.

## Settings

- `Gateway URL`: Base URL for the gateway (default `http://127.0.0.1:18789`).
- `Token`: Sent as `Authorization: Bearer <token|password>` when set.
- `Agent ID`: Sent as `x-openclaw-agent-id` and also used as `model: openclaw:<agentId>`.
- `User`: Sent as OpenAI `user` to help stable session routing (default `noctalia:claw`).
- `Session Key` (optional): If set, sent as `x-openclaw-session-key`.
- `Stream responses (SSE)`: Attempts SSE streaming; falls back to non-streaming when necessary.

## Chat History

Chat history is kept in memory by the plugin main instance, so you can close and reopen the panel and continue the conversation.

## Troubleshooting

- HTTP 404: the chat-completions endpoint may be disabled in the gateway. Enable:
  - `gateway.http.endpoints.chatCompletions.enabled = true`
- HTTP 401/403: token/auth is wrong or required but missing.
