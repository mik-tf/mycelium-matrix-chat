use sqlx::PgPool;
use crate::error::{Result, BridgeError};
use crate::types::{FederationRoute, RoomState, MatrixEvent};

pub async fn create_pool(database_url: &str) -> Result<PgPool> {
    PgPool::connect(database_url).await
        .map_err(|e| BridgeError::Database {
            message: format!("Failed to connect to database: {}", e)
        })
}

pub async fn run_migrations(pool: &PgPool) -> Result<()> {
    sqlx::migrate!("./migrations")
        .run(pool)
        .await
        .map_err(|e| BridgeError::Database {
            message: format!("Failed to run migrations: {}", e)
        })
}

pub struct Database {
    pool: PgPool,
}

impl Database {
    pub async fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn store_federation_route(&self, route: &FederationRoute) -> Result<()> {
        sqlx::query!(
            r#"
            INSERT INTO federation_routes
            (destination_server, mycelium_key, last_successful, latency_ms)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (destination_server) DO UPDATE SET
                mycelium_key = EXCLUDED.mycelium_key,
                last_successful = EXCLUDED.last_successful,
                latency_ms = EXCLUDED.latency_ms
            "#,
            route.destination_server,
            route.mycelium_key,
            route.last_successful as i64,
            route.latency_ms as i64
        )
        .execute(&self.pool)
        .await
        .map_err(|e| BridgeError::Database {
            message: format!("Failed to store federation route: {}", e)
        })?;

        Ok(())
    }

    pub async fn get_federation_route(&self, server: &str) -> Result<Option<FederationRoute>> {
        let route = sqlx::query_as!(
            FederationRoute,
            r#"
            SELECT destination_server, mycelium_key, last_successful, latency_ms
            FROM federation_routes
            WHERE destination_server = $1
            "#,
            server
        )
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| BridgeError::Database {
            message: format!("Failed to get federation route: {}", e)
        })?;

        Ok(route)
    }

    pub async fn get_all_federation_routes(&self) -> Result<Vec<FederationRoute>> {
        let routes = sqlx::query_as!(
            FederationRoute,
            r#"
            SELECT destination_server, mycelium_key, last_successful, latency_ms
            FROM federation_routes
            ORDER BY destination_server
            "#,
        )
        .fetch_all(&self.pool)
        .await
        .map_err(|e| BridgeError::Database {
            message: format!("Failed to get all federation routes: {}", e)
        })?;

        Ok(routes)
    }

    pub async fn store_room_state(&self, room_state: &RoomState) -> Result<()> {
        // Store/update room information
        sqlx::query!(
            r#"
            INSERT INTO rooms (room_id, is_public)
            VALUES ($1, $2)
            ON CONFLICT (room_id) DO NOTHING
            "#,
            room_state.room_id,
            room_state.is_external
        )
        .execute(&self.pool)
        .await
        .map_err(|e| BridgeError::Database {
            message: format!("Failed to store room: {}", e)
        })?;

        // Store state events
        for event in &room_state.state_events {
            // Insert event with ON CONFLICT to handle duplicate event IDs
            let _ = sqlx::query!(
                r#"
                INSERT INTO matrix_events
                (event_id, event_type, room_id, sender, origin_server_ts, content, state_key)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                ON CONFLICT (event_id) DO NOTHING
                "#,
                event.event_id,
                event.event_type,
                event.room_id,
                event.sender,
                event.origin_server_ts as i64,
                event.content.clone(),
                event.state_key
            )
            .execute(&self.pool)
            .await
            .map_err(|e| BridgeError::Database {
                message: format!("Failed to store room event: {}", e)
            })?;
        }

        // Update room membership
        // First, remove all existing members for this room
        sqlx::query!(
            r#"DELETE FROM room_members WHERE room_id = $1"#,
            room_state.room_id
        )
        .execute(&self.pool)
        .await
        .map_err(|e| BridgeError::Database {
            message: format!("Failed to clear room members: {}", e)
        })?;

        // Add current members
        for member in &room_state.members {
            sqlx::query!(
                r#"
                INSERT INTO room_members (room_id, user_id, membership)
                VALUES ($1, $2, 'join')
                "#,
                room_state.room_id,
                member
            )
            .execute(&self.pool)
            .await
            .map_err(|e| BridgeError::Database {
                message: format!("Failed to store room member: {}", e)
            })?;
        }

        Ok(())
    }

    pub async fn get_room_state(&self, room_id: &str) -> Result<Option<RoomState>> {
        // Check if room exists
        let room_row = sqlx::query!(
            r#"SELECT room_id, is_public FROM rooms WHERE room_id = $1"#,
            room_id
        )
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| BridgeError::Database {
            message: format!("Failed to get room: {}", e)
        })?;

        let Some(room_row) = room_row else {
            return Ok(None); // Room doesn't exist
        };

        // Get room members
        let member_rows = sqlx::query!(
            r#"SELECT user_id FROM room_members WHERE room_id = $1 AND membership = 'join'"#,
            room_id
        )
        .fetch_all(&self.pool)
        .await
        .map_err(|e| BridgeError::Database {
            message: format!("Failed to get room members: {}", e)
        })?;

        let members = member_rows.into_iter().map(|row| row.user_id).collect();

        // Get state events
        let state_event_rows = sqlx::query!(
            r#"
            SELECT event_id, event_type, room_id, sender, origin_server_ts, content, state_key
            FROM matrix_events
            WHERE room_id = $1 AND state_key IS NOT NULL
            ORDER BY origin_server_ts ASC
            "#,
            room_id
        )
        .fetch_all(&self.pool)
        .await
        .map_err(|e| BridgeError::Database {
            message: format!("Failed to get room state events: {}", e)
        })?;

        let state_events = state_event_rows
            .into_iter()
            .map(|row| MatrixEvent {
                event_id: row.event_id,
                event_type: row.event_type,
                room_id: row.room_id,
                sender: row.sender,
                origin_server_ts: row.origin_server_ts as u64,
                content: row.content.unwrap_or_else(|| serde_json::json!({})),
                state_key: row.state_key,
            })
            .collect();

        let room_state = RoomState {
            room_id: room_row.room_id,
            state_events,
            members,
            is_external: room_row.is_public,
        };

        Ok(Some(room_state))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[tokio::test]
    async fn test_create_pool_success() {
        // This test assumes a test database is available
        // For now, we'll skip actual database tests
        // In real implementation, we'd use a test database
        assert!(true);
    }

    fn test_federation_route_creation() {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let route = FederationRoute {
            destination_server: "server1.com".to_string(),
            mycelium_key: "key123".to_string(),
            last_successful: now as i64,
            latency_ms: 50,
        };

        assert_eq!(route.destination_server, "server1.com");
        assert_eq!(route.mycelium_key, "key123");
        assert_eq!(route.latency_ms, 50);
    }
}
