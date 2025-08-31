use axum::{
    body::Body,
    extract::{Request, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::any,
    Router,
};
use mycelium_matrix_chat::{config::WebGatewayConfig, error::BridgeError};
use reqwest::Client;
use std::sync::Arc;
use tokio::net::TcpListener;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;

#[derive(Clone)]
struct GatewayState {
    config: WebGatewayConfig,
    http_client: Client,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    tracing::info!("Starting Web Gateway Service");

    // Load configuration
    let config = WebGatewayConfig::from_env()?;

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
    };

    // Build application
    let app = Router::new()
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
    async fn test_gateway_state_creation() {
        let config = WebGatewayConfig::default();
        let http_client = Client::new();

        let state = GatewayState {
            config,
            http_client,
        };

        assert_eq!(state.config.server_host, "0.0.0.0");
        assert_eq!(state.config.server_port, 8080);
    }
}
