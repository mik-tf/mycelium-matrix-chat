-- Initial database setup for Mycelium Matrix Chat

-- Database tables are now managed through SQLx migrations
-- This file is kept for any additional initialization if needed

-- Insert some default data for testing
INSERT INTO federation_routes (destination_server, mycelium_key, last_successful, latency_ms)
VALUES ('matrix.org', 'default-key-1', 0, 100)
ON CONFLICT (destination_server) DO NOTHING;
