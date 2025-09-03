# API Specification

## 🎯 Overview

This document defines the complete API specification for the Mycelium-Matrix integration, including internal service APIs, client-facing endpoints, and Matrix protocol extensions.

## 📋 API Categories

1. **Matrix Client-Server API** - Standard Matrix endpoints for client communication
2. **Matrix Server-Server API** - Federation endpoints (enhanced with Mycelium)
3. **Mycelium Enhancement API** - Progressive enhancement detection and control
4. **Bridge Management API** - Internal service management
5. **WebSocket API** - Real-time communication

## 🔗 Base URLs

### Production
- **Web Application**: `https://chat.threefold.pro`
- **Matrix Client API**: `https://chat.threefold.pro/_matrix/client/v3`
- **Matrix Federation API**: `https://chat.threefold.pro/_matrix/federation/v1`
- **Enhancement API**: `https://chat.threefold.pro/api/v1/mycelium`
- **Bridge Management**: `http://localhost:8080/api/v1/bridge` (internal)

### Development
- **Web Application**: `http://localhost:3000`
- **Matrix Client API**: `http://localhost:8008/_matrix/client/v3`
- **Enhancement API**: `http://localhost:3000/api/v1/mycelium`
- **Bridge Management**: `http://localhost:8080/api/v1/bridge`

## 🌐 Matrix Client-Server API

### Authentication

#### Login
```http
POST /_matrix/client/v3/login
Content-Type: application/json

{
  "type": "m.login.password",
  "user": "username",
  "password": "password"
}
```

**Response:**
```json
{
  "user_id": "@username:chat.threefold.pro",
  "access_token": "MDAxOGxvY2F0aW9uIG1hdHJpeC5vcmc",
  "home_server": "chat.threefold.pro",
  "device_id": "GHTYAJCE",
  "well_known": {
    "m.homeserver": {
      "base_url": "https://chat.threefold.pro"
    }
  }
}
```

#### Logout
```http
POST /_matrix/client/v3/logout
Authorization: Bearer MDAxOGxvY2F0aW9uIG1hdHJpeC5vcmc
```

**Response:**
```json
{}
```

### Room Management

#### Create Room
```http
POST /_matrix/client/v3/createRoom
Authorization: Bearer MDAxOGxvY2F0aW9uIG1hdHJpeC5vcmc
Content-Type: application/json

{
  "name": "My Mycelium Room",
  "topic": "Secure chat over Mycelium network",
  "preset": "public_chat",
  "initial_state": [
    {
      "type": "m.room.encryption",
      "content": {
        "algorithm": "m.megolm.v1.aes-sha2"
      }
    }
  ]
}
```

**Response:**
```json
{
  "room_id": "!room123:chat.threefold.pro"
}
```

#### Join Room
```http
POST /_matrix/client/v3/rooms/{roomId}/join
Authorization: Bearer MDAxOGxvY2F0aW9uIG1hdHJpeC5vcmc
```

#### Send Message
```http
PUT /_matrix/client/v3/rooms/{roomId}/send/m.room.message/{txnId}
Authorization: Bearer MDAxOGxvY2F0aW9uIG1hdHJpeC5vcmc
Content-Type: application/json

{
  "msgtype": "m.text",
  "body": "Hello from Mycelium network!",
  "format": "org.matrix.custom.html",
  "formatted_body": "<p>Hello from <strong>Mycelium</strong> network!</p>"
}
```

**Response:**
```json
{
  "event_id": "$event123:chat.threefold.pro"
}
```

### Sync and Events

#### Sync
```http
GET /_matrix/client/v3/sync?since={token}&timeout=30000
Authorization: Bearer MDAxOGxvY2F0aW9uIG1hdHJpeC5vcmc
```

**Response:**
```json
{
  "next_batch": "s123_456_789",
  "rooms": {
    "join": {
      "!room123:chat.threefold.pro": {
        "timeline": {
          "events": [
            {
              "type": "m.room.message",
              "content": {
                "msgtype": "m.text",
                "body": "Hello!"
              },
              "sender": "@user:chat.threefold.pro",
              "origin_server_ts": 1234567890,
              "event_id": "$event123:chat.threefold.pro",
              "unsigned": {
                "mycelium_routed": true,
                "mycelium_latency_ms": 45
              }
            }
          ]
        }
      }
    }
  }
}
```

## 🚀 Mycelium Enhancement API

### Connection Detection

#### Check Mycelium Availability
```http
GET /api/v1/mycelium/detect
```

**Response:**
```json
{
  "available": true,
  "version": "0.6.1",
  "public_key": "abd16194646defe7ad2318a0f0a69eb2e3fe939c3b0b51cf0bb88bb8028ecd1d",
  "address": "5c4:c176:bf44:b2ab:5e7e:f6a:b7e2:11ca",
  "api_url": "http://localhost:8989",
  "network_status": "connected"
}
```

#### Get Connection Status
```http
GET /api/v1/mycelium/status
Authorization: Bearer MDAxOGxvY2F0aW9uIG1hdHJpeC5vcmc
```

**Response:**
```json
{
  "connection_type": "enhanced",
  "quality": "excellent",
  "latency_ms": 45,
  "throughput_mbps": 12.5,
  "peers_connected": 8,
  "mycelium_network": {
    "overlay_ip": "5c4:c176:bf44:b2ab:5e7e:f6a:b7e2:11ca",
    "public_key": "abd16194646defe7ad2318a0f0a69eb2e3fe939c3b0b51cf0bb88bb8028ecd1d",
    "routing_table_size": 142,
    "message_queue_size": 0
  }
}
```

### Connection Management

#### Switch Connection Type
```http
POST /api/v1/mycelium/connection
Authorization: Bearer MDAxOGxvY2F0aW9uIG1hdHJpeC5vcmc
Content-Type: application/json

{
  "type": "enhanced",
  "prefer_direct_routing": true
}
```

**Response:**
```json
{
  "success": true,
  "new_connection_type": "enhanced",
  "switch_time_ms": 1250,
  "message": "Successfully switched to enhanced P2P mode"
}
```

### Network Information

#### Get Network Topology
```http
GET /api/v1/mycelium/network
Authorization: Bearer MDAxOGxvY2F0aW9uIG1hdHJpeC5vcmc
```

**Response:**
```json
{
  "local_node": {
    "public_key": "abd16194646defe7ad2318a0f0a69eb2e3fe939c3b0b51cf0bb88bb8028ecd1d",
    "overlay_ip": "5c4:c176:bf44:b2ab:5e7e:f6a:b7e2:11ca",
    "listen_port": 9651
  },
  "connected_peers": [
    {
      "public_key": "bb39b4a3a4efd70f3e05e37887677e02efbda14681d0acd3882bc0f754792c32",
      "overlay_ip": "2e4:9ace:9252:630:beee:e405:74c0:d876",
      "endpoint": "tcp://192.168.1.100:9651",
      "latency_ms": 12,
      "last_seen": "2024-01-01T12:00:00Z"
    }
  ],
  "known_homeservers": [
    {
      "domain": "other.mycelium.com",
      "public_key": "cc48c5b4b5efd70f3e05e37887677e02efbda14681d0acd3882bc0f754792c43",
      "overlay_ip": "3f5:a9ce:9252:630:beee:e405:74c0:d877",
      "federation_status": "active"
    }
  ]
}
```

### Direct P2P Messaging

#### Send Direct Message
```http
POST /api/v1/mycelium/direct-message
Authorization: Bearer MDAxOGxvY2F0aW9uIG1hdHJpeC5vcmc
Content-Type: application/json

{
  "target_public_key": "bb39b4a3a4efd70f3e05e37887677e02efbda14681d0acd3882bc0f754792c32",
  "message_type": "chat",
  "content": {
    "body": "Direct P2P message via Mycelium",
    "encrypted": true
  },
  "timeout_ms": 30000
}
```

**Response:**
```json
{
  "message_id": "msg_12345",
  "status": "delivered",
  "delivery_time_ms": 234,
  "route": "direct_p2p"
}
```

## 🔧 Bridge Management API

### Bridge Status

#### Get Bridge Health
```http
GET /api/v1/bridge/health
```

**Response:**
```json
{
  "status": "healthy",
  "uptime_seconds": 86400,
  "version": "0.1.0",
  "components": {
    "matrix_connection": "healthy",
    "mycelium_connection": "healthy",
    "database": "healthy",
    "redis": "healthy"
  },
  "metrics": {
    "messages_processed": 15420,
    "federation_events": 3240,
    "active_connections": 45,
    "error_rate": 0.002
  }
}
```

#### Get Bridge Statistics
```http
GET /api/v1/bridge/stats
Authorization: Bearer internal_api_key
```

**Response:**
```json
{
  "federation": {
    "messages_sent": 8520,
    "messages_received": 6900,
    "average_latency_ms": 145,
    "success_rate": 0.998,
    "active_federations": 12
  },
  "mycelium": {
    "overlay_messages": 15420,
    "direct_p2p_messages": 340,
    "network_peers": 28,
    "routing_efficiency": 0.87
  },
  "performance": {
    "cpu_usage_percent": 15.2,
    "memory_usage_mb": 256,
    "message_queue_size": 12,
    "processing_time_ms": {
      "p50": 45,
      "p95": 180,
      "p99": 450
    }
  }
}
```

### Federation Management

#### Send Federation Message
```http
POST /api/v1/bridge/federation/send
Authorization: Bearer internal_api_key
Content-Type: application/json

{
  "destination_server": "other.mycelium.com",
  "message_type": "matrix.federation.event",
  "content": {
    "type": "m.room.message",
    "room_id": "!room123:chat.threefold.pro",
    "sender": "@user:chat.threefold.pro",
    "content": {
      "msgtype": "m.text",
      "body": "Federation message"
    }
  },
  "timeout_ms": 30000
}
```

**Response:**
```json
{
  "message_id": "fed_msg_12345",
  "status": "sent",
  "destination_key": "cc48c5b4b5efd70f3e05e37887677e02efbda14681d0acd3882bc0f754792c43",
  "route": "mycelium_overlay",
  "send_time_ms": 123
}
```

#### Get Federation Routes
```http
GET /api/v1/bridge/federation/routes
Authorization: Bearer internal_api_key
```

**Response:**
```json
{
  "routes": [
    {
      "destination_server": "other.mycelium.com",
      "mycelium_key": "cc48c5b4b5efd70f3e05e37887677e02efbda14681d0acd3882bc0f754792c43",
      "overlay_ip": "3f5:a9ce:9252:630:beee:e405:74c0:d877",
      "status": "active",
      "latency_ms": 89,
      "success_rate": 0.995,
      "last_contact": "2024-01-01T12:00:00Z"
    }
  ]
}
```

### Room State Management

#### Get Room State
```http
GET /api/v1/bridge/rooms/{roomId}/state
Authorization: Bearer internal_api_key
```

**Response:**
```json
{
  "room_id": "!room123:chat.threefold.pro",
  "state_hash": "sha256:abc123...",
  "last_updated": "2024-01-01T12:00:00Z",
  "federation_servers": [
    "other.mycelium.com",
    "third.mycelium.com"
  ],
  "sync_status": {
    "other.mycelium.com": "synced",
    "third.mycelium.com": "pending"
  },
  "events_count": 1450,
  "members_count": 8
}
```

#### Force State Sync
```http
POST /api/v1/bridge/rooms/{roomId}/sync
Authorization: Bearer internal_api_key
Content-Type: application/json

{
  "target_servers": ["other.mycelium.com"],
  "full_sync": false
}
```

## 🔌 WebSocket API

### Real-time Events

#### Connection
```javascript
// Client-side WebSocket connection
const ws = new WebSocket('wss://chat.threefold.pro/api/v1/ws');

// Authentication after connection
ws.send(JSON.stringify({
  type: 'auth',
  token: 'MDAxOGxvY2F0aW9uIG1hdHJpeC5vcmc'
}));
```

#### Event Types

**Connection Status Updates:**
```json
{
  "type": "connection_status",
  "data": {
    "connection_type": "enhanced",
    "quality": "good",
    "latency_ms": 67,
    "timestamp": "2024-01-01T12:00:00Z"
  }
}
```

**Real-time Messages:**
```json
{
  "type": "matrix_event",
  "data": {
    "room_id": "!room123:chat.threefold.pro",
    "event": {
      "type": "m.room.message",
      "content": {
        "msgtype": "m.text",
        "body": "Real-time message"
      },
      "sender": "@user:chat.threefold.pro",
      "event_id": "$event123:chat.threefold.pro"
    }
  }
}
```

**Network Topology Changes:**
```json
{
  "type": "network_update",
  "data": {
    "event": "peer_connected",
    "peer": {
      "public_key": "new_peer_key",
      "overlay_ip": "4a6:b8df:3456:789:abcd:ef01:2345:6789"
    },
    "network_size": 156
  }
}
```

## 📊 Error Handling

### Error Response Format

All APIs use consistent error formatting:

```json
{
  "error": {
    "code": "M_NOT_FOUND",
    "message": "Room not found",
    "details": {
      "room_id": "!nonexistent:chat.threefold.pro",
      "suggestion": "Check the room ID and try again"
    }
  },
  "timestamp": "2024-01-01T12:00:00Z",
  "request_id": "req_12345"
}
```

### Error Codes

#### Matrix Standard Errors
- `M_FORBIDDEN` - Access denied
- `M_NOT_FOUND` - Resource not found
- `M_BAD_JSON` - Invalid JSON in request
- `M_UNKNOWN_TOKEN` - Invalid access token
- `M_LIMIT_EXCEEDED` - Rate limit exceeded

#### Mycelium-Specific Errors
- `MYCELIUM_UNAVAILABLE` - Mycelium node not accessible
- `MYCELIUM_NETWORK_ERROR` - Network connectivity issues
- `MYCELIUM_TIMEOUT` - Operation timed out
- `MYCELIUM_PEER_UNREACHABLE` - Target peer not reachable
- `BRIDGE_ERROR` - Internal bridge service error

#### Federation Errors
- `FEDERATION_FAILED` - Federation message delivery failed
- `FEDERATION_TIMEOUT` - Federation operation timed out
- `FEDERATION_UNAUTHORIZED` - Federation not authorized
- `STATE_SYNC_ERROR` - Room state synchronization failed

## 🔐 Authentication & Authorization

### Access Token Format

Access tokens are JWT tokens with the following structure:

```json
{
  "header": {
    "alg": "HS256",
    "typ": "JWT"
  },
  "payload": {
    "user_id": "@username:chat.threefold.pro",
    "device_id": "DEVICEID",
    "iat": 1234567890,
    "exp": 1234571490,
    "scope": ["matrix:client", "mycelium:enhanced"]
  }
}
```

### API Key Authentication

Internal APIs use API key authentication:

```http
Authorization: Bearer internal_api_key_here
```

### Rate Limiting

Rate limits are applied per user/IP:

- **Matrix Client API**: 100 requests/minute
- **Enhancement API**: 60 requests/minute  
- **WebSocket connections**: 10 connections per user
- **Federation API**: 1000 requests/minute per server

Rate limit headers:
```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1234567890
```

## 📈 Monitoring & Metrics

### Prometheus Metrics Endpoints

#### Bridge Metrics
```http
GET /api/v1/bridge/metrics
```

**Response (Prometheus format):**
```
# HELP messages_sent_total Total messages sent via federation
# TYPE messages_sent_total counter
messages_sent_total{destination="other.mycelium.com"} 1234

# HELP federation_latency_seconds Federation message latency
# TYPE federation_latency_seconds histogram
federation_latency_seconds_bucket{le="0.1"} 100
federation_latency_seconds_bucket{le="0.5"} 450
federation_latency_seconds_bucket{le="1.0"} 800
federation_latency_seconds_bucket{le="+Inf"} 1000

# HELP active_connections Current active connections
# TYPE active_connections gauge
active_connections 45
```

### Health Check Endpoints

#### Comprehensive Health Check
```http
GET /api/v1/health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00Z",
  "checks": {
    "database": {
      "status": "healthy",
      "latency_ms": 5,
      "details": "Connection pool: 8/10 active"
    },
    "redis": {
      "status": "healthy",
      "latency_ms": 2
    },
    "mycelium": {
      "status": "healthy",
      "network_peers": 28,
      "overlay_connected": true
    },
    "matrix_federation": {
      "status": "healthy",
      "active_federations": 12,
      "avg_latency_ms": 145
    }
  }
}
```

This comprehensive API specification provides all the endpoints and data formats needed to implement and integrate with the Mycelium-Matrix system.