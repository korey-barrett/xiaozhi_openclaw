# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repo bridges `xiaozhi-esp32-server-golang` (WebSocket server, ESP32 voice devices) and an OpenClaw Gateway. It has two layers:

- **`openclaw-channel/`** — the deliverable: an OpenClaw channel plugin published to npm as `@xiaozhi_openclaw/xiaozhi` (currently `0.0.6`). Written in TypeScript, shipped **uncompiled** (`main`/`openclaw.extensions` point at `./index.ts`), loaded by OpenClaw's TypeScript runtime.
- **Repo root** — integration tooling and docs: `generate-token.js` (JWT helper), `apply-config.sh` / `config-patch.json` (legacy jq-based config merge, includes a hard-coded path from the original environment), and `README.md` / `INTEGRATION_GUIDE.md` / `INTEGRATION_STEPS.md` (English).

`protocol/XIAOZHI_OPENCLAW_PROTOCOL.md` is the source of truth for the wire protocol. Read it before changing message semantics.

## Commands

There is no build, lint, or test setup. `npm test` at the root intentionally fails (`"Error: no test specified"`).

```bash
# Install dependencies
npm install                              # root: jsonwebtoken for generate-token.js
npm install --prefix openclaw-channel    # ws, required by the plugin at runtime

# Generate a test JWT (args: user_id agent_id [endpoint_id] [expires_in])
node generate-token.js 1 main agent_main
# Uses JWT_SECRET env var, else the default test secret xiaozhi_admin_secret_key

# Develop locally: link the source dir into OpenClaw, restart gateway after edits
openclaw plugins install --link ./openclaw-channel

# Installer / diagnostics (run from the package directory)
node openclaw-channel/cli.mjs install [--dry-run] [--link]
node openclaw-channel/cli.mjs doctor
node openclaw-channel/cli.mjs setup --url ws://localhost:8080/ws/openclaw --token <jwt>

# Configure the channel (preferred over `channels add`, which reports "Unknown channel" for external plugins)
openclaw config set channels.xiaozhi.enabled true --strict-json
openclaw config set channels.xiaozhi.url "ws://localhost:8080/ws/openclaw"
openclaw config set channels.xiaozhi.token "<jwt>"

# Release (from openclaw-channel/)
npm publish --access public --registry=https://registry.npmjs.org
```

Installer environment overrides: `OPENCLAW_BIN`, `OPENCLAW_CONFIG_FILE`, `OPENCLAW_CONFIG_DIR`, `OPENCLAW_STATE_DIR`.

A release requires bumping the version in three places: `openclaw-channel/package.json`, `plugin.version` in `openclaw-channel/index.ts`, and `openclaw-channel/openclaw.plugin.json`.

### Commit conventions

Do not add `Co-Authored-By` lines or "Generated with ..." attribution footers naming any AI agent, assistant, or coding harness (Claude, Claude Code, Copilot, Cursor, Codex, Gemini, or others) to commits, pull requests, or generated files.

## Architecture

### Plugin registration and lifecycle

`index.ts` is the OpenClaw extension entry. It stores the host runtime via `setXiaozhiRuntime()` and registers `xiaozhiPlugin` from `channel.ts`.

`channel.ts` is the `ChannelPlugin` definition — metadata, flat config schema, account setup, outbound send, status, and `gateway.startAccount`. `startAccount` calls `monitorXiaozhiProvider()` and then stays alive until the gateway aborts the account.

### Connection layer (`client.ts`, `websocket.ts`, `send.ts`)

- `client.ts` owns the socket lifecycle: connect to `<url>?token=<jwt>`, reconnect with `reconnectInterval`, heartbeat (`ping` every `heartbeatInterval`, close after 3 consecutive missed `pong`s), and stale-socket guards.
- Handshake order is inverted from intuition: the **server** sends `handshake_ack` first; only then does the client send `handshake` and mark the connection live (firing `onConnect`). Do not treat `onopen` as connected.
- `websocket.ts` resolves the WebSocket constructor, preferring the `ws` package over the runtime-global `WebSocket` (Node/undici can fail with an opaque error before `open`). The constructor is cached. If neither exists it throws; this is why `ws` is a real dependency.
- `send.ts` builds the `response` envelope. `correlation_id` is the inbound message id; `payload.metadata.device_id` is always injected so the server can route to the right ESP32.

### Inbound pipeline (`monitor.ts`)

For each `message` from the server:

1. Resolve the OpenClaw agent route, then override with the selection precedence: `metadata.openclaw_agent_id` (also binds the device) > existing per-device binding > token `agent_id` claim > routed agent. Unknown agent ids fall back to the routed agent.
2. Session key is the route's key for the routed agent, otherwise `xiaozhi:<accountId>:<agentId>:<deviceId>`.
3. Session id: reuse `payload.session_id`, else the per-device cache, else generate `xiaozhi-{user}-{device}-{timestamp}-{uuid8}`. It is returned in every response.
4. Call `dispatchReplyWithBufferedBlockDispatcher` and send the result in one of two modes:
   - **Non-stream (default):** buffer all deliverable text and send one final `response` with no stream metadata.
   - **Stream (`payload.metadata.stream === true`):** emit queued `response` frames with `stream_id`/`seq`/`phase`/`content_type`; deltas are `phase=chunk`, rewrites are `phase=snapshot` (the receiver must replace, not append), and a final `done=true, phase=final` frame is always sent with `reason` `complete` or `error`. The final frame may have empty `content`.

`classifyStreamTextUpdate()` and the per-message `StreamMessageState` array handle partials and multi-message replies; treat emitted text as the source of truth when deciding delta vs. snapshot.

### Runtime state (`runtime.ts`)

Module-global maps hold the host `PluginRuntime` and live connections keyed by account id. `monitor` registers a connection on connect and clears it on disconnect; `channel.outbound.sendText` reads it for proactive sends. Duplicate monitor starts for the same account are detected and the previous one stopped.

### SDK shim (`sdk-shim.ts`)

OpenClaw SDK helpers are reimplemented locally because `0.0.5+` removed runtime resolution of `openclaw/plugin-sdk/*` from the installed extension directory. **Invariant:** imports from `openclaw/*` in this package must be `import type` only (erased at runtime); all runtime helpers come from `sdk-shim.ts`. Adding a value import from `openclaw/*` reintroduces the "Cannot find module openclaw/plugin-sdk/core" failure. Relative imports use `.js` specifiers even though the files are `.ts` — keep that convention.

### Config model (`accounts.ts`, `config-schema.ts`)

Config lives under `channels.xiaozhi`. Both a flat form (`enabled`/`url`/`token` at channel level) and an `accounts` map are supported; per-account values are shallow-merged over channel-level base fields. The default account is `channels.xiaozhi.defaultAccount` if valid, else `"default"`. Account ids are normalized to lowercase `[a-z0-9_-]`. Keep the channel config schema **flat** (no wrapped nodes) — older OpenClaw admin UIs throw "Unsupported schema node" otherwise. Token claims are decoded client-side without signature verification; only the server validates the JWT.
