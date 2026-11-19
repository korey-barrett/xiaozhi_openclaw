# xiaozhi-esp32-server-golang and OpenClaw WebSocket Communication Protocol

## Overview

This protocol defines the WebSocket communication contract between xiaozhi-esp32-server-golang and the OpenClaw Gateway.

- **xiaozhi-esp32-server-golang**: WebSocket server
- **OpenClaw Gateway**: WebSocket client

## 1. Connection

### 1.1 Connection Endpoint

```
ws://<host>:<port>/ws/openclaw?token=<token>
```

### 1.2 URL Parameters

| Parameter | Type | Required | Description |
|------|------|------|------|
| token | string | Yes | JWT token containing user and agent information |

### 1.3 Token Format

The token should be in JWT format. It is recommended to use the token returned by the XiaoZhi server's endpoint API directly. The server currently uses snake_case claims:

```json
{
  "user_id": 1,
  "agent_id": "main",
  "endpoint_id": "agent_main",
  "purpose": "openclaw-endpoint"
}
```

| Field | Type | Required | Description |
|------|------|------|------|
| user_id | number | Yes | User ID |
| agent_id | string | Yes | Agent ID |
| endpoint_id | string | Yes | Endpoint identifier (usually `agent_<agentId>`) |
| purpose | string | No | Recommended to be fixed as `openclaw-endpoint` |
| exp/iat | number | No | Optional when the caller signs its own token |

### 1.4 Connection Flow

```
1. OpenClaw establishes a connection: ws://<host>:<port>/ws/openclaw?token=<token>
2. xiaozhi validates the token and accepts the connection if validation succeeds
3. xiaozhi sends handshake_ack
4. OpenClaw sends handshake
5. Both sides enter the message communication phase
```

## 2. Message Format

### 2.1 Common Envelope

All messages use the following JSON format:

```json
{
  "id": "uuid-v4",
  "timestamp": 1737264000000,
  "type": "<message-type>",
  "payload": {}
}
```

| Field | Type | Required | Description |
|------|------|------|------|
| id | string | Yes | Unique message identifier (UUID v4) |
| timestamp | number | Yes | Timestamp (milliseconds) |
| type | string | Yes | Message type |
| payload | object | Yes | Message content |

### 2.2 Message Types

| Type | Direction | Description |
|------|------|------|
| `handshake` | OpenClaw → xiaozhi | Connection handshake |
| `handshake_ack` | xiaozhi → OpenClaw | Handshake acknowledgement (sent immediately when the connection is established) |
| `message` | xiaozhi → OpenClaw | User message (text) |
| `response` | OpenClaw → xiaozhi | AI response (text; supports streaming chunks and an end marker) |
| `ping` | Bidirectional | Heartbeat |
| `pong` | Bidirectional | Heartbeat response |
| `error` | Bidirectional | Error message |
| `close` | Bidirectional | Close connection |

## 3. Message Definitions

### 3.1 handshake - Handshake

**Direction:** OpenClaw → xiaozhi

```json
{
  "id": "handshake-001",
  "timestamp": 1737264000000,
  "type": "handshake",
  "payload": {
    "version": "1.0.0",
    "client": "openclaw-gateway",
    "capabilities": ["text"]
  }
}
```

| Field | Type | Description |
|------|------|------|
| version | string | Protocol version |
| client | string | Client identifier |
| capabilities | array<string> | Supported capabilities (currently only "text") |

### 3.2 handshake_ack - Handshake Acknowledgement

**Direction:** xiaozhi → OpenClaw

**Description:** Sent immediately after the connection is established; no need to wait for handshake.

```json
{
  "id": "handshake-ack-001",
  "timestamp": 1737264000000,
  "type": "handshake_ack",
  "payload": {
    "version": "1.0.0",
    "server": "xiaozhi-esp32-server"
  }
}
```

| Field | Type | Description |
|------|------|------|
| version | string | Protocol version |
| server | string | Server identifier |

### 3.3 message - User Message

**Direction:** xiaozhi → OpenClaw

```json
{
  "id": "msg-001",
  "timestamp": 1737264002000,
  "type": "message",
  "payload": {
    "content": "What's the weather like today?",
    "session_id": "session-abc",
    "metadata": {}
  }
}
```

| Field | Type | Required | Description |
|------|------|------|------|
| content | string | Yes | User message content (plain text) |
| session_id | string | No | Session ID (used to preserve context) |
| metadata | object | No | Metadata |

#### 3.3.1 Agent Selection and Binding (controlled by xiaozhi)

By default, OpenClaw selects the agent according to its own routing rules.

If xiaozhi needs to specify an agent and bind it at the device level, include the following in `message.payload.metadata`:

| Field | Type | Description |
|------|------|------|
| openclaw_agent_id | string | Specifies the OpenClaw agent for this message and automatically binds it to the device |

Notes:

- Binding dimension: `account + device_id`
- After binding, subsequent messages that do not explicitly specify an agent preferentially use the bound agent

Example (specify and bind to `weather_assistant`):

```json
{
  "id": "msg-001",
  "timestamp": 1737264002000,
  "type": "message",
  "payload": {
    "content": "Check today's weather in Hangzhou for me",
    "metadata": {
      "openclaw_agent_id": "weather_assistant"
    }
  }
}
```

#### 3.3.2 Streaming Reply Switch (controlled by xiaozhi)

By default, OpenClaw uses **non-streaming replies** for this protocol (for backward compatibility).

If xiaozhi needs streaming chunked replies, explicitly set the following in `message.payload.metadata`:

- The only switch: `stream: true`

Example (enable streaming):

```json
{
  "id": "msg-001",
  "timestamp": 1737264002000,
  "type": "message",
  "payload": {
    "content": "Check the inventory and summarize it.",
    "session_id": "session-abc",
    "metadata": {
      "stream": true
    }
  }
}
```

### 3.4 response - AI Response

**Direction:** OpenClaw → xiaozhi

```json
{
  "id": "resp-001",
  "timestamp": 1737264003000,
  "type": "response",
  "correlation_id": "msg-001",
  "payload": {
    "content": "Querying, please wait...",
    "session_id": "session-abc",
    "metadata": {
      "stream_id": "stream-001",
      "seq": 1,
      "done": false,
      "phase": "chunk"
    }
  }
}
```

| Field | Type | Required | Description |
|------|------|------|------|
| correlation_id | string | Yes | Corresponding message ID |
| content | string | Yes* | AI response content (plain text); when `metadata.done=true`, it may be an empty string as the end frame |
| session_id | string | No | Session ID |
| metadata | object | No | Metadata (may include `agent_id`; see below for streaming) |

Non-streaming (default):

- OpenClaw returns a single `response`
- `metadata` may be empty and does not contain `stream_id/seq/done`

#### 3.4.1 response Streaming Chunks and End Rules

OpenClaw sends multiple consecutive `response` messages for the same `correlation_id` only when xiaozhi explicitly enables streaming in `message.payload.metadata`.

Recommended fields in `payload.metadata`:

| Field | Type | Required | Description |
|------|------|------|------|
| agent_id | string | No | The OpenClaw agent actually used for this reply |
| stream_id | string | No | Stream ID; all chunks of the same reply round use the same value |
| seq | number | No | Chunk sequence number, incrementing from 1 |
| done | boolean | No | Whether this chunk ends the reply. `true` means the reply round is finished |
| phase | string | No | Chunk phase; recommended values: `chunk` / `snapshot` / `final` |
| content_type | string | No | Content semantics: `delta` (append increment) / `snapshot` (full-sentence snapshot) |
| reason | string | No | End reason (recommended only when `done=true`): `complete` / `error` |

Streaming recommendations:

1. Incremental chunk: `done=false`, `phase=chunk`; recommended to also include `content_type=delta`; `content` is the newly added text.
2. If a full-sentence rewrite or snapshot occurs: `done=false`; use `phase=snapshot`, and recommended to include `content_type=snapshot`; in this case `content` is the current full text snapshot, not an appended fragment.
3. End chunk: `done=true`, `phase=final`; recommended to include `reason`.
4. If the end chunk is only used to signal the end, it may send empty `content` (`""`).
5. The receiver uses `done=true` as the end marker for a reply round, rather than relying on a timeout or connection close.

Example (same `correlation_id`):

```json
{
  "id": "resp-001",
  "timestamp": 1737264003000,
  "type": "response",
  "correlation_id": "msg-001",
  "payload": {
    "content": "I'm working on the task, please wait.",
    "session_id": "session-abc",
    "metadata": { "stream_id": "stream-001", "seq": 1, "done": false, "phase": "chunk" }
  }
}
```

```json
{
  "id": "resp-002",
  "timestamp": 1737264006000,
  "type": "response",
  "correlation_id": "msg-001",
  "payload": {
    "content": "Task in progress; a few more seconds expected.",
    "session_id": "session-abc",
    "metadata": { "stream_id": "stream-001", "seq": 2, "done": false, "phase": "chunk" }
  }
}
```

```json
{
  "id": "resp-003",
  "timestamp": 1737264009000,
  "type": "response",
  "correlation_id": "msg-001",
  "payload": {
    "content": "",
    "session_id": "session-abc",
    "metadata": { "stream_id": "stream-001", "seq": 3, "done": true, "phase": "final", "reason": "complete" }
  }
}
```

#### 3.4.2 Receiver Parsing Recommendations (xiaozhi)

Recommended order for the receiver to parse `response`:

1. Process only `type=response` messages; use `correlation_id` to group the same question-answer round.
2. Prefer to save `payload.session_id` for context reuse in the next round.
3. Determine whether it is a streaming chunk (if any of `stream_id` / `seq` / `done` / `phase` appears in `metadata`).
4. Non-streaming: treat `content` as the final reply.
5. Streaming: maintain a buffer keyed by `(correlation_id, stream_id)`, concatenate text in increasing `seq` order, and end the round when `done=true`.

Parsing notes:

- The end chunk may have `content=""`; this is a valid end frame and should not be treated as an error.
- `done=true` only means "the stream has ended"; it does not mean another "full body" will be sent.
- If a `phase=snapshot` frame is received, replace the accumulated text with that frame's `content` instead of appending.
- If duplicate or out-of-order chunks are received, deduplicate by `seq` (ignore `seq <= lastSeq`).

Example pseudocode:

```ts
type StreamState = { text: string; lastSeq: number };
const streams = new Map<string, StreamState>();

function onResponse(msg: any) {
  const cid = String(msg.correlation_id || "");
  const payload = msg.payload || {};
  const md = payload.metadata || {};
  const content = String(payload.content || "");
  const sessionId = payload.session_id;
  if (sessionId) saveSessionId(sessionId);

  const isStream =
    typeof md.stream_id === "string" ||
    typeof md.seq === "number" ||
    typeof md.done === "boolean" ||
    md.phase === "chunk" ||
    md.phase === "snapshot" ||
    md.phase === "final";

  if (!isStream) {
    handleFinalText(cid, content);
    return;
  }

  const key = `${cid}:${md.stream_id || "default"}`;
  const st = streams.get(key) || { text: "", lastSeq: 0 };
  const seq = typeof md.seq === "number" ? md.seq : st.lastSeq + 1;
  if (seq <= st.lastSeq) return;

  if (content) {
    if (md.phase === "snapshot") {
      st.text = content;
      handleSnapshotText(cid, content);
    } else {
      st.text += content;
      handleChunkText(cid, content);
    }
  }

  st.lastSeq = seq;
  streams.set(key, st);

  if (md.done === true) {
    handleStreamDone(cid, st.text, md.reason || "complete");
    streams.delete(key);
  }
}
```

### 3.5 ping/pong - Heartbeat

**Direction:** Bidirectional

**ping:**

```json
{
  "id": "ping-001",
  "timestamp": 1737264000000,
  "type": "ping",
  "payload": {
    "seq": 1
  }
}
```

**pong:**

```json
{
  "id": "pong-001",
  "timestamp": 1737264000000,
  "type": "pong",
  "correlation_id": "ping-001",
  "payload": {
    "seq": 1
  }
}
```

| Field | Type | Required | Description |
|------|------|------|------|
| seq | number | Yes | Sequence number |
| correlation_id | string | Yes | In pong, the id of the corresponding ping |

**Heartbeat mechanism:**

- The sender sends a ping every 30 seconds
- The receiver should reply with pong within 10 seconds
- If 3 consecutive heartbeats are missed, close the connection

### 3.6 error - Error Message

**Direction:** Bidirectional

```json
{
  "id": "error-001",
  "timestamp": 1737264000000,
  "type": "error",
  "correlation_id": "msg-001",
  "payload": {
    "code": "INVALID_MESSAGE",
    "message": "Invalid message format"
  }
}
```

| Field | Type | Required | Description |
|------|------|------|------|
| correlation_id | string | No | Related message ID (if any) |
| code | string | Yes | Error code |
| message | string | Yes | Error description |

**Error code list:**

| Error Code | Description |
|--------|------|
| INVALID_MESSAGE | Invalid message format |
| AUTH_FAILED | Authentication failed |
| UNAUTHORIZED | Unauthorized |
| RATE_LIMITED | Rate limited |
| INTERNAL_ERROR | Internal error |
| SESSION_NOT_FOUND | Session not found |

### 3.7 close - Close Connection

**Direction:** Bidirectional

```json
{
  "id": "close-001",
  "timestamp": 1737264000000,
  "type": "close",
  "payload": {
    "reason": "normal_shutdown",
    "code": 1000
  }
}
```

| Field | Type | Required | Description |
|------|------|------|------|
| reason | string | No | Close reason |
| code | number | Yes | WebSocket close code |

## 4. Session Management

### 4.1 Session ID Generation Rules

Session IDs are generated and managed by the OpenClaw Gateway.

Format: `xiaozhi-{user_id}-{device_id}-{timestamp}`

Example: `xiaozhi-user-123-esp32-001-1737264000000`

### 4.2 Session Lifecycle

1. On the first connection, OpenClaw generates a new session_id.
2. Return the session_id in the response.
3. xiaozhi saves the session_id and includes it in subsequent messages.
4. If the WebSocket disconnects and reconnects, the session_id may be reused or a new one generated.

## 5. Workflow Examples

### 5.1 Complete Conversation Flow

```
1. OpenClaw connects
   ws://xiaozhi-host:8080/ws/openclaw?token=<jwt>

2. xiaozhi sends handshake_ack
   {
     "id": "...",
     "type": "handshake_ack",
     "payload": { "version": "1.0.0", "server": "xiaozhi-esp32-server" }
   }

3. OpenClaw sends handshake
   {
     "id": "...",
     "type": "handshake",
     "payload": { "version": "1.0.0", "client": "openclaw-gateway", "capabilities": ["text"] }
   }

4. The user speaks on the device: "What's the weather like today?"

5. ESP32 → xiaozhi-esp32-server-golang (voice data)
   xiaozhi-esp32-server-golang performs STT and obtains text

6. xiaozhi sends message
   {
     "id": "msg-001",
     "type": "message",
     "payload": { "content": "What's the weather like today?" }
   }

7. OpenClaw Gateway processes the message
   - Invokes the Agent
   - Agent returns a response

8. OpenClaw sends a single response by default (non-streaming)
   {
     "id": "resp-001",
     "type": "response",
     "correlation_id": "msg-001",
     "payload": {
       "content": "It's sunny today, 25 degrees Celsius, good for going out.",
       "session_id": "xiaozhi-user-123-esp32-001-1737264000000"
     }
   }

9. xiaozhi receives the response and performs TTS (if needed)
```

### 5.2 Streaming Reply Flow (optional; must be explicitly enabled by xiaozhi)

```
1. xiaozhi sends message with the stream switch
   {
     "id": "msg-001",
     "type": "message",
     "payload": {
       "content": "Run a long-running task",
       "metadata": { "stream": true }
     }
   }

2. OpenClaw sends response (may be multiple chunks)
   {
     "id": "resp-001",
     "type": "response",
     "correlation_id": "msg-001",
     "payload": {
       "content": "I'm working on the task, please wait.",
       "session_id": "xiaozhi-user-123-esp32-001-1737264000000",
       "metadata": { "stream_id": "stream-001", "seq": 1, "done": false, "phase": "chunk" }
     }
   }

   ... (more response frames may be sent in between)

   {
     "id": "resp-003",
     "type": "response",
     "correlation_id": "msg-001",
     "payload": {
       "content": "",
       "session_id": "xiaozhi-user-123-esp32-001-1737264000000",
       "metadata": { "stream_id": "stream-001", "seq": 3, "done": true, "phase": "final", "reason": "complete" }
     }
   }

9. xiaozhi receives the response
   - Chunks with `done=false` may be sent to TTS (if needed)
   - Wait for `done=true` to finish the current reply round
   - Send to the ESP32 device for playback
```

### 5.3 Heartbeat Flow

```
1. Every 30 seconds, OpenClaw sends ping
   { "type": "ping", "payload": { "seq": 1 } }

2. xiaozhi replies with pong within 10 seconds
   { "type": "pong", "correlation_id": "<ping-id>", "payload": { "seq": 1 } }
```

### 5.4 Error Handling Flow

```
1. xiaozhi receives an invalid message

2. It sends error
   {
     "type": "error",
     "correlation_id": "<invalid-msg-id>",
     "payload": {
       "code": "INVALID_MESSAGE",
       "message": "Missing required field: type"
     }
   }

3. OpenClaw receives error, logs it, and continues
```

## 6. Security Considerations

### 6.1 Token Validation

- xiaozhi-esp32-server-golang must validate the token signature
- If an `exp` field exists, validate the expiration time
- Extract `user_id` and `agent_id` from the token (default agent); if business rules allow, `message.metadata.openclaw_agent_id` may override and bind the agent

### 6.2 Rate Limiting

Recommended in xiaozhi-esp32-server-golang:

- Per-connection message rate limit (e.g. 10 messages per second)
- Per-user global rate limit

### 6.3 Connection Limits

- At most 1 active connection per user (one-to-one)
- Only one connection per device ID

## 7. Implementation Recommendations

### 7.1 xiaozhi-esp32-server-golang Side

```go
// WebSocket handler example
func (s *Server) handleOpenClawWS(c *gin.Context) {
    // 1. Get and validate the token
    token := c.Query("token")
    claims, err := s.validateToken(token)
    if err != nil {
        c.JSON(401, gin.H{"error": "unauthorized"})
        return
    }

    // 2. Upgrade to WebSocket
    conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        log.Error("WebSocket upgrade failed", err)
        return
    }
    defer conn.Close()

    // 3. Send handshake_ack immediately
    handshakeAck := WSMessage{
        ID:        generateUUID(),
        Timestamp: time.Now().UnixMilli(),
        Type:      "handshake_ack",
        Payload: map[string]interface{}{
            "version": "1.0.0",
            "server":  "xiaozhi-esp32-server",
        },
    }
    sendMessage(conn, handshakeAck)

    // 4. Start the message loop
    for {
        var msg WSMessage
        if err := conn.ReadJSON(&msg); err != nil {
            log.Error("Read error", err)
            break
        }

        switch msg.Type {
        case "handshake":
            // Record handshake information
        case "ping":
            sendPong(conn, msg)
        case "response":
            // Handle AI response chunks; read payload.metadata.done to determine whether the stream has ended
            s.handleResponse(claims.DeviceID, msg.Payload)
        default:
            log.Warn("Unknown message type", msg.Type)
        }
    }
}
```

### 7.2 OpenClaw Gateway Side

See the OpenClaw Channel implementation code.

## 8. Appendix

### 8.1 WebSocket Subprotocol

No subprotocol is used; plain-text JSON messages are used.

### 8.2 Error Code Reference

See RFC 6455 WebSocket close codes:

| Code | Description |
|----|------|
| 1000 | Normal closure |
| 1001 | Endpoint going away |
| 1002 | Protocol error |
| 1003 | Unsupported data type |
| 1006 | Abnormal closure |
| 1011 | Internal error |

### 8.3 Test Cases

See the OpenClaw Channel test files.

## 9. Version History

| Version | Date | Changes |
|------|------|------|
| 1.4.0 | 2026-03-27 | Clearly distinguish streaming delta chunks from full-sentence snapshot chunks; add the `phase=snapshot` / `content_type` convention |
| 1.3.1 | 2026-03-07 | Add receiver-side parsing recommendations for streaming `response` (chunk assembly, done termination, seq deduplication) |
| 1.3.0 | 2026-03-06 | Support customizing the OpenClaw agent via metadata and binding/unbinding per device |
| 1.2.0 | 2026-03-05 | Default to non-streaming; xiaozhi explicitly controls whether streaming is enabled via message.metadata |
| 1.1.0 | 2026-03-05 | Add the response streaming chunk and done end-marker convention |
| 1.0.0 | 2026-02-28 | Initial version |
