# XiaoZhi Channel Integration Steps (Checklist)

This checklist helps you quickly set up and test `@xiaozhi_openclaw/xiaozhi`.

## 0. Preflight Checks

- [ ] Node.js `18+`
- [ ] OpenClaw Gateway can start
- [ ] xiaozhi-esp32-server-golang is running and exposes a WebSocket endpoint
- [ ] A JWT token is ready

## 1. Install the Plugin

### Option A: Use the OpenClaw plugin command (recommended)

```bash
openclaw plugins install @xiaozhi_openclaw/xiaozhi
```

To pin a version:

```bash
openclaw plugins install @xiaozhi_openclaw/xiaozhi@0.0.6
```

Check the installation:

```bash
openclaw plugins list
openclaw channels capabilities --channel xiaozhi
```

### Option B: Offline/local source install (only when online install is unavailable)

```bash
cp -r /path/to/xiaozhi_openclaw/openclaw-channel ~/.openclaw/extensions/xiaozhi
```

If `~/.openclaw/extensions/xiaozhi` already exists, remove the old directory before installing to avoid `plugin already exists`.

```bash
openclaw plugins uninstall xiaozhi
rm -rf ~/.openclaw/extensions/xiaozhi
```

If `clawhub` returns `429`, use this instead:

```bash
npx -y @xiaozhi_openclaw/xiaozhi@0.0.6 install
```

If `openclaw channels capabilities --channel xiaozhi` still fails after installation, run:

```bash
node /path/to/openclaw-channel/cli.mjs doctor
```

## 2. Configure the Gateway

Prefer the official OpenClaw commands:

```bash
openclaw config set channels.xiaozhi.enabled true --strict-json
openclaw config set channels.xiaozhi.url "ws://localhost:8080/ws/openclaw"
openclaw config set channels.xiaozhi.token "your-jwt-token"
```

Alternatively, edit `~/.openclaw/openclaw.json` directly. At minimum it must contain:

```json
{
  "channels": {
    "xiaozhi": {
      "enabled": true,
      "url": "ws://localhost:8080/ws/openclaw",
      "token": "your-jwt-token",
      "reconnectInterval": 5000,
      "heartbeatInterval": 30000,
      "heartbeatTimeout": 10000,
      "accounts": {
        "default": {
          "enabled": true,
          "url": "ws://localhost:8080/ws/openclaw",
          "token": "your-jwt-token"
        }
      },
      "defaultAccount": "default"
    }
  }
}
```

## 3. Start the Services

1. Start xiaozhi-esp32-server-golang

```bash
./xiaozhi-server --config config.yaml
```

2. Start the OpenClaw Gateway

```bash
openclaw gateway start
```

## 4. Verify Connectivity

### 4.1 Status Check

```bash
openclaw status
```

Expected:

```text
Channels:
  xiaozhi (default):
    Status: running
```

### 4.2 Log Check

```bash
openclaw gateway logs --follow
```

Expected to include at least:

```text
[xiaozhi:default] connecting to ws://localhost:8080/ws/openclaw
[xiaozhi:default] connected
[xiaozhi:default] received handshake_ack ...
```

### 4.3 Reconnect Check (important)

After restarting the peer service, expect to see:

```text
[xiaozhi:default] websocket error ...
[xiaozhi:default] scheduleReconnect called ...
[xiaozhi:default] reconnecting...
```

## 5. Common Issues

### 5.1 `Cannot find module 'ws'`

```bash
npm install ws
```

### 5.2 `Unsupported schema node. Use Raw mode.`

Upgrade to the current plugin version and restart the gateway; the current version uses a flat schema.

### 5.3 `Cannot find module 'openclaw/plugin-sdk/core'`

Upgrade to `0.0.5+` and retry; the current version removes runtime bare imports of the SDK from the installation directory.

### 5.4 `ClawHub ... 429: Rate limit exceeded`

Use this instead:

```bash
npx -y @xiaozhi_openclaw/xiaozhi@0.0.6 install
```

### 5.5 `Unknown channel: xiaozhi`

Check the following first:

```bash
openclaw plugins list
openclaw plugins doctor
openclaw channels capabilities --channel xiaozhi
node /path/to/openclaw-channel/cli.mjs doctor
```

If `plugins list` shows `xiaozhi` and `channels capabilities --channel xiaozhi` also succeeds, but `openclaw channels add --channel xiaozhi ...` still fails, switch to:

```bash
openclaw config set channels.xiaozhi.enabled true --strict-json
openclaw config set channels.xiaozhi.url "ws://localhost:8080/ws/openclaw"
openclaw config set channels.xiaozhi.token "<jwt>"
```

This happens because OpenClaw `2026.3.23-1`'s `channels add` subcommand does not preload the plugin registry for external channels.

### 5.6 Publish the npm package (if needed)

Current package name: `@xiaozhi_openclaw/xiaozhi`.

Run this in the `openclaw-channel` directory:

```bash
npm publish --access public --registry=https://registry.npmjs.org
```

## 6. References

- [Detailed Guide](./INTEGRATION_GUIDE.md)
- [Communication Protocol](./protocol/XIAOZHI_OPENCLAW_PROTOCOL.md)
