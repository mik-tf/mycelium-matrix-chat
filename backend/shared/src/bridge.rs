use std::time::SystemTime;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::time::{timeout, Duration};

use crate::config::BridgeConfig;
use crate::error::{BridgeError, Result};
use crate::types::*;

pub struct MatrixMyceliumBridge {
    pub config: BridgeConfig,
    matrix_client: reqwest::Client,
    mycelium_client: Option<reqwest::Client>,
    server_discovery: Arc<Mutex<std::collections::HashMap<String, FederationRoute>>>,
}

impl MatrixMyceliumBridge {
    pub async fn new(config: BridgeConfig) -> Result<Self> {
        let matrix_client = reqwest::Client::builder()
            .timeout(Duration::from_secs(config.federation_timeout))
            .build()
            .map_err(|e| BridgeError::Config {
                message: format!("Failed to create Matrix client: {}", e),
            })?;

        let mycelium_client = if config.mycelium_enabled {
            Some(reqwest::Client::builder()
                .timeout(Duration::from_secs(config.federation_timeout))
                .build()
                .map_err(|e| BridgeError::Config {
                    message: format!("Failed to create Mycelium client: {}", e),
                })?)
        } else {
            None
        };

        Ok(Self {
            config,
            matrix_client,
            mycelium_client,
            server_discovery: Arc::new(Mutex::new(std::collections::HashMap::new())),
        })
    }

    pub async fn handle_federation_request(
        &self,
        request: FederationRequest
    ) -> Result<FederationResponse> {
        // Check if we can use Mycelium for this request
        if let Some(destination) = self.extract_server_name(&request.path) {
            if self.should_use_mycelium(&destination).await {
                return self.handle_via_mycelium(request, destination).await;
            }
        }

        // Fall back to standard Matrix federation
        self.handle_via_matrix(request).await
    }

    pub async fn translate_matrix_to_mycelium(&self, event: MatrixEvent) -> Result<MyceliumFederationMessage> {
        let topic = self.determine_mycelium_topic(&event);

        // Find destination servers for this room
        let destinations = self.get_room_servers(&event.room_id).await?;

        // Create message payload
        let payload = serde_json::json!({
            "event_type": event.event_type,
            "room_id": event.room_id,
            "sender": event.sender,
            "origin_server_ts": event.origin_server_ts,
            "content": event.content,
            "state_key": event.state_key
        });

        Ok(MyceliumFederationMessage {
            topic,
            room_id: Some(event.room_id),
            sender: event.sender,
            origin_server_ts: event.origin_server_ts,
            payload,
            destination: destinations.first()
                .ok_or_else(|| BridgeError::Federation {
                    message: "No destination servers found".to_string()
                })?
                .to_string(),
        })
    }

    pub async fn translate_mycelium_to_matrix(
        &self,
        mycelium_msg: MyceliumFederationMessage
    ) -> Result<MatrixEvent> {
        let event: MatrixEvent = serde_json::from_value(mycelium_msg.payload)
            .map_err(|e| BridgeError::Serde {
                message: format!("Failed to parse Mycelium message: {}", e)
            })?;

        Ok(event)
    }

    pub async fn get_bridge_status(&self) -> Result<BridgeStatus> {
        let server_discovery = self.server_discovery.lock().await;

        let mycelium_connected = if let Some(client) = &self.mycelium_client {
            if let Some(api_url) = &self.config.mycelium_api_url {
                timeout(
                    Duration::from_secs(5),
                    client.get(format!("{}/health", api_url)).send()
                )
                .await
                .is_ok_and(|res| res.is_ok())
            } else {
                false
            }
        } else {
            false
        };

        Ok(BridgeStatus {
            connected_servers: server_discovery.len() as u32,
            pending_messages: 0, // TODO: implement message queue tracking
            last_sync: SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            mycelium_connected,
        })
    }

    async fn handle_via_mycelium(
        &self,
        request: FederationRequest,
        destination: String
    ) -> Result<FederationResponse> {
        // Get Mycelium route for destination
        let route = self.get_mycelium_route(&destination).await?;

        // Create Mycelium message
        let mycelium_msg = MyceliumMessage {
            topic: format!("matrix.federation.{}", request.method.to_lowercase()),
            payload: serde_json::to_vec(&request)
                .map_err(|e| BridgeError::Serde {
                    message: format!("Failed to serialize request: {}", e)
                })?,
            destination: Some(route.mycelium_key.clone()),
            timeout: self.config.federation_timeout as u32,
        };

        // Send via Mycelium (placeholder - will be implemented when Mycelium client is available)
        tracing::info!(
            "Sending federation request via Mycelium to {}: {} {}",
            destination, request.method, request.path
        );

        // For now, fall back to Matrix
        self.handle_via_matrix(request).await
    }

    async fn handle_via_matrix(&self, request: FederationRequest) -> Result<FederationResponse> {
        // Build Matrix federation URL
        let url = format!("{}{}", self.config.matrix_homeserver_url, request.path);

        // Build request
        let mut req_builder = match request.method.as_str() {
            "GET" => self.matrix_client.get(&url),
            "POST" => self.matrix_client.post(&url),
            "PUT" => self.matrix_client.put(&url),
            "DELETE" => self.matrix_client.delete(&url),
            _ => return Err(BridgeError::InvalidRequest {
                message: format!("Unsupported method: {}", request.method)
            }),
        };

        // Add headers
        for (key, value) in &request.headers {
            req_builder = req_builder.header(key, value);
        }

        // Add body if present
        if let Some(body) = request.body {
            req_builder = req_builder
                .header("Content-Type", "application/json")
                .json(&body);
        }

        // Send request
        let response = req_builder.send().await?;
        let status_code = response.status().as_u16();
        let body: serde_json::Value = response.json().await
            .map_err(|e| BridgeError::MatrixApi {
                message: format!("Failed to parse response: {}", e)
            })?;

        Ok(FederationResponse { status_code, body })
    }

    fn extract_server_name(&self, path: &str) -> Option<String> {
        // Extract server name from federation path
        // Example: /_matrix/federation/v1/send/{txnId} -> extract from headers/query params
        // For now, return None to force Matrix path
        None
    }

    async fn should_use_mycelium(&self, destination: &str) -> bool {
        self.config.mycelium_enabled
            && self.mycelium_client.is_some()
            && self.get_mycelium_route(destination).await.is_ok()
    }

    fn determine_mycelium_topic(&self, event: &MatrixEvent) -> String {
        match event.event_type.as_str() {
            "m.room.member" => "matrix.federation.membership".to_string(),
            "m.room.message" => "matrix.federation.message".to_string(),
            "m.room.name" | "m.room.topic" => "matrix.federation.state".to_string(),
            _ => "matrix.federation.event".to_string(),
        }
    }

    async fn get_room_servers(&self, _room_id: &str) -> Result<Vec<String>> {
        // TODO: Implement room server discovery
        // For now, return empty vector
        Ok(vec![])
    }

    async fn get_mycelium_route(&self, server_name: &str) -> Result<FederationRoute> {
        let discovery = self.server_discovery.lock().await;

        if let Some(route) = discovery.get(server_name) {
            return Ok(route.clone());
        }

        Err(BridgeError::NotFound)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_bridge_creation() {
        let config = BridgeConfig::default();
        let bridge = MatrixMyceliumBridge::new(config).await;

        assert!(bridge.is_ok());
    }

    #[tokio::test]
    async fn test_mycelium_topic_determination() {
        let config = BridgeConfig::default();
        let bridge = MatrixMyceliumBridge::new(config).await.unwrap();

        let message_event = MatrixEvent {
            event_type: "m.room.message".to_string(),
            room_id: "!room:example.com".to_string(),
            sender: "@user:example.com".to_string(),
            origin_server_ts: 1234567890,
            content: serde_json::json!({"body": "test"}),
            state_key: None,
        };

        let topic = bridge.determine_mycelium_topic(&message_event);
        assert_eq!(topic, "matrix.federation.message");

        let membership_event = MatrixEvent {
            event_type: "m.room.member".to_string(),
            room_id: "!room:example.com".to_string(),
            sender: "@user:example.com".to_string(),
            origin_server_ts: 1234567890,
            content: serde_json::json!({"membership": "join"}),
            state_key: Some("@user:example.com".to_string()),
        };

        let topic = bridge.determine_mycelium_topic(&membership_event);
        assert_eq!(topic, "matrix.federation.membership");
    }
}
