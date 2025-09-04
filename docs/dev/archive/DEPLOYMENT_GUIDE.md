# Deployment Guide

## 🚀 Deployment Overview

This guide covers deploying the Mycelium-Matrix integration in various environments, from development to production scale.

## 📋 Prerequisites

### System Requirements

#### Minimum Requirements
- **CPU**: 2 cores
- **RAM**: 4GB
- **Storage**: 20GB SSD
- **Network**: 100 Mbps with IPv6 support
- **OS**: Linux (Ubuntu 20.04+ recommended), macOS, or Windows

#### Recommended Production Requirements
- **CPU**: 4+ cores
- **RAM**: 8GB+
- **Storage**: 100GB+ SSD
- **Network**: 1 Gbps with IPv6 support
- **OS**: Linux with container runtime

#### Software Dependencies
```bash
# Required
- Docker 24.0+
- Docker Compose 2.0+
- Git

# Optional but recommended
- Kubernetes 1.25+ (for cluster deployment)
- Helm 3.0+ (for Kubernetes deployments)
- Nginx or Traefik (for reverse proxy)
- PostgreSQL 14+ (external database)
- Redis 7.0+ (for caching)
```

## 🐳 Docker Deployment

### Single Node Deployment

#### 1. Quick Start with Docker Compose
```bash
# Clone repository
git clone https://github.com/mik-tf/mycelium-matrix-chat.git
cd mycelium-matrix-chat

# Copy environment configuration
cp .env.example .env.production
vim .env.production  # Edit configuration

# Start services
docker-compose -f docker-compose.prod.yml up -d

# Verify deployment
curl https://chat.projectmycelium.org/api/v1/health
```

#### 2. Docker Compose Configuration
```yaml
# docker-compose.prod.yml
version: '3.8'

services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: mycelium_matrix
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./migrations:/docker-entrypoint-initdb.d
    networks:
      - backend

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - backend

  mycelium-node:
    image: threefoldtech/mycelium:latest
    command: |
      mycelium --config /etc/mycelium/config.toml
      --peers tcp://188.40.132.242:9651
      --api-addr 0.0.0.0:8989
    volumes:
      - ./config/mycelium.toml:/etc/mycelium/config.toml
      - mycelium_data:/var/lib/mycelium
    ports:
      - "9651:9651"
      - "8989:8989"
    networks:
      - backend
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun

  matrix-bridge:
    build: 
      context: ./backend/matrix-bridge
      dockerfile: Dockerfile.prod
    environment:
      DATABASE_URL: postgresql://${DB_USER}:${DB_PASSWORD}@postgres/mycelium_matrix
      REDIS_URL: redis://redis:6379
      MYCELIUM_API_URL: http://mycelium-node:8989
      RUST_LOG: info
    depends_on:
      - postgres
      - redis
      - mycelium-node
    networks:
      - backend

  web-gateway:
    build:
      context: ./backend/web-gateway
      dockerfile: Dockerfile.prod
    environment:
      MATRIX_BRIDGE_URL: http://matrix-bridge:8080
      FRONTEND_URL: http://frontend:3000
    ports:
      - "8080:8080"
    depends_on:
      - matrix-bridge
    networks:
      - backend
      - frontend

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.prod
      args:
        REACT_APP_API_BASE_URL: https://chat.projectmycelium.org
        REACT_APP_MATRIX_BASE_URL: https://chat.projectmycelium.org
    networks:
      - frontend

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
    depends_on:
      - web-gateway
      - frontend
    networks:
      - frontend

networks:
  backend:
    driver: bridge
  frontend:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
  mycelium_data:
```

#### 3. Environment Configuration
```bash
# .env.production
# Database Configuration
DB_HOST=postgres
DB_PORT=5432
DB_NAME=mycelium_matrix
DB_USER=mycelium_user
DB_PASSWORD=secure_password_here

# Redis Configuration
REDIS_URL=redis://redis:6379

# Mycelium Configuration
MYCELIUM_PRIVATE_KEY_PATH=/var/lib/mycelium/private_key.bin
MYCELIUM_PEERS=tcp://188.40.132.242:9651,quic://185.69.166.8:9651

# Matrix Configuration
MATRIX_SERVER_NAME=chat.projectmycelium.org
MATRIX_REGISTRATION_SHARED_SECRET=very_secure_secret_here

# Web Configuration
DOMAIN=chat.projectmycelium.org
ENABLE_HTTPS=true
SSL_CERT_PATH=/etc/nginx/ssl/cert.pem
SSL_KEY_PATH=/etc/nginx/ssl/key.pem

# Security
JWT_SECRET=jwt_secret_key_here
API_KEY=api_key_for_internal_services

# Monitoring
ENABLE_METRICS=true
PROMETHEUS_PORT=9090
```

### Multi-Node Deployment

#### High Availability Setup
```yaml
# docker-compose.ha.yml
version: '3.8'

services:
  # Load balancer
  haproxy:
    image: haproxy:2.8
    ports:
      - "80:80"
      - "443:443"
      - "8404:8404"  # Stats page
    volumes:
      - ./config/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg
      - ./ssl:/etc/ssl/certs
    networks:
      - frontend

  # Multiple gateway instances
  web-gateway-1:
    extends:
      file: docker-compose.prod.yml
      service: web-gateway
    networks:
      - backend
      - frontend

  web-gateway-2:
    extends:
      file: docker-compose.prod.yml
      service: web-gateway
    networks:
      - backend
      - frontend

  # Multiple bridge instances
  matrix-bridge-1:
    extends:
      file: docker-compose.prod.yml
      service: matrix-bridge
    networks:
      - backend

  matrix-bridge-2:
    extends:
      file: docker-compose.prod.yml
      service: matrix-bridge
    networks:
      - backend

  # Multiple Mycelium nodes
  mycelium-node-1:
    extends:
      file: docker-compose.prod.yml
      service: mycelium-node
    volumes:
      - ./config/mycelium-1.toml:/etc/mycelium/config.toml
      - mycelium_data_1:/var/lib/mycelium

  mycelium-node-2:
    extends:
      file: docker-compose.prod.yml
      service: mycelium-node
    volumes:
      - ./config/mycelium-2.toml:/etc/mycelium/config.toml
      - mycelium_data_2:/var/lib/mycelium

  # External database (production)
  postgres-primary:
    image: postgres:15
    environment:
      POSTGRES_REPLICATION_MODE: master
      POSTGRES_REPLICATION_USER: replicator
      POSTGRES_REPLICATION_PASSWORD: replication_password
    volumes:
      - postgres_primary_data:/var/lib/postgresql/data

  postgres-replica:
    image: postgres:15
    environment:
      POSTGRES_REPLICATION_MODE: slave
      POSTGRES_REPLICATION_USER: replicator
      POSTGRES_REPLICATION_PASSWORD: replication_password
      POSTGRES_MASTER_SERVICE: postgres-primary
    depends_on:
      - postgres-primary

volumes:
  postgres_primary_data:
  mycelium_data_1:
  mycelium_data_2:
```

## ☸️ Kubernetes Deployment

### Helm Chart Structure
```
helm/mycelium-matrix/
├── Chart.yaml
├── values.yaml
├── values-production.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   └── hpa.yaml
└── charts/
    ├── postgresql/
    ├── redis/
    └── mycelium/
```

#### Chart.yaml
```yaml
apiVersion: v2
name: mycelium-matrix
description: Mycelium-Matrix Chat Integration
type: application
version: 0.1.0
appVersion: "0.1.0"

dependencies:
  - name: postgresql
    version: 12.1.2
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled
  
  - name: redis
    version: 17.4.3
    repository: https://charts.bitnami.com/bitnami
    condition: redis.enabled
```

#### Deployment Configuration
```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mycelium-matrix.fullname" . }}-bridge
  labels:
    {{- include "mycelium-matrix.labels" . | nindent 4 }}
    app.kubernetes.io/component: bridge
spec:
  replicas: {{ .Values.bridge.replicaCount }}
  selector:
    matchLabels:
      {{- include "mycelium-matrix.selectorLabels" . | nindent 6 }}
      app.kubernetes.io/component: bridge
  template:
    metadata:
      labels:
        {{- include "mycelium-matrix.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: bridge
    spec:
      containers:
      - name: matrix-bridge
        image: "{{ .Values.bridge.image.repository }}:{{ .Values.bridge.image.tag }}"
        imagePullPolicy: {{ .Values.bridge.image.pullPolicy }}
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: {{ include "mycelium-matrix.secretName" . }}
              key: database-url
        - name: REDIS_URL
          value: "redis://{{ include "mycelium-matrix.redis.fullname" . }}-master:6379"
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          {{- toYaml .Values.bridge.resources | nindent 12 }}
```

#### Production Values
```yaml
# values-production.yaml
replicaCount: 3

image:
  repository: mycelium-matrix/bridge
  pullPolicy: IfNotPresent
  tag: "0.1.0"

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  hosts:
    - host: chat.projectmycelium.org
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: chat-mycelium-com-tls
      hosts:
        - chat.projectmycelium.org

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

postgresql:
  enabled: true
  auth:
    database: mycelium_matrix
    username: mycelium_user
  primary:
    persistence:
      enabled: true
      size: 100Gi
      storageClass: "fast-ssd"

redis:
  enabled: true
  auth:
    enabled: false
  master:
    persistence:
      enabled: true
      size: 10Gi

mycelium:
  replicaCount: 2
  image:
    repository: threefoldtech/mycelium
    tag: "latest"
  config:
    peers:
      - tcp://188.40.132.242:9651
      - quic://185.69.166.8:9651
    apiAddr: "0.0.0.0:8989"
  persistence:
    enabled: true
    size: 10Gi
```

#### Deployment Commands
```bash
# Add Helm repositories
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Create namespace
kubectl create namespace mycelium-matrix

# Install with Helm
helm install mycelium-matrix ./helm/mycelium-matrix \
  --namespace mycelium-matrix \
  --values helm/mycelium-matrix/values-production.yaml

# Upgrade deployment
helm upgrade mycelium-matrix ./helm/mycelium-matrix \
  --namespace mycelium-matrix \
  --values helm/mycelium-matrix/values-production.yaml

# Check deployment status
kubectl get pods -n mycelium-matrix
kubectl get services -n mycelium-matrix
kubectl get ingress -n mycelium-matrix
```

## 🔧 Configuration Management

### Mycelium Node Configuration
```toml
# config/mycelium.toml
[network]
# Network name for private network (optional)
# network_name = "mycelium-matrix"

# Pre-shared key for private network (optional)
# network_key = "base64_encoded_key_here"

# Listen address for incoming connections
listen_addr = "0.0.0.0:9651"

# Peers to connect to
peers = [
    "tcp://188.40.132.242:9651",
    "quic://185.69.166.8:9651",
    "tcp://185.69.166.7:9651",
    "quic://65.21.231.58:9651"
]

[api]
# API server listen address
listen_addr = "0.0.0.0:8989"

# Enable message subsystem
enable_message_api = true

[logging]
level = "info"
format = "json"

[storage]
# Private key storage path
private_key_path = "/var/lib/mycelium/private_key.bin"

# Node database path
database_path = "/var/lib/mycelium/node.db"
```

### Matrix Bridge Configuration
```rust
// config/bridge.toml
[server]
listen_addr = "0.0.0.0:8080"
workers = 4

[matrix]
server_name = "chat.projectmycelium.org"
registration_shared_secret = "very_secure_secret"
database_url = "postgresql://user:pass@localhost/synapse"

[mycelium]
api_url = "http://localhost:8989"
message_timeout_ms = 30000
max_retries = 3

[federation]
# Topic configuration for Matrix federation events
[federation.topics]
"matrix.federation.invite" = { timeout_ms = 10000, max_size_bytes = 1048576 }
"matrix.federation.join" = { timeout_ms = 15000, max_size_bytes = 1048576 }
"matrix.federation.leave" = { timeout_ms = 5000, max_size_bytes = 1048576 }
"matrix.federation.event" = { timeout_ms = 30000, max_size_bytes = 10485760 }
"matrix.federation.state" = { timeout_ms = 60000, max_size_bytes = 10485760 }

[security]
# Rate limiting
rate_limit_per_second = 100
rate_limit_burst = 200

# Message validation
max_message_size_bytes = 10485760
validate_signatures = true

[caching]
# Redis configuration for caching
redis_url = "redis://localhost:6379"
cache_ttl_seconds = 3600

# Cache sizes
room_state_cache_size = 1000
server_key_cache_size = 10000
```

### Nginx Configuration
```nginx
# config/nginx.conf
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=matrix:10m rate=30r/s;

    # Upstream servers
    upstream web_gateway {
        least_conn;
        server web-gateway-1:8080;
        server web-gateway-2:8080;
    }

    upstream frontend {
        least_conn;
        server frontend-1:3000;
        server frontend-2:3000;
    }

    # HTTPS redirect
    server {
        listen 80;
        server_name chat.projectmycelium.org;
        return 301 https://$server_name$request_uri;
    }

    # Main server block
    server {
        listen 443 ssl http2;
        server_name chat.projectmycelium.org;

        # SSL configuration
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305;
        ssl_prefer_server_ciphers off;

        # Security headers
        add_header Strict-Transport-Security "max-age=63072000" always;
        add_header X-Frame-Options DENY always;
        add_header X-Content-Type-Options nosniff always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        # Frontend (React app)
        location / {
            proxy_pass http://frontend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Handle client-side routing
            try_files $uri $uri/ /index.html;
        }

        # API endpoints
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            
            proxy_pass http://web_gateway;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Timeouts
            proxy_connect_timeout 5s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # Matrix federation
        location /_matrix/ {
            limit_req zone=matrix burst=50 nodelay;
            
            proxy_pass http://web_gateway;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Matrix-specific timeouts
            proxy_connect_timeout 10s;
            proxy_send_timeout 120s;
            proxy_read_timeout 120s;
        }

        # WebSocket support for Matrix sync
        location /_matrix/client/r0/sync {
            proxy_pass http://web_gateway;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Long polling support
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
        }

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
```

## 📊 Monitoring & Observability

### Prometheus Configuration
```yaml
# config/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: 'mycelium-matrix-bridge'
    static_configs:
      - targets: ['matrix-bridge:8080']
    metrics_path: /metrics
    scrape_interval: 10s

  - job_name: 'mycelium-node'
    static_configs:
      - targets: ['mycelium-node:8989']
    metrics_path: /metrics
    scrape_interval: 30s

  - job_name: 'web-gateway'
    static_configs:
      - targets: ['web-gateway:8080']
    metrics_path: /metrics
    scrape_interval: 10s

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
```

### Grafana Dashboard
```json
{
  "dashboard": {
    "title": "Mycelium-Matrix Monitoring",
    "panels": [
      {
        "title": "Message Delivery Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(messages_sent_total[5m])",
            "legendFormat": "Messages Sent/sec"
          },
          {
            "expr": "rate(messages_received_total[5m])",
            "legendFormat": "Messages Received/sec"
          }
        ]
      },
      {
        "title": "Federation Latency",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(federation_latency_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          },
          {
            "expr": "histogram_quantile(0.50, rate(federation_latency_seconds_bucket[5m]))",
            "legendFormat": "Median"
          }
        ]
      },
      {
        "title": "Active Connections",
        "type": "singlestat",
        "targets": [
          {
            "expr": "active_connections",
            "legendFormat": "Connections"
          }
        ]
      }
    ]
  }
}
```

## 🔒 Security Hardening

### SSL/TLS Certificate Management
```bash
# Generate certificates with Let's Encrypt
certbot certonly --nginx \
  --email admin@mycelium.com \
  --agree-tos \
  --no-eff-email \
  -d chat.projectmycelium.org

# Auto-renewal with cron
echo "0 12 * * * /usr/bin/certbot renew --quiet" | crontab -
```

### Firewall Configuration
```bash
# UFW firewall rules
ufw default deny incoming
ufw default allow outgoing

# SSH access
ufw allow 22/tcp

# HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Mycelium P2P
ufw allow 9651/tcp
ufw allow 9651/udp

# Enable firewall
ufw enable
```

### Database Security
```sql
-- Create dedicated database user
CREATE USER mycelium_user WITH ENCRYPTED PASSWORD 'secure_password';
CREATE DATABASE mycelium_matrix OWNER mycelium_user;

-- Grant minimal required permissions
GRANT CONNECT ON DATABASE mycelium_matrix TO mycelium_user;
GRANT USAGE ON SCHEMA public TO mycelium_user;
GRANT CREATE ON SCHEMA public TO mycelium_user;

-- Revoke public access
REVOKE ALL ON DATABASE mycelium_matrix FROM public;
```

## 🧪 Deployment Testing

### Health Check Scripts
```bash
#!/bin/bash
# scripts/health-check.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

BASE_URL="${1:-https://chat.projectmycelium.org}"

echo "Running health checks for $BASE_URL"

# Check web frontend
echo -n "Frontend health: "
if curl -f -s "$BASE_URL/health" >/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

# Check API endpoints
echo -n "API health: "
if curl -f -s "$BASE_URL/api/v1/health" >/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

# Check Matrix federation
echo -n "Matrix federation: "
if curl -f -s "$BASE_URL/_matrix/federation/v1/version" >/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

# Check Mycelium connectivity
echo -n "Mycelium node: "
if curl -f -s "http://localhost:8989/api/v1/admin" >/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}WARNING${NC} (Mycelium not accessible)"
fi

echo "All health checks passed!"
```

### Load Testing
```bash
#!/bin/bash
# scripts/load-test.sh

# Install k6 if not present
if ! command -v k6 &> /dev/null; then
    echo "Installing k6..."
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
    echo "deb https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
    sudo apt-get update
    sudo apt-get install k6
fi

# Run load test
k6 run --vus 50 --duration 5m tests/load-test.js
```

```javascript
// tests/load-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  vus: 50,
  duration: '5m',
  thresholds: {
    http_req_duration: ['p(95)<2000'], // 95% of requests under 2s
    http_req_failed: ['rate<0.1'],     // Error rate under 10%
  },
};

export default function() {
  // Test frontend
  let response = http.get('https://chat.projectmycelium.org');
  check(response, {
    'frontend status is 200': (r) => r.status === 200,
    'frontend loads quickly': (r) => r.timings.duration < 1000,
  });

  // Test API health
  response = http.get('https://chat.projectmycelium.org/api/v1/health');
  check(response, {
    'API health status is 200': (r) => r.status === 200,
  });

  // Test Matrix endpoint
  response = http.get('https://chat.projectmycelium.org/_matrix/federation/v1/version');
  check(response, {
    'Matrix federation accessible': (r) => r.status === 200,
  });

  sleep(1);
}
```

This comprehensive deployment guide provides everything needed to deploy the Mycelium-Matrix integration from development to production scale across various environments.