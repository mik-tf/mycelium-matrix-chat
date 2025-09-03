# Phase 2: Mycelium Bridge Integration - Deployment Guide

## 🚀 Phase 2 Deployment Overview

Phase 2 focuses on Mycelium P2P enhancement with Matrix federation routing, providing both Web users (standard HTTPS) and Mycelium-powered users (P2P routing).

### 📋 Phase 2 MVP Goals
- Deploy Matrix Bridge service on local 8081 and production
- Implement Mycelium JavaScript client library in frontend
- Add automatic Mycelium detection and progressive enhancement logic
- Test real-world Matrix federation with matrix.org
- Expand testing infrastructure for P2P features

## 🏗️ Quick Phase 2 Setup

### Pre-deployment Checklist
- [ ] Phase 1 MVP deployed and running: `https://chat.threefold.pro`
- [ ] All production configs prepared (see Phase 1 setup)
- [ ] Mycelium integration prepared
- [ ] SSL certificates active (via Let's Encrypt)

### Option A: Quick Local Setup (Development)
```bash
# Set up Matrix Bridge + Mycelium on localhost:8081
make setup-phase2-local

# Bridge will run on localhost:8081
# Frontend (localhost:5173) will auto-detect Mycelium
```

### Option B: Production Deployment
```bash
# Deploy complete Phase 2 to chat.threefold.pro
make setup-phase2-prod

# Or manual deployment:
chmod +x deploy.sh
sudo ./deploy.sh
```

## 🔧 Phase 2 Components Setup

### 1. Matrix Bridge Service
- **Port**: 8081 (local), 8080 (production via Nginx proxy)
- **Purpose**: Translates Matrix federation events to Mycelium overlay
- **Connection**: Connects to matrix.org + local Mycelium nodes

### 2. Mycelium Node Integration
- **Purpose**: P2P routing for enhanced users
- **Nodes**: Pre-configured peers (188.40.132.242:9651, 185.69.166.8:9651)
- **Client**: JavaScript lib for browser P2P connections

### 3. Progressive Enhancement
- **Auto-detection**: Browser checks for Mycelium compatibility
- **Fallback**: Standard Matrix routing for non-Mycelium users
- **UI indicators**: Show connection type and routing status

## 🐳 Phase 2 Docker Setup

### Production Services (Phase 2)
```yaml
# Add to docker-compose.prod.yml:
services:
  matrix-bridge:     # ⚡ NEW in Phase 2
    image: mycelium-matrix/bridge:v2
    ports:
      - "8080:8080"
    depends_on:
      - postgres
      - mycelium-node

  mycelium-node:     # ⚡ NEW in Phase 2
    image: threefoldtech/mycelium:latest
    ports:
      - "9651:9651/udp"
      - "8989:8989"
    cap_add: [NET_ADMIN]
    devices: [/dev/net/tun]
```

## 🧪 Phase 2 Testing & Verification

### Basic Connectivity Tests
```bash
# Test Matrix Bridge API
make test-bridge

# Test Mycelium connectivity
make test-mycelium

# Test federation routing
make test-federation
```

### End-to-End User Testing

#### For Media users (Standard HTTPS):
1. Open `https://chat.threefold.pro`
2. Login with `@user:matrix.org`
3. Create/join rooms normally
4. ✅ Should work without Mycelium (fallback routing)

#### For Mycelium users (Enhanced P2P):
1. User has Mycelium installed/configured
2. Open `https://chat.threefold.pro`
3. Login flow should auto-detect Mycelium
4. ✅ Messages route through P2P overlay
5. ✅ UI shows "Enhanced Connection" status

### Federation Testing
```bash
# Test real Matrix federation
make test-matrix-org

# Cross-homeserver routing
# 1. User A on mycelium-chat.threefold.pro
# 2. User B on matrix.example.com
# 3. Messages should route through Matrix federation + Mycelium overlay
```

## 📊.Poduction Monitoring

### Health Checks (Phase 2)
```bash
# Bridge health
curl https://chat.threefold.pro/api/bridge/health

# Mycelium node health
curl https://chat.threefold.pro/api/mycelium/status

# Federation status
curl https://chat.threefold.pro/api/matrix/federation/status
```

### Logging & Troubleshooting
```bash
# View Phase 2 service logs
make logs-phase2

# Check bridge federation events
make logs-federation

# Monitor Mycelium connections
make logs-mycelium
```

## 🔧 Troubleshooting Guide

### Common Issues

#### Matrix Bridge Not Starting
```bash
# Check bridge logs
docker-compose -f docker/docker-compose.prod.yml logs matrix-bridge

# Verify Mycelium connection
curl -i http://localhost:8989/api/v1/health

# Check Matrix server connectivity
curl -i https://matrix.org/_matrix/federation/v1/version
```

#### Mycelium Not Connecting
```bash
# Test local Mycelium node
curl -i http://localhost:8989/api/v1/admin

# Check peering table
curl -i http://localhost:8989/api/v1/peers

# Restart Mycelium node
docker-compose -f docker/docker-compose.prod.yml restart mycelium-node
```

#### Progressive Enhancement Failing
```bash
# Check frontend Mycelium detection
curl https://chat.threefold.pro/api/mycelium/detect

# Test client-side Mycelium lib
make test-frontend-mycelium

# Verify API keys and endpoints
# See docs/ops/phase-2-deploy.md for full steps
```

## 📈 Phase 2 Success Criteria

### Minimum Viable Enhancements
- [x] Matrix Bridge service running (localhost:8081)
- [ ] Mycelium client library integrated
- [ ] Auto-detection working in browser
- [ ] Matrix federation routes through Mycelium
- [ ] Progressive enhancement fallback functional
- [ ] Production deployment stable

### Performance Benchmarks
- Bridge latency: <50ms for local routing
- Mycelium connection time: <10s
- Message delivery rate: >99.9% success
- Federation compatibility: matrix.org integration

## 🚀 Next Steps After Phase 2

Once Phase 2 is stable:
1. **Mobile App Development**: React Native with embedded Mycelium
2. **Advanced P2P Features**: Mesh networking, file sharing
3. **Community Launch**: User registration and marketing
4. **Production Scaling**: Kubernetes deployment, monitoring

---

## 📋 Quick Reference

```bash
# Setup & Testing
make setup-phase2-local    # Local development
make setup-phase2-prod     # Production deployment
make test-phase2           # Complete testing suite

# Service URLs
Frontend:    https://chat.threefold.pro
Bridge API:  https://chat.threefold.pro/api/bridge
Mycelium:    https://chat.threefold.pro/api/mycelium
Matrix Bridge: http://localhost:8081 (local dev)

# Logs & Debugging
make logs-phase2
make debug-matrix
make debug-mycelium
```

Documentation updated for Phase 2 Mycelium bridge integration and deployment.
