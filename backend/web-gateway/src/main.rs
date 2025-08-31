use axum::{
    body::Body,
    extract::{Path, Request, State},
    http::{StatusCode, Method},
    response::{IntoResponse, Response, Json},
    routing::{any, get, post},
    Json as AxumJson,
    Router,
    middleware,
};
use mycelium_matrix_chat::{config::WebGatewayConfig, error::BridgeError, database::Database};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::sync::Arc;
use tokio::net::TcpListener;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;

// API Types
#[derive(Debug, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateRoomRequest {
    pub room_name: String,
    pub topic: Option<String>,
    pub is_public: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateRoomResponse {
    pub room_id: String,
    pub room_name: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct JoinRoomRequest {
    pub room_id: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct JoinRoomResponse {
    pub room_id: String,
    pub joined: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RoomInfo {
    pub room_id: String,
    pub room_name: String,
    pub topic: Option<String>,
    pub member_count: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ListRoomsResponse {
    pub rooms: Vec<RoomInfo>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AuthRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AuthResponse {
    pub access_token: String,
    pub user_id: String,
}

#[derive(Clone)]
struct GatewayState {
    config: WebGatewayConfig,
    http_client: Client,
    database: Arc<Database>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    tracing::info!("Starting Web Gateway Service");

    // Load configuration
    let config = WebGatewayConfig::from_env()?;

    // Create database connection pool
    let database_url = "postgresql://mycelium:password@localhost/mycelium_db?schema=public".to_string();
    tracing::info!("Connecting to database: {}", database_url);
    let db_pool = mycelium_matrix_chat::database::create_pool(&database_url).await?;
    mycelium_matrix_chat::database::run_migrations(&db_pool).await?;
    let database = Database::new(db_pool).await;

    // Create HTTP client
    let http_client = Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| BridgeError::Config {
            message: format!("Failed to create HTTP client: {}", e)
        })?;

    let state = GatewayState {
        config,
        http_client,
        database: Arc::new(database),
    };

    // Build application
    let app = Router::new()
        // API routes
        .route("/api/rooms/create", post(create_room))
        .route("/api/rooms/join/:room_id", post(join_room))
        .route("/api/rooms/list", get(list_rooms))
        .route("/api/auth/login", post(auth_login))
        .route("/api/auth/logout", post(auth_logout))
        // Legacy proxy routes
        .route("/", any(proxy_request))
        .route("/*path", any(proxy_request))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(Arc::new(state.clone()));

    // Start server
    let addr = std::net::SocketAddr::from(([0, 0, 0, 0], state.config.server_port));

    tracing::info!("Web Gateway listening on {}", addr);

    let listener = TcpListener::bind(addr).await?;

    axum::serve(listener, app).await?;

    Ok(())
}

// API Endpoint Handlers

async fn create_room(
    State(state): State<Arc<GatewayState>>,
    AxumJson(request): AxumJson<CreateRoomRequest>,
) -> Json<ApiResponse<CreateRoomResponse>> {
    tracing::info!("Creating room: {}", request.room_name);

    // Generate a room ID (simple implementation for now)
    let room_id = format!("room_{}", std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis());

    // Create room in database
    let room_state = mycelium_matrix_chat::types::RoomState {
        room_id: room_id.clone(),
        state_events: Vec::new(),
        members: Vec::new(),
        is_external: request.is_public.unwrap_or(false),
    };

    match state.database.store_room_state(&room_state).await {
        Ok(_) => {
            tracing::info!("Room created successfully: {}", room_id);
            Json(ApiResponse {
                success: true,
                data: Some(CreateRoomResponse {
                    room_id: room_id.clone(),
                    room_name: request.room_name.clone(),
                }),
                error: None,
            })
        }
        Err(e) => {
            tracing::error!("Failed to create room: {}", e);
            Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Failed to create room: {}", e)),
            })
        }
    }
}

async fn join_room(
    State(state): State<Arc<GatewayState>>,
    Path(room_id): Path<String>,
    AxumJson(_request): AxumJson<JoinRoomRequest>,
) -> Json<ApiResponse<JoinRoomResponse>> {
    tracing::info!("Joining room: {}", room_id);

    // Check if room exists
    let room_state = match state.database.get_room_state(&room_id).await {
        Ok(Some(state)) => state,
        Ok(None) => {
            return Json(ApiResponse {
                success: false,
                data: None,
                error: Some("Room not found".to_string()),
            });
        }
        Err(e) => {
            tracing::error!("Failed to get room state: {}", e);
            return Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Database error: {}", e)),
            });
        }
    };

    // For now, we'll just assume successful join (no user ID tracking yet)
    tracing::info!("Room joined successfully: {}", room_id);

    Json(ApiResponse {
        success: true,
        data: Some(JoinRoomResponse {
            room_id: room_id.clone(),
            joined: true,
        }),
        error: None,
    })
}

async fn list_rooms(
    State(state): State<Arc<GatewayState>>,
) -> Json<ApiResponse<ListRoomsResponse>> {
    tracing::info!("Listing rooms");

    // For now, return a simple empty list (we need user session tracking to filter)
    // In a real implementation, we'd get this from the database
    let rooms = Vec::new();

    Json(ApiResponse {
        success: true,
        data: Some(ListRoomsResponse { rooms }),
        error: None,
    })
}

async fn auth_login(
    State(state): State<Arc<GatewayState>>,
    AxumJson(_request): AxumJson<AuthRequest>,
) -> Json<ApiResponse<AuthResponse>> {
    tracing::info!("Auth login request");

    // For now, return a mock response (proper Matrix authentication would proxy to homeserver)
    let user_id = "@test:example.com".to_string();
    let access_token = "mock_token_123".to_string();

    Json(ApiResponse {
        success: true,
        data: Some(AuthResponse {
            access_token,
            user_id,
        }),
        error: None,
    })
}

async fn auth_logout(
    State(state): State<Arc<GatewayState>>,
) -> Json<ApiResponse<String>> {
    tracing::info!("Auth logout request");

    // For now, return a mock response
    Json(ApiResponse {
        success: true,
        data: Some("Logged out successfully".to_string()),
        error: None,
    })
}

async fn proxy_request(
    State(state): State<Arc<GatewayState>>,
    mut req: Request,
) -> Result<impl IntoResponse, BridgeError> {
    let path = req.uri().path();
    let query = req.uri().query();
    let method = req.method().clone();

    tracing::info!("Proxying request: {} {} {}", method, path, query.unwrap_or(""));

    let mut url = if path.starts_with("/_matrix") {
        // Handle Matrix API requests by proxying to the correct homeserver
        let mut homeserver = "https://matrix.org"; // Default homeserver

        // Check if we need to proxy to a different homeserver
        // For now, we'll use matrix.org but in the future this could be dynamic
        // based on the user login request

        // Remove any duplicate /_matrix prefix
        let api_path = if path.starts_with("/_matrix/_matrix") {
            path.replace("/_matrix/_matrix", "/_matrix")
        } else {
            path.to_string()
        };

        format!("{}{}", homeserver, api_path)
    } else {
        // Handle frontend routes by serving a simple response
        return Ok(Response::new(Body::from("Gateway is running. Use /_matrix/* for Matrix federation.")));
    };

    // Add query parameters if they exist
    if let Some(query) = query {
        if url.contains('?') {
            url.push('&');
            url.push_str(query);
        } else {
            url.push('?');
            url.push_str(query);
        }
    }

    tracing::debug!("Proxying to URL: {}", url);

    // Build the proxied request
    let mut proxy_req = state.http_client.request(method, &url);

    // Copy headers (excluding hop-by-hop headers)
    for (name, value) in req.headers() {
        if !is_hop_by_hop_header(name) {
            proxy_req = proxy_req.header(name, value);
        }
    }

    // Add Gateway identifier
    proxy_req = proxy_req.header("X-Mycelium-Gateway", "true");

    // Send the request
    let response = proxy_req
        .send()
        .await
        .map_err(|e| BridgeError::MatrixApi {
            message: format!("Gateway proxy error: {}", e)
        })?;

    let status = response.status();
    let headers = response.headers().clone();

    tracing::debug!("Gateway response: {}", status);

    // Get the response body
    let body = response.bytes().await
        .map_err(|e| BridgeError::MatrixApi {
            message: format!("Failed to read response body: {}", e)
        })?;

    // Build the response
    let mut resp = Response::builder().status(status);

    // Copy headers
    for (name, value) in headers {
        if let Some(name) = name {
            if !is_hop_by_hop_header(&name) {
                resp = resp.header(name, value);
            }
        }
    }

    Ok(resp.body(Body::from(body)).unwrap())
}

fn is_hop_by_hop_header(name: &axum::http::HeaderName) -> bool {
    matches!(
        name.as_str(),
        "connection"
        | "keep-alive"
        | "proxy-authenticate"
        | "proxy-authorization"
        | "te"
        | "trailers"
        | "transfer-encoding"
        | "upgrade"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_config_defaults() {
        let config = WebGatewayConfig::default();

        assert_eq!(config.server_host, "0.0.0.0");
        assert_eq!(config.server_port, 8080);
    }
}
