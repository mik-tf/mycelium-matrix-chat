# Development Guide

## 🚀 Quick Start

### Prerequisites

**System Requirements**:
- Rust 1.75+ with Cargo
- Node.js 18+ with npm/yarn
- Docker and Docker Compose
- Git

**Recommended Tools**:
- VS Code with Rust Analyzer extension
- Postman or similar API testing tool
- Redis CLI for debugging
- PostgreSQL client

### Environment Setup

#### 1. Clone and Initialize Project
```bash
# Clone the repository
git clone https://github.com/mik-tf/mycelium-matrix-chat.git
cd mycelium-matrix-chat

# Initialize git submodules (for Mycelium)
git submodule update --init --recursive

# Set up development environment
./scripts/setup-dev.sh
```

#### 2. Install Dependencies
```bash
# Backend dependencies (Rust)
cd backend
cargo build

# Frontend dependencies (Node.js)
cd ../frontend
npm install

# Build tools
cd ../tools
cargo build --release
```

#### 3. Development Configuration
```bash
# Copy environment templates
cp .env.example .env.development
cp docker-compose.override.yml.example docker-compose.override.yml

# Generate development certificates
./scripts/generate-dev-certs.sh

# Start development services
docker-compose up -d postgres redis mycelium
```

### Project Structure

```
mycelium-matrix-chat/
├── backend/                     # Rust backend services
│   ├── matrix-bridge/          # Matrix-Mycelium bridge service
│   ├── web-gateway/            # HTTPS gateway service
│   ├── shared/                 # Shared libraries and utilities
│   └── migrations/             # Database migrations
├── frontend/                   # Web application
│   ├── src/
│   │   ├── components/        # React components
│   │   ├── services/          # API clients and business logic
│   │   ├── hooks/             # Custom React hooks
│   │   └── utils/             # Utility functions
│   ├── public/                # Static assets
│   └── tests/                 # Frontend tests
├── mobile/                     # Mobile applications
│   ├── ios/                   # iOS application
│   ├── android/               # Android application
│   └── shared/                # Shared mobile code
├── docs/                       # Documentation
├── scripts/                    # Development and deployment scripts
├── tests/                      # Integration tests
└── docker/                     # Docker configurations
```

## 🔧 Backend Development

### Rust Workspace Structure

#### Core Services Architecture
```rust
// workspace Cargo.toml
[workspace]
members = [
    "matrix-bridge",
    "web-gateway", 
    "shared/types",
    "shared/database",
    "shared/crypto",
    "shared/networking"
]

resolver = "2"

[workspace.dependencies]
tokio = { version = "1.0", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
anyhow = "1.0"
tracing = "0.1"
```

#### Matrix Bridge Service
```rust
// backend/matrix-bridge/src/main.rs
use matrix_bridge::{
    bridge::MatrixMyceliumBridge,
    config::BridgeConfig,
    server::start_bridge_server,
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::init();
    
    let config = BridgeConfig::from_env()?;
    let bridge = MatrixMyceliumBridge::new(config).await?;
    
    start_bridge_server(bridge).await
}
```

#### Development Database Setup
```rust
// backend/shared/database/src/lib.rs
use sqlx::{PgPool, postgres::PgPoolOptions};

pub async fn create_dev_pool() -> Result<PgPool, sqlx::Error> {
    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgresql://dev:dev@localhost/mycelium_matrix_dev".to_string());
    
    PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await
}

pub async fn run_migrations(pool: &PgPool) -> Result<(), sqlx::Error> {
    sqlx::migrate!("./migrations").run(pool).await
}
```

### Development Workflow

#### 1. Running Services Locally
```bash
# Terminal 1: Start Mycelium node
cd mycelium
cargo run --bin mycelium -- --config ../config/dev-mycelium.toml

# Terminal 2: Start Matrix bridge
cd backend/matrix-bridge
cargo run

# Terminal 3: Start web gateway  
cd backend/web-gateway
cargo run

# Terminal 4: Start frontend
cd frontend
npm run dev
```

#### 2. Testing and Debugging
```bash
# Run backend tests
cd backend
cargo test

# Run integration tests
cargo test --test integration

# Check code formatting
cargo fmt --check

# Run linter
cargo clippy

# Debug with logs
RUST_LOG=debug cargo run
```

#### 3. Database Migrations
```bash
# Create new migration
sqlx migrate add create_federation_routes

# Run migrations
sqlx migrate run

# Revert last migration
sqlx migrate revert
```

### API Development

#### Service Definition
```rust
// backend/matrix-bridge/src/api.rs
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};

pub fn create_bridge_router() -> Router<BridgeState> {
    Router::new()
        .route("/api/v1/bridge/status", get(get_bridge_status))
        .route("/api/v1/bridge/federation/send", post(send_federation_message))
        .route("/api/v1/bridge/rooms/:room_id/state", get(get_room_state))
}

async fn get_bridge_status(
    State(state): State<BridgeState>
) -> Result<Json<BridgeStatus>, StatusCode> {
    let status = state.bridge.get_status().await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(status))
}
```

#### Error Handling
```rust
// backend/shared/types/src/errors.rs
use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};

#[derive(Debug, thiserror::Error)]
pub enum BridgeError {
    #[error("Matrix API error: {0}")]
    MatrixApi(String),
    
    #[error("Mycelium network error: {0}")]
    MyceliumNetwork(String),
    
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),
    
    #[error("Configuration error: {0}")]
    Config(String),
}

impl IntoResponse for BridgeError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            BridgeError::MatrixApi(_) => (StatusCode::BAD_GATEWAY, self.to_string()),
            BridgeError::MyceliumNetwork(_) => (StatusCode::SERVICE_UNAVAILABLE, self.to_string()),
            BridgeError::Database(_) => (StatusCode::INTERNAL_SERVER_ERROR, "Database error".to_string()),
            BridgeError::Config(_) => (StatusCode::INTERNAL_SERVER_ERROR, "Configuration error".to_string()),
        };
        
        (status, Json(serde_json::json!({"error": message}))).into_response()
    }
}
```

## 🌐 Frontend Development

### React Application Setup

#### Technology Stack
```json
{
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "typescript": "^5.0.0",
    "@tanstack/react-query": "^5.0.0",
    "@matrix-org/matrix-js-sdk": "^28.0.0",
    "zustand": "^4.4.0",
    "tailwindcss": "^3.3.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.0.0",
    "vite": "^4.4.0",
    "vitest": "^0.34.0",
    "@testing-library/react": "^13.4.0"
  }
}
```

#### Application Structure
```typescript
// frontend/src/main.tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { App } from './App';
import './index.css';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 1000 * 60 * 5 }, // 5 minutes
  },
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
  </React.StrictMode>
);
```

#### State Management
```typescript
// frontend/src/stores/connectionStore.ts
import { create } from 'zustand';
import { devtools, subscribeWithSelector } from 'zustand/middleware';

interface ConnectionState {
  type: 'enhanced' | 'standard' | 'connecting' | 'offline';
  myceliumDetected: boolean;
  quality: 'excellent' | 'good' | 'fair' | 'poor';
  latency?: number;
}

interface ConnectionStore extends ConnectionState {
  detectMycelium: () => Promise<void>;
  switchConnection: (type: 'enhanced' | 'standard') => Promise<void>;
  updateQuality: (quality: ConnectionState['quality']) => void;
}

export const useConnectionStore = create<ConnectionStore>()(
  devtools(
    subscribeWithSelector((set, get) => ({
      type: 'connecting',
      myceliumDetected: false,
      quality: 'good',
      
      detectMycelium: async () => {
        try {
          const response = await fetch('http://localhost:8989/api/v1/admin');
          const detected = response.ok;
          
          set({ 
            myceliumDetected: detected,
            type: detected ? 'enhanced' : 'standard'
          });
        } catch {
          set({ type: 'standard', myceliumDetected: false });
        }
      },
      
      switchConnection: async (type) => {
        set({ type: 'connecting' });
        // Implementation for switching connection type
        await new Promise(resolve => setTimeout(resolve, 1000));
        set({ type });
      },
      
      updateQuality: (quality) => set({ quality }),
    }))
  )
);
```

#### Matrix Integration
```typescript
// frontend/src/services/matrixClient.ts
import { createClient, MatrixClient, MatrixEvent } from 'matrix-js-sdk';

class MatrixClientManager {
  private client: MatrixClient | null = null;
  private connectionType: 'enhanced' | 'standard' = 'standard';
  
  async initialize(accessToken: string, baseUrl: string) {
    this.client = createClient({
      baseUrl,
      accessToken,
      userId: '@user:example.com', // Retrieved from login
    });
    
    this.setupEventHandlers();
    await this.client.startClient();
  }
  
  private setupEventHandlers() {
    if (!this.client) return;
    
    this.client.on('Room.timeline', (event: MatrixEvent) => {
      // Handle incoming messages
      console.log('New message:', event.getContent());
    });
    
    this.client.on('sync', (state: string) => {
      console.log('Sync state:', state);
    });
  }
  
  async sendMessage(roomId: string, content: any) {
    if (!this.client) throw new Error('Client not initialized');
    
    return this.client.sendEvent(roomId, 'm.room.message', content);
  }
  
  setConnectionType(type: 'enhanced' | 'standard') {
    this.connectionType = type;
    // Update transport layer based on connection type
  }
}

export const matrixClient = new MatrixClientManager();
```

### Development Tools

#### Hot Reloading Setup
```typescript
// vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
      '/_matrix': {
        target: 'http://localhost:8008',
        changeOrigin: true,
      },
    },
  },
  define: {
    'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV),
  },
});
```

#### Testing Setup
```typescript
// frontend/src/test-utils.tsx
import React, { ReactElement } from 'react';
import { render, RenderOptions } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const createTestQueryClient = () =>
  new QueryClient({
    defaultOptions: {
      queries: { retry: false },
      mutations: { retry: false },
    },
  });

const AllTheProviders = ({ children }: { children: React.ReactNode }) => {
  const queryClient = createTestQueryClient();
  
  return (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  );
};

const customRender = (
  ui: ReactElement,
  options?: Omit<RenderOptions, 'wrapper'>
) => render(ui, { wrapper: AllTheProviders, ...options });

export * from '@testing-library/react';
export { customRender as render };
```

## 🧪 Testing Strategy

### Unit Testing

#### Backend Tests
```rust
// backend/matrix-bridge/src/bridge.rs
#[cfg(test)]
mod tests {
    use super::*;
    use tokio_test;
    
    #[tokio::test]
    async fn test_matrix_to_mycelium_translation() {
        let bridge = MatrixMyceliumBridge::new_test().await;
        
        let matrix_event = MatrixEvent {
            event_type: "m.room.message".to_string(),
            content: serde_json::json!({"body": "Hello"}),
            room_id: "!room:example.com".to_string(),
            sender: "@user:example.com".to_string(),
        };
        
        let mycelium_msg = bridge.translate_to_mycelium(&matrix_event).await?;
        
        assert_eq!(mycelium_msg.topic, "matrix.federation.event");
        assert!(mycelium_msg.payload.contains("Hello"));
    }
}
```

#### Frontend Tests
```typescript
// frontend/src/components/__tests__/ConnectionIndicator.test.tsx
import { render, screen } from '../../test-utils';
import { ConnectionIndicator } from '../ConnectionIndicator';

describe('ConnectionIndicator', () => {
  it('shows enhanced mode when Mycelium is connected', () => {
    render(<ConnectionIndicator type="enhanced" quality="excellent" />);
    
    expect(screen.getByText('Enhanced P2P Mode')).toBeInTheDocument();
    expect(screen.getByText('🔒')).toBeInTheDocument();
  });
  
  it('shows standard mode when using HTTPS', () => {
    render(<ConnectionIndicator type="standard" quality="good" />);
    
    expect(screen.getByText('Standard Web Mode')).toBeInTheDocument();
    expect(screen.getByText('🌐')).toBeInTheDocument();
  });
});
```

### Integration Testing

#### End-to-End Test Setup
```typescript
// tests/e2e/setup.ts
import { test as base, expect } from '@playwright/test';

export interface TestFixtures {
  matrixUser1: { username: string; password: string; accessToken: string };
  matrixUser2: { username: string; password: string; accessToken: string };
  myceliumNode: { publicKey: string; address: string };
}

export const test = base.extend<TestFixtures>({
  matrixUser1: async ({ page }, use) => {
    // Create test user
    const user = await createTestUser('user1');
    await use(user);
    // Cleanup
    await deleteTestUser(user.username);
  },
  
  myceliumNode: async ({ page }, use) => {
    // Start test Mycelium node
    const node = await startTestMyceliumNode();
    await use(node);
    // Cleanup
    await stopTestMyceliumNode(node);
  },
});

export { expect };
```

#### Message Flow Tests
```typescript
// tests/e2e/message-flow.test.ts
import { test, expect } from './setup';

test.describe('Message Flow', () => {
  test('users can send messages via standard connection', async ({ 
    page, 
    matrixUser1, 
    matrixUser2 
  }) => {
    // Login as user1
    await page.goto('/');
    await page.fill('[data-testid=username]', matrixUser1.username);
    await page.fill('[data-testid=password]', matrixUser1.password);
    await page.click('[data-testid=login]');
    
    // Send message
    await page.fill('[data-testid=message-input]', 'Hello from user1');
    await page.click('[data-testid=send-button]');
    
    // Verify message appears
    await expect(page.locator('[data-testid=message-list]'))
      .toContainText('Hello from user1');
  });
  
  test('enhanced users get P2P routing', async ({ 
    page, 
    matrixUser1, 
    myceliumNode 
  }) => {
    // Start with Mycelium node running
    await page.goto('/');
    
    // Should auto-detect enhanced mode
    await expect(page.locator('[data-testid=connection-status]'))
      .toContainText('Enhanced P2P Mode');
    
    // Connection indicator should show encrypted
    await expect(page.locator('[data-testid=connection-icon]'))
      .toContainText('🔒');
  });
});
```

## 🔧 Development Best Practices

### Code Style

#### Rust Formatting
```toml
# rustfmt.toml
max_width = 100
hard_tabs = false
tab_spaces = 4
newline_style = "Unix"
imports_granularity = "Crate"
group_imports = "StdExternalCrate"
```

#### TypeScript Configuration
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "allowJs": false,
    "skipLibCheck": true,
    "esModuleInterop": false,
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "forceConsistentCasingInFileNames": true,
    "module": "ESNext",
    "moduleResolution": "Node",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx"
  }
}
```

### Git Workflow

#### Branch Strategy
```bash
# Feature development
git checkout -b feature/mycelium-auto-detection
git commit -m "feat: add Mycelium auto-detection"

# Bug fixes
git checkout -b fix/connection-timeout
git commit -m "fix: handle connection timeout gracefully"

# Release preparation
git checkout -b release/v0.1.0
git commit -m "chore: prepare v0.1.0 release"
```

#### Commit Message Format
```
type(scope): description

[optional body]

[optional footer]
```

**Types**: feat, fix, docs, style, refactor, test, chore
**Scopes**: matrix, mycelium, ui, api, config

### Performance Monitoring

#### Backend Metrics
```rust
// backend/shared/monitoring/src/lib.rs
use prometheus::{Counter, Histogram, Registry};

pub struct Metrics {
    pub messages_sent: Counter,
    pub messages_received: Counter,
    pub federation_latency: Histogram,
    pub connection_count: prometheus::Gauge,
}

impl Metrics {
    pub fn new() -> Self {
        Self {
            messages_sent: Counter::new("messages_sent_total", "Total messages sent").unwrap(),
            messages_received: Counter::new("messages_received_total", "Total messages received").unwrap(),
            federation_latency: Histogram::with_opts(
                prometheus::HistogramOpts::new("federation_latency_seconds", "Federation latency")
                    .buckets(vec![0.1, 0.5, 1.0, 2.0, 5.0])
            ).unwrap(),
            connection_count: prometheus::Gauge::new("active_connections", "Active connections").unwrap(),
        }
    }
}
```

#### Frontend Performance
```typescript
// frontend/src/utils/performance.ts
export class PerformanceMonitor {
  private static instance: PerformanceMonitor;
  
  static getInstance(): PerformanceMonitor {
    if (!this.instance) {
      this.instance = new PerformanceMonitor();
    }
    return this.instance;
  }
  
  measureMessageDelivery(startTime: number) {
    const duration = performance.now() - startTime;
    console.log(`Message delivery took ${duration}ms`);
    
    // Send to analytics
    if (typeof gtag !== 'undefined') {
      gtag('event', 'message_delivery_time', {
        value: Math.round(duration),
        custom_parameter: 'frontend_performance'
      });
    }
  }
  
  measureConnectionSwitch(type: 'enhanced' | 'standard', startTime: number) {
    const duration = performance.now() - startTime;
    console.log(`Connection switch to ${type} took ${duration}ms`);
  }
}
```

This comprehensive development guide provides everything needed to set up, develop, and maintain the Mycelium-Matrix integration project.