use serde::{Deserialize, Serialize};
use config::Config;
use std::convert::TryFrom;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeConfig {
    pub server_host: String,
    pub server_port: u16,
    pub matrix_homeserver_url: String,
    pub mycelium_api_url: Option<String>,
    pub database_url: String,
    pub redis_url: Option<String>,
    pub federation_timeout: u64,
    pub max_connections: u32,
    pub log_level: String,
    pub mycelium_enabled: bool,
}

impl Default for BridgeConfig {
    fn default() -> Self {
        Self {
            server_host: "0.0.0.0".to_string(),
            server_port: 8081,
            matrix_homeserver_url: "http://localhost:8008".to_string(),
            mycelium_api_url: Some("http://localhost:8989".to_string()),
            database_url: "postgresql://bridge:bridge@localhost/bridge_dev?schema=public".to_string(),
            redis_url: Some("redis://localhost:6379".to_string()),
            federation_timeout: 30,
            max_connections: 100,
            log_level: "info".to_string(),
            mycelium_enabled: true,
        }
    }
}

impl BridgeConfig {
    pub fn from_env() -> anyhow::Result<Self> {
        let mut config = config::Config::default();

        // Load default values
        config.merge(config::Config::try_from(&Self::default())?)?;

        // Load from environment variables
        config.merge(config::Environment::new().prefix("BRIDGE").separator("_"))?;

        // Convert to our config struct
        let bridge_config: Self = config.try_into()?;

        Ok(bridge_config)
    }
}

impl TryFrom<Config> for BridgeConfig {
    type Error = config::ConfigError;

    fn try_from(config: Config) -> Result<Self, Self::Error> {
        Ok(BridgeConfig {
            server_host: config.get_string("server_host")?,
            server_port: config.get_int("server_port")? as u16,
            matrix_homeserver_url: config.get_string("matrix_homeserver_url")?,
            mycelium_api_url: config.get_string("mycelium_api_url").ok(),
            database_url: config.get_string("database_url")?,
            redis_url: config.get_string("redis_url").ok(),
            federation_timeout: config.get_int("federation_timeout")? as u64,
            max_connections: config.get_int("max_connections")? as u32,
            log_level: config.get_string("log_level")?,
            mycelium_enabled: config.get_bool("mycelium_enabled")?,
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebGatewayConfig {
    pub server_host: String,
    pub server_port: u16,
    pub matrix_bridge_url: String,
    pub mycelium_api_url: Option<String>,
    pub rate_limit_requests: u32,
    pub rate_limit_window: u64,
    pub cors_allowed_origins: Vec<String>,
    pub log_level: String,
}

impl Default for WebGatewayConfig {
    fn default() -> Self {
        Self {
            server_host: "0.0.0.0".to_string(),
            server_port: 8080,
            matrix_bridge_url: "http://localhost:8081".to_string(),
            mycelium_api_url: Some("http://localhost:8989".to_string()),
            rate_limit_requests: 1000,
            rate_limit_window: 60, // seconds
            cors_allowed_origins: vec!["http://localhost:3000".to_string()],
            log_level: "info".to_string(),
        }
    }
}

impl WebGatewayConfig {
    pub fn from_env() -> anyhow::Result<Self> {
        let mut config = config::Config::default();

        // Load default values
        config.merge(config::Config::try_from(&Self::default())?)?;

        // Load from environment variables
        config.merge(config::Environment::new().prefix("GATEWAY").separator("_"))?;

        let gateway_config: Self = config.try_into()?;

        Ok(gateway_config)
    }
}

impl TryFrom<Config> for WebGatewayConfig {
    type Error = config::ConfigError;

    fn try_from(config: Config) -> Result<Self, Self::Error> {
        Ok(WebGatewayConfig {
            server_host: config.get_string("server_host")?,
            server_port: config.get_int("server_port")? as u16,
            matrix_bridge_url: config.get_string("matrix_bridge_url")?,
            mycelium_api_url: config.get_string("mycelium_api_url").ok(),
            rate_limit_requests: config.get_int("rate_limit_requests")? as u32,
            rate_limit_window: config.get_int("rate_limit_window")? as u64,
            cors_allowed_origins: config.get_array("cors_allowed_origins")?
                .into_iter()
                .map(|v| v.into_string().unwrap_or_default())
                .collect(),
            log_level: config.get_string("log_level")?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bridge_config_default() {
        let config = BridgeConfig::default();
        assert_eq!(config.server_host, "0.0.0.0");
        assert_eq!(config.server_port, 8081);
        assert_eq!(config.matrix_homeserver_url, "http://localhost:8008");
    }

    #[test]
    fn test_web_gateway_config_default() {
        let config = WebGatewayConfig::default();
        assert_eq!(config.server_host, "0.0.0.0");
        assert_eq!(config.server_port, 8080);
        assert_eq!(config.matrix_bridge_url, "http://localhost:8081");
    }
}
