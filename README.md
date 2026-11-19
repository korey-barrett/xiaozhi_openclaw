# XiaoZhi ESP32 and OpenClaw Integration Project

This project provides a complete integration between xiaozhi-esp32-server-golang and the OpenClaw Gateway.

## Project Structure

```
xiaozhi-integration/
├── protocol/                          # Communication protocol documentation
│   └── XIAOZHI_OPENCLAW_PROTOCOL.md  # Detailed WebSocket communication protocol
├── openclaw-channel/                 # OpenClaw Channel implementation
│   ├── index.ts                      # Plugin entry point
│   ├── channel.ts                    # Main Channel plugin file
│   ├── client.ts                     # WebSocket client implementation
│   ├── monitor.ts                    # Monitoring and message routing
│   ├── types.ts                      # TypeScript type definitions
│   ├── accounts.ts                   # Account management
│   ├── config-schema.ts              # Configuration schema
│   ├── normalize.ts                  # Target normalization
│   ├── send.ts                       # Message sending
│   ├── runtime.ts                    # Runtime interface
│   ├── utils.ts                      # Utility functions
│   ├── package.json                  # Package configuration
│   └── openclaw.plugin.json         # Plugin metadata
├── INTEGRATION_GUIDE.md             # OpenClaw integration guide
└── README.md                        # This file
```

## Quick Start

### 1. Learn the Protocol

Start with the [communication protocol documentation](./protocol/XIAOZHI_OPENCLAW_PROTOCOL.md) to understand the WebSocket message format and interaction flow.

### 2. Integrate with OpenClaw

Follow the steps in the [Integration Guide](./INTEGRATION_GUIDE.md):

1. Copy the `openclaw-channel` directory into the OpenClaw extensions directory
2. Configure the OpenClaw Gateway
3. Start the services

### 3. Implement the xiaozhi-esp32-server-golang Side

Implement the following in the xiaozhi-esp32-server-golang project according to the protocol documentation:

- The `/ws/openclaw` WebSocket endpoint
- Token validation (JWT parsing)
- Message handling (message, ping/pong, response, and so on)
- ESP32 device communication

## Core Features

### Communication Protocol

- ✅ Bidirectional WebSocket communication
- ✅ JWT token authentication
- ✅ Message types: handshake, message, response, ping/pong, error, close
- ✅ Heartbeat mechanism
- ✅ Automatic reconnect

### OpenClaw Channel

- ✅ Complete Channel plugin implementation
- ✅ WebSocket client (with reconnect and heartbeat)
- ✅ Message routing and handling
- ✅ Session management
- ✅ Multi-account support
- ✅ Status monitoring

### Message Flow

```
ESP32 device
    ↓ (voice)
xiaozhi-esp32-server-golang
    ↓ (STT → text → WebSocket message)
OpenClaw Gateway (xiaozhi channel)
    ↓ (forward to Agent)
AI Agent
    ↓ (generate reply)
OpenClaw Gateway
    ↓ (WebSocket response)
xiaozhi-esp32-server-golang
    ↓ (TTS → audio)
ESP32 device (playback)
```

## Configuration Example

### OpenClaw Configuration

```json
{
  "channels": {
    "xiaozhi": {
      "enabled": true,
      "url": "ws://localhost:8080/ws/openclaw",
      "token": "your-jwt-token",
      "reconnectInterval": 5000,
      "heartbeatInterval": 30000,
      "heartbeatTimeout": 10000
    }
  }
}
```

### xiaozhi-esp32-server-golang Configuration

```yaml
websocket:
  xiaozhi:
    enabled: true
    path: "/ws/openclaw"
    jwt_secret: "your-secret-key"

esp32:
  devices:
    - id: "esp32-001"
      name: "Living Room Speaker"
      user_id: "user-123"
```

## Token Generation

### JWT Payload

```json
{
  "user_id": 1,
  "agent_id": "main",
  "endpoint_id": "agent_main",
  "purpose": "openclaw-endpoint"
}
```

### Generation Example

```javascript
const jwt = require('jsonwebtoken');
const token = jwt.sign(
  {
    user_id: 1,
    agent_id: 'main',
    endpoint_id: 'agent_main',
    purpose: 'openclaw-endpoint',
  },
  'your-secret-key',
  {}
);
console.log(token);
```

## Documentation

- [Communication Protocol](./protocol/XIAOZHI_OPENCLAW_PROTOCOL.md) - Detailed WebSocket communication protocol
- [Integration Guide](./INTEGRATION_GUIDE.md) - How to integrate this channel into OpenClaw

## Tech Stack

- **OpenClaw Channel**: TypeScript
- **WebSocket**: ws (Node.js)
- **Authentication**: JWT
- **Protocol**: JSON over WebSocket

## Features

- 🔒 Secure: JWT token authentication
- 💪 Reliable: Automatic reconnect + heartbeat detection
- 🔌 Extensible: Support for multiple accounts and devices
- 📝 Observable: Complete logging and status monitoring
- 🎯 Simple: Concise protocol and API

## Planned Features

The following features are not fully implemented yet and need further work:

1. **Complete the OpenClaw integration points**
   - `processMessage` needs to be wired to the OpenClaw Gateway message handler
   - `registerOutboundHandler` needs to be registered with the Gateway
   - `getConnection` needs to retrieve the connection from the Gateway runtime

2. **OpenClaw CLI tools**
   - `openclaw xiaozhi token generate` - Generate a token
   - `openclaw xiaozhi token verify` - Verify a token
   - `openclaw xiaozhi status` - Show channel status

3. **Tests**
   - Unit tests
   - Integration tests
   - End-to-end tests

4. **Session persistence**
   - Session ID storage and recovery
   - Session history queries

5. **TTS/STT integration**
   - Audio format support (if needed in the future)

## Contributing

Issues and pull requests are welcome!

## License

MIT License

## Version

v1.0.0 - 2026-02-28

- Initial version
- Basic WebSocket communication protocol
- OpenClaw Channel implementation
