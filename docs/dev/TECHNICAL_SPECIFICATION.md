# Technical Specification

## 🎯 System Requirements

### Functional Requirements

#### FR-1: Progressive Enhancement
- **FR-1.1**: System MUST detect local Mycelium installation automatically
- **FR-1.2**: System MUST provide identical chat functionality regardless of user setup
- **FR-1.3**: System MUST upgrade connection automatically when Mycelium is available
- **FR-1.4**: System MUST gracefully degrade when Mycelium is unavailable

#### FR-2: Matrix Protocol Compatibility
- **FR-2.1**: System MUST implement Matrix Client-Server API v1.11
- **FR-2.2**: System MUST support Matrix federation via Server-Server API
- **FR-2.3**: System MUST maintain Matrix room state consistency
- **FR-2.4**: System MUST support Matrix end-to-end encryption

#### FR-3: Mycelium Integration
- **FR-3.1**: System MUST use Mycelium overlay for homeserver federation
- **FR-3.2**: System MUST translate Matrix federation events to Mycelium messages
- **FR-3.3**: System MUST provide direct P2P routing for enhanced users
- **FR-3.4**: System MUST handle Mycelium network partitions gracefully

### Non-Functional Requirements

#### NFR-1: Performance
- **NFR-1.1**: Message delivery latency < 200ms for local network
- **NFR-1.2**: Message delivery latency < 1000ms for global network
- **NFR-1.3**: System throughput > 1000 messages/second per homeserver
- **NFR-1.4**: Web application load time < 2 seconds

#### NFR-2: Reliability
- **NFR-2.1**: System uptime > 99.5%
- **NFR-2.2**: Message delivery reliability > 99.9%
- **NFR-2.3**: Federation sync reliability > 99.5%
- **NFR-2.4**: Auto-recovery from network partitions < 30 seconds

#### NFR-3: Security
- **NFR-3.1**: All federation traffic MUST be encrypted via Mycelium
- **NFR-3.2**: User authentication MUST use Matrix protocols
- **NFR-3.3**: System MUST prevent message tampering
- **NFR-3.4**: System MUST validate all federation events

## 🔧 Technical Architecture

### Component Specifications

#### Matrix-Mycelium Bridge Service

**Purpose**: Translate between Matrix federation protocol and Mycelium messaging

**Interface**:
```rust
pub struct MatrixMyceliumBridge {
    pub matrix_client: MatrixClient,
    pub mycelium_node: MyceliumNode,
    pub topic_router: TopicRouter,
    pub state_manager: StateManager,
}

impl MatrixMyceliumBridge {
    pub async fn handle_matrix_federation(&self, request: FederationRequest) -> Result<FederationResponse>;
    pub async fn handle_mycelium_message(&self, message: MyceliumMessage) -> Result<()>;
    pub async fn sync_state(&self, room_id: &str) -> Result<()>;
}
```

**Message Topics**:
- `matrix.federation.invite` - Room invitations
- `matrix.federation.join` - Room join requests  
- `matrix.federation.leave` - Room leave events
- `matrix.federation.event` - Room events and messages
- `matrix.federation.state` - Room state synchronization
- `matrix.federation.query` - Query operations

**Message Format**:
```rust
#[derive(Serialize, Deserialize)]
pub struct MatrixFederationMessage {
    pub message_type: String,
    pub room_id: Option<String>,
    pub sender: String,
    pub origin_server_ts: u64,
    pub content: serde_json::Value,
    pub signature: String,
}
```

#### Web Application

**Purpose**: Provide user interface with progressive enhancement

**Technology Stack**:
- Frontend: React/TypeScript or Vue.js/TypeScript
- Build Tool: Vite or Webpack
- State Management: Redux Toolkit or Pinia
- HTTP Client: Axios or Fetch API

**Key Components**:
```typescript
interface MyceliumDetector {
  detectMycelium(): Promise<'available' | 'unavailable'>;
  getMyceliumInfo(): Promise<MyceliumNodeInfo>;
}

interface ConnectionManager {
  connectionType: 'enhanced' | 'standard';
  switchConnection(type: 'enhanced' | 'standard'): Promise<void>;
  getConnectionStatus(): ConnectionStatus;
}

interface MatrixClient {
  login(credentials: LoginCredentials): Promise<LoginResponse>;
  sendMessage(roomId: string, content: MessageContent): Promise<void>;
  joinRoom(roomId: string): Promise<void>;
  syncEvents(): Promise<SyncResponse>;
}
```

**Progressive Enhancement Logic**:
```typescript
class ProgressiveEnhancement {
  async initialize(): Promise<void> {
    const myceliumStatus = await this.detectMycelium();
    
    if (myceliumStatus === 'available') {
      await this.enableEnhancedMode();
    } else {
      await this.enableStandardMode();
    }
  }
  
  private async enableEnhancedMode(): Promise<void> {
    this.connectionManager.setType('enhanced');
    this.matrixClient.setTransport(new MyceliumTransport());
    this.ui.showEnhancedIndicator();
  }
  
  private async enableStandardMode(): Promise<void> {
    this.connectionManager.setType('standard');
    this.matrixClient.setTransport(new HttpsTransport());
    this.ui.showStandardIndicator();
  }
}
```

### Protocol Specifications

#### Matrix Federation over Mycelium

**Event Translation**:
```rust
impl FederationTranslator {
    pub fn matrix_to_mycelium(&self, event: MatrixEvent) -> MyceliumMessage {
        MyceliumMessage {
            topic: format!("matrix.federation.{}", event.event_type),
            payload: serde_json::to_vec(&event).unwrap(),
            destination: self.resolve_destination(&event.room_id),
            timeout: Duration::from_secs(30),
        }
    }
    
    pub fn mycelium_to_matrix(&self, message: MyceliumMessage) -> MatrixEvent {
        serde_json::from_slice(&message.payload).unwrap()
    }
}
```

**Server Discovery**:
```rust
pub struct ServerDiscovery {
    pub known_servers: HashMap<String, PublicKey>,
    pub mycelium_node: MyceliumNode,
}

impl ServerDiscovery {
    pub async fn discover_server(&self, domain: &str) -> Option<PublicKey> {
        // Try cache first
        if let Some(key) = self.known_servers.get(domain) {
            return Some(*key);
        }
        
        // Query network
        let query = ServerDiscoveryQuery { domain: domain.to_string() };
        let response = self.mycelium_node.broadcast_query(
            "matrix.discovery.server",
            &query,
            Duration::from_secs(10)
        ).await?;
        
        response.server_key
    }
}
```

#### API Specifications

**Matrix Client-Server API Extensions**:
```typescript
// Enhanced endpoints for Mycelium users
interface MyceliumEnhancedAPI {
  // Get connection status
  GET /api/v1/mycelium/status
  
  // Switch connection type  
  POST /api/v1/mycelium/connection
  {
    "type": "enhanced" | "standard"
  }
  
  // Get network topology
  GET /api/v1/mycelium/network
  
  // Direct P2P message
  POST /api/v1/mycelium/direct-message
  {
    "target": "mycelium_public_key",
    "content": "message_content"
  }
}
```

**Bridge Management API**:
```rust
// Internal API for bridge management
#[derive(OpenApi)]
struct BridgeAPI;

#[utoipa::path(
    get,
    path = "/bridge/status",
    responses(
        (status = 200, description = "Bridge status", body = BridgeStatus)
    )
)]
async fn get_bridge_status() -> Json<BridgeStatus> {
    // Implementation
}

#[utoipa::path(
    post,
    path = "/bridge/federation/send",
    request_body = FederationMessage,
    responses(
        (status = 200, description = "Message sent successfully")
    )
)]
async fn send_federation_message(message: Json<FederationMessage>) -> StatusCode {
    // Implementation
}
```

### Data Models

#### Core Data Structures

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MyceliumMatrixUser {
    pub matrix_id: String,
    pub mycelium_key: Option<PublicKey>,
    pub connection_type: ConnectionType,
    pub last_seen: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FederationRoute {
    pub destination_server: String,
    pub mycelium_key: PublicKey,
    pub last_successful: DateTime<Utc>,
    pub latency_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MyceliumRoom {
    pub matrix_room_id: String,
    pub participants: Vec<MyceliumMatrixUser>,
    pub federation_servers: Vec<FederationRoute>,
    pub state_hash: String,
}
```

#### Database Schema

```sql
-- User management
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    matrix_id TEXT UNIQUE NOT NULL,
    mycelium_key TEXT,
    connection_type TEXT NOT NULL DEFAULT 'standard',
    created_at TIMESTAMP DEFAULT NOW(),
    last_seen TIMESTAMP
);

-- Federation routing
CREATE TABLE federation_routes (
    id SERIAL PRIMARY KEY,
    destination_server TEXT NOT NULL,
    mycelium_key TEXT NOT NULL,
    last_successful TIMESTAMP,
    latency_ms INTEGER,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Message queue for reliable delivery
CREATE TABLE message_queue (
    id SERIAL PRIMARY KEY,
    topic TEXT NOT NULL,
    payload BYTEA NOT NULL,
    destination_key TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    attempts INTEGER DEFAULT 0,
    next_retry TIMESTAMP,
    status TEXT DEFAULT 'pending'
);
```

### Performance Specifications

#### Caching Strategy

```rust
pub struct FederationCache {
    // Room state caching
    room_states: LruCache<String, RoomState>,
    
    // Server discovery caching  
    server_keys: LruCache<String, PublicKey>,
    
    // Message deduplication
    message_hashes: LruCache<String, ()>,
    
    // User session caching
    user_sessions: LruCache<String, UserSession>,
}

impl FederationCache {
    pub fn get_room_state(&self, room_id: &str) -> Option<RoomState> {
        self.room_states.get(room_id).cloned()
    }
    
    pub fn cache_room_state(&mut self, room_id: String, state: RoomState) {
        self.room_states.put(room_id, state);
    }
}
```

#### Connection Pooling

```rust
pub struct MyceliumConnectionPool {
    connections: HashMap<PublicKey, MyceliumConnection>,
    max_connections: usize,
    connection_timeout: Duration,
}

impl MyceliumConnectionPool {
    pub async fn get_connection(&self, key: &PublicKey) -> Result<&MyceliumConnection> {
        if let Some(conn) = self.connections.get(key) {
            if conn.is_healthy().await {
                return Ok(conn);
            }
        }
        
        self.create_connection(key).await
    }
}
```

## 🔒 Security Specifications

### Encryption Requirements

1. **Transport Layer**: All Mycelium overlay traffic encrypted with x25519 keys
2. **Application Layer**: Matrix E2EE for user messages
3. **Federation Layer**: Message signing for federation events
4. **Storage Layer**: Encrypted storage for sensitive configuration

### Authentication Flow

```rust
pub struct AuthenticationFlow {
    pub matrix_auth: MatrixAuthenticator,
    pub mycelium_identity: MyceliumIdentityManager,
}

impl AuthenticationFlow {
    pub async fn authenticate_user(&self, credentials: LoginCredentials) -> Result<UserSession> {
        // Matrix authentication
        let matrix_session = self.matrix_auth.login(&credentials).await?;
        
        // Link Mycelium identity if available
        let mycelium_identity = self.mycelium_identity.get_or_create_identity().await?;
        
        Ok(UserSession {
            matrix_session,
            mycelium_identity,
            connection_type: self.detect_connection_type().await,
        })
    }
}
```

### Message Validation

```rust
pub struct MessageValidator {
    pub signature_verifier: SignatureVerifier,
    pub rate_limiter: RateLimiter,
    pub content_filter: ContentFilter,
}

impl MessageValidator {
    pub fn validate_federation_message(&self, message: &FederationMessage) -> Result<()> {
        // Verify message signature
        self.signature_verifier.verify(&message.signature, &message.content)?;
        
        // Check rate limits
        self.rate_limiter.check_rate(&message.sender)?;
        
        // Content filtering
        self.content_filter.validate(&message.content)?;
        
        Ok(())
    }
}
```

This technical specification provides the detailed implementation requirements for building the Mycelium-Matrix integration system.