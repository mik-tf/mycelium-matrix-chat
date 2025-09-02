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
    pending_messages: Arc<Mutex<std::collections::HashMap<String, tokio::sync::oneshot::Sender<FederationResponse>>>>,
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
            pending_messages: Arc::new(Mutex::new(std::collections::HashMap::new())),
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

    pub async fn test_federation_connection(
        &self,
        server_name: &str,
        test_request: FederationRequest
    ) -> Result<(FederationResponse, String, u128)> {
        let start_time = std::time::Instant::now();

        // Check if we can use Mycelium for this request
        let routing_method = if self.should_use_mycelium(server_name).await {
            "mycelium"
        } else {
            "matrix"
        };

        let result = if routing_method == "mycelium" {
            self.handle_via_mycelium(test_request, server_name.to_string()).await
        } else {
            self.handle_via_matrix(test_request).await
        };

        let duration = start_time.elapsed().as_millis();

        match result {
            Ok(response) => Ok((response, routing_method.to_string(), duration)),
            Err(e) => Err(e)
        }
    }

    pub async fn translate_matrix_to_mycelium(&self, event: MatrixEvent) -> Result<MyceliumFederationMessage> {
        let topic = self.determine_mycelium_topic(&event);

        // Find destination servers for this room
        let destinations = self.get_room_servers(&event.room_id).await?;

        // Create comprehensive message payload with all Matrix event fields
        let mut payload = serde_json::json!({
            "event_id": event.event_id,
            "event_type": event.event_type,
            "room_id": event.room_id,
            "sender": event.sender,
            "origin_server_ts": event.origin_server_ts,
            "content": event.content
        });

        // Add state_key if present (for state events)
        if let Some(state_key) = event.state_key {
            payload["state_key"] = serde_json::Value::String(state_key);
        }

        // Add additional metadata for federation
        payload["federation_version"] = serde_json::json!("v1");
        payload["origin_server"] = serde_json::json!(self.extract_server_from_user_id(&event.sender));

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
        // Extract the Matrix event from the Mycelium payload
        let event_id = mycelium_msg.payload.get("event_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| BridgeError::Serde {
                message: "Missing event_id in Mycelium message".to_string()
            })?
            .to_string();

        let event_type = mycelium_msg.payload.get("event_type")
            .and_then(|v| v.as_str())
            .ok_or_else(|| BridgeError::Serde {
                message: "Missing event_type in Mycelium message".to_string()
            })?
            .to_string();

        let room_id = mycelium_msg.payload.get("room_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| BridgeError::Serde {
                message: "Missing room_id in Mycelium message".to_string()
            })?
            .to_string();

        let sender = mycelium_msg.payload.get("sender")
            .and_then(|v| v.as_str())
            .ok_or_else(|| BridgeError::Serde {
                message: "Missing sender in Mycelium message".to_string()
            })?
            .to_string();

        let origin_server_ts = mycelium_msg.payload.get("origin_server_ts")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| BridgeError::Serde {
                message: "Missing or invalid origin_server_ts in Mycelium message".to_string()
            })?;

        let content = mycelium_msg.payload.get("content")
            .ok_or_else(|| BridgeError::Serde {
                message: "Missing content in Mycelium message".to_string()
            })?
            .clone();

        // Extract optional state_key
        let state_key = mycelium_msg.payload.get("state_key")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        // Validate the event structure
        if !self.validate_matrix_event(&event_type, &content) {
            return Err(BridgeError::Serde {
                message: format!("Invalid Matrix event structure for type: {}", event_type)
            });
        }

        Ok(MatrixEvent {
            event_id,
            event_type,
            room_id,
            sender,
            origin_server_ts,
            content,
            state_key,
        })
    }

    fn validate_matrix_event(&self, event_type: &str, content: &serde_json::Value) -> bool {
        // Basic validation for common Matrix event types
        match event_type {
            "m.room.message" => {
                content.get("body").is_some() || content.get("msgtype").is_some()
            },
            "m.room.member" => {
                content.get("membership").and_then(|v| v.as_str()).is_some()
            },
            "m.room.name" => {
                content.get("name").and_then(|v| v.as_str()).is_some()
            },
            "m.room.topic" => {
                content.get("topic").and_then(|v| v.as_str()).is_some()
            },
            _ => true, // Allow other event types for now
        }
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

        let pending_count = {
            let pending = self.pending_messages.lock().await;
            pending.len() as u32
        };

        Ok(BridgeStatus {
            connected_servers: server_discovery.len() as u32,
            pending_messages: pending_count,
            last_sync: SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64,
            mycelium_connected,
        })
    }

    pub async fn handle_via_mycelium(
        &self,
        request: FederationRequest,
        destination: String
    ) -> Result<FederationResponse> {
        // Get Mycelium route for destination
        let route = self.get_mycelium_route(&destination).await?;

        // Create unique message ID for tracking
        let message_id = format!("{}_{}", uuid::Uuid::new_v4(), std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis());

        // Create Mycelium message payload with request tracking
        let message_payload = serde_json::json!({
            "message_id": message_id,
            "method": request.method,
            "path": request.path,
            "body": request.body,
            "headers": request.headers,
            "timestamp": std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs()
        });

        // Send via Mycelium HTTP API
        if let Some(mycelium_url) = &self.config.mycelium_api_url {
            let client = self.mycelium_client.as_ref()
                .ok_or_else(|| BridgeError::Config {
                    message: "Mycelium client not configured".to_string()
                })?;

            // Get the destination node's public key
            let dest_pubkey = self.get_destination_pubkey(&destination, &route.mycelium_key, client, mycelium_url).await?;

            // Create response channel for async response handling
            let (response_tx, response_rx) = tokio::sync::oneshot::channel();

            // Store the response channel
            {
                let mut pending = self.pending_messages.lock().await;
                pending.insert(message_id.clone(), response_tx);
            }

            // Create the message to send via Mycelium
            let mycelium_request = serde_json::json!({
                "dst": { "pk": dest_pubkey },
                "topic": format!("matrix.federation.{}", request.method.to_lowercase()).into_bytes(),
                "payload": message_payload.to_string().into_bytes()
            });

            let response = client
                .post(format!("{}/api/v1/messages", mycelium_url))
                .json(&mycelium_request)
                .send()
                .await
                .map_err(|e| BridgeError::MyceliumApi {
                    message: format!("Failed to send via Mycelium: {}", e)
                })?;

            if response.status().is_success() {
                tracing::info!(
                    "Successfully sent federation request via Mycelium to {}: {} {} (ID: {})",
                    destination, request.method, request.path, message_id
                );

                // Wait for response with timeout
                match tokio::time::timeout(
                    Duration::from_secs(self.config.federation_timeout),
                    response_rx
                ).await {
                    Ok(Ok(federation_response)) => {
                        tracing::info!("Received Mycelium response for message {}", message_id);
                        return Ok(federation_response);
                    },
                    Ok(Err(_)) => {
                        tracing::warn!("Response channel closed for message {}", message_id);
                    },
                    Err(_) => {
                        tracing::warn!("Timeout waiting for Mycelium response for message {}", message_id);
                    }
                }

                // Clean up pending message
                {
                    let mut pending = self.pending_messages.lock().await;
                    pending.remove(&message_id);
                }

                // Return success status even if we didn't get a response
                return Ok(FederationResponse {
                    status_code: 200,
                    body: serde_json::json!({
                        "status": "sent_via_mycelium",
                        "message_id": message_id
                    })
                });
            } else {
                // Clean up on failure
                {
                    let mut pending = self.pending_messages.lock().await;
                    pending.remove(&message_id);
                }

                tracing::warn!(
                    "Mycelium message send failed with status {}, falling back to Matrix",
                    response.status()
                );
            }
        }

        // Fall back to standard Matrix federation
        self.handle_via_matrix(request).await
    }

    pub async fn handle_via_matrix(&self, request: FederationRequest) -> Result<FederationResponse> {
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
        // Matrix federation paths typically include destination server info in query params or headers
        // For now, we'll look for common patterns

        // Check if this is a federation request with destination info
        if path.starts_with("/_matrix/federation/") {
            // In a real implementation, we'd extract from:
            // - Query parameters (?destination=server.com)
            // - Request headers (Destination: server.com)
            // - Path segments for some endpoints

            // For now, return None to allow fallback logic to work
            // This will be enhanced when we have proper request parsing
            None
        } else {
            None
        }
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
            "m.room.name" | "m.room.topic" | "m.room.avatar" => "matrix.federation.state".to_string(),
            "m.room.power_levels" | "m.room.join_rules" => "matrix.federation.state".to_string(),
            "m.room.redaction" => "matrix.federation.redaction".to_string(),
            "m.room.encrypted" => "matrix.federation.encrypted".to_string(),
            _ => "matrix.federation.event".to_string(),
        }
    }

    fn extract_server_from_user_id(&self, user_id: &str) -> String {
        // Matrix user IDs are in format @user:server.com
        if let Some(server_part) = user_id.split(':').nth(1) {
            server_part.to_string()
        } else {
            "unknown".to_string()
        }
    }

    async fn get_room_servers(&self, room_id: &str) -> Result<Vec<String>> {
        // Extract server names from room ID
        // Matrix room IDs are in format !room:server.com
        if let Some(server_part) = room_id.split(':').nth(1) {
            // For now, return the server from the room ID
            // In a full implementation, this would query the database
            // for all servers that have users in this room
            Ok(vec![server_part.to_string()])
        } else {
            Err(BridgeError::InvalidRequest {
                message: format!("Invalid room ID format: {}", room_id)
            })
        }
    }

    pub async fn add_federation_route(&self, server_name: String, mycelium_key: String) -> Result<()> {
        let mut discovery = self.server_discovery.lock().await;
        let route = FederationRoute {
            destination_server: server_name.clone(),
            mycelium_key,
            last_successful: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64,
            latency_ms: 0, // Will be updated on successful communication
        };
        discovery.insert(server_name, route);
        Ok(())
    }

    pub async fn get_all_federation_routes(&self) -> Vec<FederationRoute> {
        let discovery = self.server_discovery.lock().await;
        discovery.values().cloned().collect()
    }

    pub async fn remove_federation_route(&self, server_name: &str) -> Result<()> {
        let mut discovery = self.server_discovery.lock().await;
        if discovery.remove(server_name).is_some() {
            Ok(())
        } else {
            Err(BridgeError::NotFound)
        }
    }

    async fn get_mycelium_route(&self, server_name: &str) -> Result<FederationRoute> {
        let discovery = self.server_discovery.lock().await;

        if let Some(route) = discovery.get(server_name) {
            return Ok(route.clone());
        }

        Err(BridgeError::NotFound)
    }

    async fn get_destination_pubkey(
        &self,
        destination: &str,
        mycelium_key: &str,
        client: &reqwest::Client,
        mycelium_url: &str
    ) -> Result<String> {
        // If we already have a public key, use it
        if mycelium_key.starts_with("0x") || mycelium_key.len() == 64 {
            return Ok(mycelium_key.to_string());
        }

        // Try to get the public key from Mycelium API
        // For now, we'll use a placeholder - in a real implementation,
        // we'd need a way to resolve server names to public keys
        // This could be done via DNS, a distributed registry, or configuration

        // Placeholder: return the mycelium_key as-is for now
        // In production, this would need proper key resolution
        tracing::warn!("Using placeholder public key resolution for {}", destination);
        Ok(mycelium_key.to_string())
    }

    pub async fn handle_incoming_mycelium_message(&self, mycelium_msg: MyceliumFederationMessage) -> Result<()> {
        tracing::info!("Received incoming Mycelium message: {}", mycelium_msg.topic);

        // Check if this is a response to a pending request
        if let Some(message_id) = mycelium_msg.payload.get("message_id").and_then(|v| v.as_str()) {
            let mut pending = self.pending_messages.lock().await;
            if let Some(response_tx) = pending.remove(message_id) {
                // This is a response to a pending request
                let federation_response = FederationResponse {
                    status_code: 200, // Assume success for now
                    body: mycelium_msg.payload.get("response_body")
                        .unwrap_or(&serde_json::json!({ "status": "received_via_mycelium" }))
                        .clone(),
                };

                // Send response back to waiting request handler
                let _ = response_tx.send(federation_response);
                tracing::info!("Delivered Mycelium response for message {}", message_id);
                return Ok(());
            }
        }

        // Handle incoming federation requests
        if mycelium_msg.topic.starts_with("matrix.federation.") {
            self.process_incoming_federation_request(mycelium_msg).await?;
        }

        Ok(())
    }

    async fn process_incoming_federation_request(&self, mycelium_msg: MyceliumFederationMessage) -> Result<()> {
        // Extract the federation request from the Mycelium message
        let method = mycelium_msg.payload.get("method")
            .and_then(|v| v.as_str())
            .ok_or_else(|| BridgeError::Serde {
                message: "Missing method in federation request".to_string()
            })?;

        let path = mycelium_msg.payload.get("path")
            .and_then(|v| v.as_str())
            .ok_or_else(|| BridgeError::Serde {
                message: "Missing path in federation request".to_string()
            })?;

        let body = mycelium_msg.payload.get("body").cloned();
        let headers = mycelium_msg.payload.get("headers")
            .and_then(|v| v.as_object())
            .map(|obj| obj.iter()
                .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string())))
                .collect()
            )
            .unwrap_or_default();

        let request = FederationRequest {
            method: method.to_string(),
            path: path.to_string(),
            body,
            headers,
        };

        // Process the federation request
        let response = self.handle_federation_request(request).await?;

        // Send response back via Mycelium
        if let Some(message_id) = mycelium_msg.payload.get("message_id").and_then(|v| v.as_str()) {
            self.send_mycelium_response(&mycelium_msg.sender, message_id, response).await?;
        }

        Ok(())
    }

    async fn send_mycelium_response(&self, destination: &str, message_id: &str, response: FederationResponse) -> Result<()> {
        if let Some(mycelium_url) = &self.config.mycelium_api_url {
            let client = self.mycelium_client.as_ref()
                .ok_or_else(|| BridgeError::Config {
                    message: "Mycelium client not configured".to_string()
                })?;

            // Get route for the destination
            let route = self.get_mycelium_route(destination).await?;
            let dest_pubkey = self.get_destination_pubkey(destination, &route.mycelium_key, client, mycelium_url).await?;

            let response_payload = serde_json::json!({
                "message_id": message_id,
                "response_body": response.body,
                "status_code": response.status_code,
                "timestamp": std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_secs()
            });

            let mycelium_request = serde_json::json!({
                "dst": { "pk": dest_pubkey },
                "topic": "matrix.federation.response".to_string().into_bytes(),
                "payload": response_payload.to_string().into_bytes()
            });

            let mycelium_response = client
                .post(format!("{}/api/v1/messages", mycelium_url))
                .json(&mycelium_request)
                .send()
                .await
                .map_err(|e| BridgeError::MyceliumApi {
                    message: format!("Failed to send Mycelium response: {}", e)
                })?;

            if mycelium_response.status().is_success() {
                tracing::info!("Sent Mycelium response for message {}", message_id);
            } else {
                tracing::warn!("Failed to send Mycelium response: {}", mycelium_response.status());
            }
        }

        Ok(())
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

    #[tokio::test]
    async fn test_federation_message_flow() {
        let config = BridgeConfig::default();
        let bridge = MatrixMyceliumBridge::new(config).await.unwrap();

        // Test Matrix to Mycelium transformation
        let test_event = MatrixEvent {
            event_id: "test_event_123".to_string(),
            event_type: "m.room.message".to_string(),
            room_id: "!test_room:example.com".to_string(),
            sender: "@user:example.com".to_string(),
            origin_server_ts: 1234567890,
            content: serde_json::json!({"body": "Hello World", "msgtype": "m.text"}),
            state_key: None,
        };

        let mycelium_msg = bridge.translate_matrix_to_mycelium(test_event.clone()).await.unwrap();

        assert_eq!(mycelium_msg.topic, "matrix.federation.message");
        assert_eq!(mycelium_msg.sender, "@user:example.com");
        assert!(mycelium_msg.payload.get("event_id").is_some());
        assert!(mycelium_msg.payload.get("federation_version").is_some());

        // Test Mycelium to Matrix transformation
        let matrix_event = bridge.translate_mycelium_to_matrix(mycelium_msg).await.unwrap();

        assert_eq!(matrix_event.event_type, "m.room.message");
        assert_eq!(matrix_event.sender, "@user:example.com");
        assert_eq!(matrix_event.room_id, "!test_room:example.com");
    }

    #[tokio::test]
    async fn test_federation_route_management() {
        let config = BridgeConfig::default();
        let bridge = MatrixMyceliumBridge::new(config).await.unwrap();

        // Test adding a federation route
        bridge.add_federation_route("test.example.com".to_string(), "test_key_123".to_string()).await.unwrap();

        // Test getting all routes
        let routes = bridge.get_all_federation_routes().await;
        assert_eq!(routes.len(), 1);
        assert_eq!(routes[0].destination_server, "test.example.com");
        assert_eq!(routes[0].mycelium_key, "test_key_123");

        // Test getting specific route
        let route = bridge.get_mycelium_route("test.example.com").await.unwrap();
        assert_eq!(route.destination_server, "test.example.com");

        // Test removing route
        bridge.remove_federation_route("test.example.com").await.unwrap();
        let routes_after = bridge.get_all_federation_routes().await;
        assert_eq!(routes_after.len(), 0);
    }

    #[tokio::test]
    async fn test_server_discovery() {
        let config = BridgeConfig::default();
        let bridge = MatrixMyceliumBridge::new(config).await.unwrap();

        // Test room server extraction
        let servers = bridge.get_room_servers("!room123:matrix.example.com").await.unwrap();
        assert_eq!(servers.len(), 1);
        assert_eq!(servers[0], "matrix.example.com");

        // Test invalid room ID
        let result = bridge.get_room_servers("invalid_room_id").await;
        assert!(result.is_err());
    }
}
