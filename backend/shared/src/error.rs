use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;

#[derive(Debug, thiserror::Error)]
pub enum BridgeError {
    #[error("Matrix API error: {message}")]
    MatrixApi { message: String },

    #[error("Mycelium network error: {message}")]
    MyceliumNetwork { message: String },

    #[error("Mycelium API error: {message}")]
    MyceliumApi { message: String },

    #[error("Database error: {message}")]
    Database { message: String },

    #[error("Configuration error: {message}")]
    Config { message: String },

    #[error("Serialization error: {message}")]
    Serde { message: String },

    #[error("Authentication error: {message}")]
    Auth { message: String },

    #[error("Federation error: {message}")]
    Federation { message: String },

    #[error("Connection timeout")]
    Timeout,

    #[error("Resource not found")]
    NotFound,

    #[error("Invalid request: {message}")]
    InvalidRequest { message: String },
}

impl IntoResponse for BridgeError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            BridgeError::MatrixApi { .. } => (StatusCode::BAD_GATEWAY, self.to_string()),
            BridgeError::MyceliumNetwork { .. } => (StatusCode::SERVICE_UNAVAILABLE, self.to_string()),
            BridgeError::MyceliumApi { .. } => (StatusCode::BAD_GATEWAY, self.to_string()),
            BridgeError::Database { .. } => (StatusCode::INTERNAL_SERVER_ERROR, "Database error".to_string()),
            BridgeError::Config { .. } => (StatusCode::INTERNAL_SERVER_ERROR, "Configuration error".to_string()),
            BridgeError::Serde { .. } => (StatusCode::BAD_REQUEST, "Invalid data format".to_string()),
            BridgeError::Auth { .. } => (StatusCode::UNAUTHORIZED, self.to_string()),
            BridgeError::Federation { .. } => (StatusCode::BAD_REQUEST, self.to_string()),
            BridgeError::Timeout => (StatusCode::REQUEST_TIMEOUT, "Request timeout".to_string()),
            BridgeError::NotFound => (StatusCode::NOT_FOUND, "Resource not found".to_string()),
            BridgeError::InvalidRequest { .. } => (StatusCode::BAD_REQUEST, self.to_string()),
        };

        (status, Json(json!({"error": message}))).into_response()
    }
}

impl From<sqlx::Error> for BridgeError {
    fn from(err: sqlx::Error) -> Self {
        BridgeError::Database {
            message: err.to_string(),
        }
    }
}

impl From<serde_json::Error> for BridgeError {
    fn from(err: serde_json::Error) -> Self {
        BridgeError::Serde {
            message: err.to_string(),
        }
    }
}

impl From<reqwest::Error> for BridgeError {
    fn from(err: reqwest::Error) -> Self {
        BridgeError::MatrixApi {
            message: err.to_string(),
        }
    }
}

pub type Result<T> = std::result::Result<T, BridgeError>;
