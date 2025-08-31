use axum::{
    routing::{get, post},
    Router,
};
use std::net::SocketAddr;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;

use crate::bridge::MatrixMyceliumBridge;
use crate::config::BridgeConfig;
use crate::error::Result;

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
