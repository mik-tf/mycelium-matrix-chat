-- Create initial database schema for Mycelium Matrix Chat

-- Matrix Events table
CREATE TABLE matrix_events (
    event_id VARCHAR(255) PRIMARY KEY,
    event_type VARCHAR(255) NOT NULL,
    room_id VARCHAR(255) NOT NULL,
    sender VARCHAR(255) NOT NULL,
    origin_server_ts BIGINT NOT NULL,
    content JSONB,
    state_key VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Rooms table
CREATE TABLE rooms (
    room_id VARCHAR(255) PRIMARY KEY,
    room_name VARCHAR(255),
    topic TEXT,
    is_public BOOLEAN NOT NULL DEFAULT TRUE,
    federation_required BOOLEAN DEFAULT FALSE,
    created_by VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Room Members table
CREATE TABLE room_members (
    room_id VARCHAR(255) NOT NULL,
    user_id VARCHAR(255) NOT NULL,
    membership VARCHAR(50) DEFAULT 'join',
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (room_id, user_id)
);

-- Federation Routes table
CREATE TABLE federation_routes (
    destination_server VARCHAR(255) PRIMARY KEY,
    mycelium_key VARCHAR(255) NOT NULL,
    last_successful BIGINT NOT NULL,
    latency_ms BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User Sessions table
CREATE TABLE user_sessions (
    session_id VARCHAR(255) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    matrix_id VARCHAR(255) NOT NULL,
    mycelium_public_key VARCHAR(255),
    connection_type VARCHAR(50) DEFAULT 'standard',
    access_token TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_active TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_matrix_events_room_id ON matrix_events(room_id);
CREATE INDEX idx_matrix_events_sender ON matrix_events(sender);
CREATE INDEX idx_matrix_events_origin_server_ts ON matrix_events(origin_server_ts);

CREATE INDEX idx_room_members_user_id ON room_members(user_id);
CREATE INDEX idx_room_members_room_id ON room_members(room_id);

CREATE INDEX idx_user_sessions_matrix_id ON user_sessions(matrix_id);

-- Insert default federation route
INSERT INTO federation_routes (destination_server, mycelium_key, last_successful, latency_ms)
VALUES ('matrix.org', 'default-key-1', 0, 100);
