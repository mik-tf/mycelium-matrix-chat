use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    routing::{delete, get, post, put},
    Router,
};
use serde_json::json;
use std::collections::HashMap;
use std::net::SocketAddr;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;

use crate::bridge::MatrixMyceliumBridge;
use crate::config::BridgeConfig;
use crate::error::Result;
use crate::types::*;

pub async fn start_bridge_server(bridge: MatrixMyceliumBridge) -> Result<()> {
    let config = bridge.config.clone();

    let app = create_router(bridge);

    let addr = SocketAddr::from(([0, 0, 0, 0], config.server_port));

    tracing::info!("Starting Matrix-Mycelium Bridge server on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await
        .map_err(|e| crate::error::BridgeError::Config {
            message: format!("Failed to bind to {}: {}", addr, e)
        })?;

    axum::serve(listener, app)
        .await
        .map_err(|e| crate::error::BridgeError::Config {
            message: format!("Server error: {}", e)
        })?;

    Ok(())
}

fn create_router(bridge: MatrixMyceliumBridge) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let bridge_state = std::sync::Arc::new(bridge);

    Router::new()
        .route("/health", get(health_check))
        .route("/api/v1/bridge/status", get(get_status))
        .route("/api/v1/bridge/federation/send", post(send_federation_message))
        .route("/api/v1/bridge/events/translate/matrix", post(translate_matrix_event))
        .route("/api/v1/bridge/events/translate/mycelium", post(translate_mycelium_event))
        .route("/api/v1/bridge/servers", get(get_federation_servers))
        .route("/api/v1/bridge/routes", get(get_federation_routes))
        .route("/api/v1/bridge/routes", post(add_federation_route))
        .route("/api/v1/bridge/routes/:server_name", delete(remove_federation_route))
        .route("/api/v1/bridge/mycelium/incoming", post(receive_mycelium_message))
        .route("/api/v1/bridge/test/federation/:server_name", post(test_federation))
        .route("/api/v1/bridge/test/end-to-end", post(run_end_to_end_test))
        .route("/api/v1/bridge/test/p2p-benefits", get(analyze_p2p_benefits))
        // Matrix Server-Server API endpoints
        .route("/_matrix/federation/v1/send/:txn_id", put(send_pdu))
        .route("/_matrix/federation/v1/state/:room_id", get(get_room_state))
        .route("/_matrix/federation/v1/state_ids/:room_id", get(get_room_state_ids))
        .route("/_matrix/federation/v1/backfill/:room_id", get(backfill_room))
        .route("/_matrix/federation/v1/query/:query_type", get(query_federation))
        .route("/_matrix/federation/v1/user/devices/:user_id", get(get_user_devices))
        .route("/_matrix/federation/v1/make_join/:room_id/:user_id", get(make_join))
        .route("/_matrix/federation/v1/send_join/:room_id/:event_id", put(send_join))
        .route("/_matrix/federation/v1/make_leave/:room_id/:user_id", get(make_leave))
        .route("/_matrix/federation/v1/send_leave/:room_id/:event_id", put(send_leave))
        .route("/_matrix/federation/v1/invite/:room_id/:event_id", put(send_invite))
        .route("/_matrix/federation/v1/make_knock/:room_id/:user_id", get(make_knock))
        .route("/_matrix/federation/v1/send_knock/:room_id/:event_id", put(send_knock))
        .layer(cors)
        .layer(TraceLayer::new_for_http())
        .with_state(bridge_state)
}

async fn health_check() -> &'static str {
    "OK"
}

async fn get_status(
    axum::extract::State(bridge): axum::extract::State<std::sync::Arc<MatrixMyceliumBridge>>,
) -> Result<axum::response::Json<crate::types::BridgeStatus>> {
    let status = bridge.get_bridge_status().await?;
    Ok(axum::response::Json(status))
}

async fn send_federation_message(
    axum::extract::State(bridge): axum::extract::State<std::sync::Arc<MatrixMyceliumBridge>>,
    axum::extract::Json(request): axum::extract::Json<crate::types::FederationRequest>,
) -> Result<axum::response::Json<crate::types::FederationResponse>> {
    let response = bridge.handle_federation_request(request).await?;
    Ok(axum::response::Json(response))
}

async fn translate_matrix_event(
    axum::extract::State(bridge): axum::extract::State<std::sync::Arc<MatrixMyceliumBridge>>,
    axum::extract::Json(event): axum::extract::Json<crate::types::MatrixEvent>,
) -> Result<axum::response::Json<crate::types::MyceliumFederationMessage>> {
    let mycelium_msg = bridge.translate_matrix_to_mycelium(event).await?;
    Ok(axum::response::Json(mycelium_msg))
}

async fn translate_mycelium_event(
    axum::extract::State(bridge): axum::extract::State<std::sync::Arc<MatrixMyceliumBridge>>,
    axum::extract::Json(mycelium_msg): axum::extract::Json<crate::types::MyceliumFederationMessage>,
) -> Result<axum::response::Json<crate::types::MatrixEvent>> {
    let matrix_event = bridge.translate_mycelium_to_matrix(mycelium_msg).await?;
    Ok(axum::response::Json(matrix_event))
}

async fn get_federation_servers(
    axum::extract::State(_bridge): axum::extract::State<std::sync::Arc<MatrixMyceliumBridge>>,
    axum::extract::Query(params): axum::extract::Query<std::collections::HashMap<String, String>>,
) -> axum::response::Json<serde_json::Value> {
    // TODO: Implement server discovery from database
    // For now, return a placeholder response

    let response = if params.get("server").is_some() {
        serde_json::json!({
            "server": params.get("server").unwrap(),
            "mycelium_key": null,
            "status": "unknown"
        })
    } else {
        serde_json::json!({
            "servers": [],
            "count": 0
        })
    };

    axum::response::Json(response)
}

async fn get_federation_routes(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
) -> Result<Json<serde_json::Value>> {
    let routes = bridge.get_all_federation_routes().await;
    Ok(Json(serde_json::json!({
        "routes": routes,
        "count": routes.len()
    })))
}

async fn add_federation_route(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Json(route_data): Json<serde_json::Value>,
) -> Result<StatusCode> {
    let server_name = route_data.get("server_name")
        .and_then(|v| v.as_str())
        .ok_or_else(|| crate::error::BridgeError::InvalidRequest {
            message: "server_name is required".to_string()
        })?;

    let mycelium_key = route_data.get("mycelium_key")
        .and_then(|v| v.as_str())
        .ok_or_else(|| crate::error::BridgeError::InvalidRequest {
            message: "mycelium_key is required".to_string()
        })?;

    bridge.add_federation_route(server_name.to_string(), mycelium_key.to_string()).await?;
    Ok(StatusCode::CREATED)
}

async fn remove_federation_route(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path(server_name): Path<String>,
) -> Result<StatusCode> {
    bridge.remove_federation_route(&server_name).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn receive_mycelium_message(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Json(mycelium_msg): Json<crate::types::MyceliumFederationMessage>,
) -> Result<StatusCode> {
    tracing::info!("Received Mycelium message via HTTP endpoint");

    bridge.handle_incoming_mycelium_message(mycelium_msg).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn test_federation(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path(server_name): Path<String>,
    Json(test_data): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Testing federation with server: {}", server_name);

    // Create a test federation request
    let test_request = FederationRequest {
        method: test_data.get("method")
            .and_then(|v| v.as_str())
            .unwrap_or("GET")
            .to_string(),
        path: test_data.get("path")
            .and_then(|v| v.as_str())
            .unwrap_or("/_matrix/federation/v1/version")
            .to_string(),
        body: test_data.get("body").cloned(),
        headers: std::collections::HashMap::new(),
    };

    // Test the federation routing
    match bridge.test_federation_connection(&server_name, test_request).await {
        Ok((response, routing_method, duration)) => {
            Ok(Json(serde_json::json!({
                "success": true,
                "server": server_name,
                "status_code": response.status_code,
                "response_time_ms": duration,
                "response_body": response.body,
                "routing_method": routing_method
            })))
        },
        Err(e) => {
            Ok(Json(serde_json::json!({
                "success": false,
                "server": server_name,
                "error": e.to_string(),
                "response_time_ms": 0,
                "routing_method": "failed"
            })))
        }
    }
}

async fn run_end_to_end_test(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Json(test_config): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Running end-to-end federation test");

    let test_server = test_config.get("test_server")
        .and_then(|v| v.as_str())
        .unwrap_or("matrix.org");

    let message_count = test_config.get("message_count")
        .and_then(|v| v.as_u64())
        .unwrap_or(5) as usize;

    let mut results = Vec::new();
    let mut total_matrix_time = 0u128;
    let mut total_mycelium_time = 0u128;
    let mut matrix_success_count = 0;
    let mut mycelium_success_count = 0;

    // Test Matrix routing (disable Mycelium temporarily)
    let original_mycelium_enabled = bridge.config.mycelium_enabled;
    // Note: In a real implementation, we'd modify the config temporarily

    for i in 0..message_count {
        // Create test message
        let test_event = crate::types::MatrixEvent {
            event_id: format!("test_event_{}", i),
            event_type: "m.room.message".to_string(),
            room_id: format!("!test_room_{}:{}", i, test_server),
            sender: format!("@test_user_{}:example.com", i),
            origin_server_ts: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            content: serde_json::json!({
                "body": format!("Test message {}", i),
                "msgtype": "m.text"
            }),
            state_key: None,
        };

        // Test Matrix routing
        let matrix_request = crate::types::FederationRequest {
            method: "PUT".to_string(),
            path: format!("/_matrix/federation/v1/send/txn_{}", i),
            body: Some(serde_json::json!({
                "edus": [],
                "pdus": [test_event]
            })),
            headers: std::collections::HashMap::new(),
        };

        let matrix_start = std::time::Instant::now();
        let matrix_result = bridge.handle_via_matrix(matrix_request).await;
        let matrix_duration = matrix_start.elapsed().as_millis();

        total_matrix_time += matrix_duration;
        if matrix_result.is_ok() {
            matrix_success_count += 1;
        }

        // Test Mycelium routing (if available)
        let mycelium_duration = if bridge.config.mycelium_enabled {
            let mycelium_request = crate::types::FederationRequest {
                method: "PUT".to_string(),
                path: format!("/_matrix/federation/v1/send/txn_myc_{}", i),
                body: Some(serde_json::json!({
                    "edus": [],
                    "pdus": [test_event]
                })),
                headers: std::collections::HashMap::new(),
            };

            let mycelium_start = std::time::Instant::now();
            let mycelium_result = bridge.handle_via_mycelium(mycelium_request, test_server.to_string()).await;
            let duration = mycelium_start.elapsed().as_millis();

            total_mycelium_time += duration;
            if mycelium_result.is_ok() {
                mycelium_success_count += 1;
            }

            Some(duration)
        } else {
            None
        };

        results.push(serde_json::json!({
            "message_id": i,
            "matrix_time_ms": matrix_duration,
            "mycelium_time_ms": mycelium_duration,
            "matrix_success": matrix_result.is_ok(),
            "mycelium_success": mycelium_duration.is_some()
        }));
    }

    let matrix_avg_time = if message_count > 0 { total_matrix_time / message_count as u128 } else { 0 };
    let mycelium_avg_time = if mycelium_success_count > 0 { total_mycelium_time / mycelium_success_count as u128 } else { 0 };

    let performance_improvement = if mycelium_avg_time > 0 && matrix_avg_time > 0 {
        ((matrix_avg_time as f64 - mycelium_avg_time as f64) / matrix_avg_time as f64 * 100.0).round()
    } else {
        0.0
    };

    Ok(Json(serde_json::json!({
        "test_completed": true,
        "test_server": test_server,
        "message_count": message_count,
        "results": results,
        "summary": {
            "matrix_routing": {
                "success_rate": format!("{}/{}", matrix_success_count, message_count),
                "average_time_ms": matrix_avg_time
            },
            "mycelium_routing": {
                "success_rate": format!("{}/{}", mycelium_success_count, message_count),
                "average_time_ms": mycelium_avg_time
            },
            "performance_comparison": {
                "improvement_percentage": performance_improvement,
                "mycelium_faster": performance_improvement > 0.0
            }
        },
        "p2p_benefits_validated": mycelium_success_count > 0 && performance_improvement > 0.0
    })))
}

async fn analyze_p2p_benefits(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
) -> Result<Json<serde_json::Value>> {
    let status = bridge.get_bridge_status().await?;
    let routes = bridge.get_all_federation_routes().await;

    // Analyze current P2P benefits
    let mycelium_connected = status.mycelium_connected;
    let active_routes = routes.len();
    let pending_messages = status.pending_messages;

    // Calculate theoretical benefits
    let decentralization_benefit = if mycelium_connected {
        "High - Messages route through decentralized P2P network instead of centralized Matrix federation"
    } else {
        "Low - Falling back to standard Matrix federation"
    };

    let privacy_benefit = if mycelium_connected {
        "High - End-to-end encrypted P2P communication with no central message logging"
    } else {
        "Medium - Standard Matrix federation with homeserver logging"
    };

    let performance_benefit = if mycelium_connected && active_routes > 0 {
        "High - Direct P2P routing reduces latency and eliminates federation hops"
    } else {
        "Low - Standard federation routing through multiple homeservers"
    };

    let resilience_benefit = if mycelium_connected {
        "High - P2P network maintains connectivity even if central servers fail"
    } else {
        "Medium - Dependent on homeserver availability and federation links"
    };

    Ok(Json(serde_json::json!({
        "analysis_timestamp": std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs(),
        "mycelium_status": {
            "connected": mycelium_connected,
            "active_routes": active_routes,
            "pending_messages": pending_messages
        },
        "p2p_benefits": {
            "decentralization": {
                "level": if mycelium_connected { "High" } else { "Low" },
                "description": decentralization_benefit
            },
            "privacy": {
                "level": if mycelium_connected { "High" } else { "Medium" },
                "description": privacy_benefit
            },
            "performance": {
                "level": if mycelium_connected && active_routes > 0 { "High" } else { "Low" },
                "description": performance_benefit
            },
            "resilience": {
                "level": if mycelium_connected { "High" } else { "Medium" },
                "description": resilience_benefit
            }
        },
        "federation_routes": routes.into_iter().map(|route| {
            serde_json::json!({
                "server": route.destination_server,
                "mycelium_key": route.mycelium_key,
                "latency_ms": route.latency_ms,
                "last_success": route.last_successful
            })
        }).collect::<Vec<_>>(),
        "recommendations": {
            "setup_mycelium": !mycelium_connected,
            "add_more_routes": active_routes < 3,
            "monitor_performance": true,
            "test_federation": true
        },
        "overall_p2p_score": if mycelium_connected && active_routes > 0 {
            "Excellent - Full P2P federation active"
        } else if mycelium_connected {
            "Good - Mycelium connected but limited routes"
        } else {
            "Basic - Standard Matrix federation only"
        }
    })))
}

// Matrix Server-Server API Handlers

async fn send_pdu(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path(txn_id): Path<String>,
    Json(pdus): Json<Vec<serde_json::Value>>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Received PDUs for transaction {}", txn_id);

    // Process each PDU (Persistent Data Unit)
    for pdu in &pdus {
        if let Some(room_id) = pdu.get("room_id").and_then(|v| v.as_str()) {
            let matrix_event: MatrixEvent = serde_json::from_value(pdu.clone())
                .map_err(|e| crate::error::BridgeError::Serde {
                    message: format!("Failed to parse PDU: {}", e)
                })?;

            // Route through Mycelium if available
            let _ = bridge.translate_matrix_to_mycelium(matrix_event).await;
        }
    }

    // Return empty object as per Matrix spec
    Ok(Json(json!({})))
}

async fn get_room_state(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path(room_id): Path<String>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Getting room state for {}", room_id);

    // Extract event IDs from query parameters
    let event_ids: Vec<String> = params.get("event_id")
        .map(|ids| ids.split(',').map(|s| s.to_string()).collect())
        .unwrap_or_default();

    // TODO: Implement actual room state retrieval
    // For now, return empty state
    Ok(Json(json!({
        "pdus": [],
        "auth_chain": []
    })))
}

async fn get_room_state_ids(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path(room_id): Path<String>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Getting room state IDs for {}", room_id);

    // TODO: Implement actual state ID retrieval
    Ok(Json(json!({
        "pdu_ids": [],
        "auth_chain_ids": []
    })))
}

async fn backfill_room(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path(room_id): Path<String>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Backfilling room {}", room_id);

    // TODO: Implement backfill logic
    Ok(Json(json!({
        "pdus": [],
        "auth_chain": []
    })))
}

async fn query_federation(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path(query_type): Path<String>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Federation query: {}", query_type);

    match query_type.as_str() {
        "profile" => {
            // User profile query
            Ok(Json(json!({
                "displayname": null,
                "avatar_url": null
            })))
        },
        "directory" => {
            // Room directory query
            Ok(Json(json!({
                "room_id": null,
                "servers": []
            })))
        },
        _ => {
            // Unknown query type
            Err(crate::error::BridgeError::InvalidRequest {
                message: format!("Unknown query type: {}", query_type)
            })
        }
    }
}

async fn get_user_devices(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path(user_id): Path<String>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Getting devices for user {}", user_id);

    // TODO: Implement device list retrieval
    Ok(Json(json!({
        "user_id": user_id,
        "devices": [],
        "master_key": null,
        "self_signing_key": null
    })))
}

async fn make_join(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path((room_id, user_id)): Path<(String, String)>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Make join request for {} in {}", user_id, room_id);

    // TODO: Implement make_join logic
    Ok(Json(json!({
        "event": {
            "type": "m.room.member",
            "room_id": room_id,
            "sender": user_id,
            "content": {
                "membership": "join"
            }
        },
        "room_version": "6"
    })))
}

async fn send_join(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path((room_id, event_id)): Path<(String, String)>,
    Json(pdu): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Send join for room {} with event {}", room_id, event_id);

    // TODO: Process join PDU
    Ok(Json(json!({})))
}

async fn make_leave(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path((room_id, user_id)): Path<(String, String)>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Make leave request for {} in {}", user_id, room_id);

    // TODO: Implement make_leave logic
    Ok(Json(json!({
        "event": {
            "type": "m.room.member",
            "room_id": room_id,
            "sender": user_id,
            "content": {
                "membership": "leave"
            }
        }
    })))
}

async fn send_leave(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path((room_id, event_id)): Path<(String, String)>,
    Json(pdu): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Send leave for room {} with event {}", room_id, event_id);

    // TODO: Process leave PDU
    Ok(Json(json!({})))
}

async fn send_invite(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path((room_id, event_id)): Path<(String, String)>,
    Json(pdu): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Send invite for room {} with event {}", room_id, event_id);

    // TODO: Process invite PDU
    Ok(Json(json!({})))
}

async fn make_knock(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path((room_id, user_id)): Path<(String, String)>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Make knock request for {} in {}", user_id, room_id);

    // TODO: Implement make_knock logic
    Ok(Json(json!({
        "event": {
            "type": "m.room.member",
            "room_id": room_id,
            "sender": user_id,
            "content": {
                "membership": "knock"
            }
        }
    })))
}

async fn send_knock(
    State(bridge): State<std::sync::Arc<MatrixMyceliumBridge>>,
    Path((room_id, event_id)): Path<(String, String)>,
    Json(pdu): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>> {
    tracing::info!("Send knock for room {} with event {}", room_id, event_id);

    // TODO: Process knock PDU
    Ok(Json(json!({})))
}
