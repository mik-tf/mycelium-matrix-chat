use mycelium_matrix_chat::{
    bridge::{MatrixMyceliumBridge},
    config::BridgeConfig,
    server::start_bridge_server,
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    tracing::info!("Starting Matrix-Mycelium Bridge Service");

    // Load configuration
    let config = BridgeConfig::from_env()?;

    // Create and initialize bridge
    let bridge = MatrixMyceliumBridge::new(config).await?;

    // Start server
    start_bridge_server(bridge).await?;

    Ok(())
}
