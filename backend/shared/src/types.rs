use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatrixEvent {
    pub event_id: String,
    pub event_type: String,
    pub room_id: String,
    pub sender: String,
    pub origin_server_ts: u64,
    pub content: serde_json::Value,
    #[serde(default)]
    pub state_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MyceliumMessage {
    pub topic: String,
    pub payload: Vec<u8>,
    pub destination: Option<String>, // Public key for Mycelium
    pub timeout: u32, // seconds
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatrixFederationMessage {
    pub message_type: String,
    pub room_id: Option<String>,
    pub sender: String,
    pub origin_server_ts: u64,
    pub content: serde_json::Value,
    pub signature: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MyceliumFederationMessage {
    pub topic: String,
    pub room_id: Option<String>,
    pub sender: String,
    pub origin_server_ts: u64,
    pub payload: serde_json::Value,
    pub destination: String, // Mycelium public key
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserSession {
    pub matrix_id: String,
    pub mycelium_public_key: Option<String>,
    pub connection_type: ConnectionType,
    pub access_token: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ConnectionType {
    Standard,
    Enhanced,
    Offline,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FederationRoute {
    pub destination_server: String,
    pub mycelium_key: String,
    pub last_successful: i64, // timestamp
    pub latency_ms: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomState {
    pub room_id: String,
    pub state_events: Vec<MatrixEvent>,
    pub members: Vec<String>,
    pub is_external: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeStatus {
    pub connected_servers: u32,
    pub pending_messages: u32,
    pub last_sync: i64,
    pub mycelium_connected: bool,
}

impl Default for BridgeStatus {
    fn default() -> Self {
        Self {
            connected_servers: 0,
            pending_messages: 0,
            last_sync: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64,
            mycelium_connected: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FederationRequest {
    pub method: String,
    pub path: String,
    pub body: Option<serde_json::Value>,
    pub headers: std::collections::HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FederationResponse {
    pub status_code: u16,
    pub body: serde_json::Value,
}
