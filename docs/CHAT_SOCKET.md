# Chat Socket.IO Protocol (Pack 17)

Real-time booking chat uses **REST for initial history and reconnect recovery**, and **Socket.IO for live delivery**.

## Authentication

Connect with `handshake.auth` only. **Query-string tokens are rejected.**

| Client | Auth payload |
|--------|----------------|
| JWT user (customer, driver, admin) | `auth.token` — Bearer access token |
| Guest | `auth.guestAccessToken` — same value as `X-Guest-Access-Token` REST header |

Server derives role and user identity from the token. Clients must not send sender user ID, role, or participant type in message payloads.

Guest tokens are validated against the **specific booking** on each `chat:join` and send/read operation. A token for booking A cannot join booking B.

## Events

### Client → server

| Event | Payload | Notes |
|-------|---------|--------|
| `chat:join` | `{ bookingNumber }` | Re-validates authorization; joins internal room `chat:{roomId}` |
| `chat:leave` | `{ roomId? }` | Leaves socket room |
| `chat:send` | `{ bookingNumber?, text, clientMessageId }` | Same `ChatService` as REST; ack returns persisted message |
| `chat:read` | `{ bookingNumber?, upToMessageId }` | Marks read up to message ID |

### Server → client

| Event | Payload |
|-------|---------|
| `chat:joined` | `{ room, roomKey }` |
| `chat:message` | `{ bookingNumber, roomId, message }` |
| `chat:read-updated` | `{ bookingNumber, roomId, upToMessageId, unreadCount, participantSocketId }` |
| `chat:error` | `{ code, message }` |

## Idempotency

`clientMessageId` is required on send (max 64 chars). Same sender + room + `clientMessageId` creates one message only. Retries return the existing message with **no duplicate broadcast**.

## Message rules

- Plain text only, trimmed, max 2000 characters
- Persisted and committed before `chat:message` broadcast
- Terminal booking statuses (`COMPLETED`, `CANCELLED`, `NO_SHOW`) are **read-only** for sending

## Driver reassignment

Only the **currently assigned** driver may join and send. Reassigned drivers fail join/send and are removed from the socket room before new message broadcasts.

## REST endpoints

See OpenAPI: `/api/v1/bookings/:bookingNumber/chat` and `/api/v1/admin/chats/*`.

Legacy `/api/v1/chat/*` returns `404 NOT_FOUND` with a deprecation message.
