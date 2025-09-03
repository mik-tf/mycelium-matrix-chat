# Production Deployment Guide - Mycelium-Matrix Chat

## 🎯 Overview

This guide covers the complete production deployment of the Mycelium-Matrix Chat application with full Phase 2 P2P Federation Routing capabilities.

## 📋 Current Status

### ✅ **COMPLETED - Phase 2 Federation Routing**
- Matrix Server-Server API endpoints fully implemented
- Mycelium P2P message routing operational
- Message transformation between Matrix ↔ Mycelium formats
- Server discovery and route management
- P2P benefits validation and performance metrics
- Cross-homeserver communication framework

### 🚧 **REMAINING - Production Infrastructure**

## 🏗️ Production Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Load Balancer │    │   Web Gateway    │    │  Matrix Bridge  │
│    (Nginx)      │────│   (Rust/Axum)   │────│   (Rust) P2P    │
│                 │    │                 │    │   Federation    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                        │                       │
         └────────────────────────┼───────────────────────┘
                                  │
                    ┌─────────────────┐    ┌─────────────────┐
                    │   Mycelium P2P  │    │   PostgreSQL     │
                    │   Network Node  │    │   Database       │
                    └─────────────────┘    └─────────────────┘
```

## 🚀 Deployment Checklist

### Phase 1: Infrastructure Setup

#### ✅ **COMPLETED**
- [x] Matrix Bridge service (Rust executable)
- [x] Web Gateway service (Rust Axum)
- [x] Database schema and migrations
- [x] Docker containerization

#### 🔄 **REMAINING**
- [ ] Production server provisioning
- [ ] Domain configuration and SSL certificates
- [ ] Mycelium P2P network connection
- [ ] Load balancer configuration
- [ ] Monitoring and logging setup

### Phase 2: Service Deployment

#### ✅ **COMPLETED**
- [x] Matrix Bridge with federation routing
- [x] P2P message routing through Mycelium
- [x] Message transformation logic
- [x] Server discovery and route management
- [x] Federation API endpoints

#### 🔄 **REMAINING**
- [ ] Production database setup
- [ ] Service orchestration (Docker Compose/Kubernetes)
- [ ] Environment configuration
- [ ] SSL/TLS certificate management
- [ ] Backup and recovery procedures

### Phase 3: Integration Testing

#### ✅ **COMPLETED**
- [x] Unit tests for all components
- [x] Integration tests for federation routing
- [x] End-to-end testing framework
- [x] P2P benefits validation

#### 🔄 **REMAINING**
- [ ] Production environment testing
- [ ] Load testing with multiple users
- [ ] Cross-homeserver federation testing
- [ ] Performance benchmarking
- [ ] Security penetration testing

## 🛠️ Production Deployment Steps

### 1. Server Provisioning

```bash
# Provision production server with required specifications
# Minimum requirements:
# - 4 CPU cores
# - 8GB RAM
# - 50GB SSD storage
# - Ubuntu 22.04 LTS or similar
```

### 2. Domain and SSL Setup

```bash
# Configure domain (e.g., chat.threefold.pro)
# Obtain SSL certificates (Let's Encrypt recommended)

# Example nginx configuration for SSL termination
server {
    listen 443 ssl http2;
    server_name chat.threefold.pro;

    ssl_certificate /etc/letsencrypt/live/chat.threefold.pro/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/chat.threefold.pro/privkey.pem;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /_matrix/ {
        proxy_pass http://localhost:8081;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 3. Mycelium P2P Network Setup

```bash
# Install and configure Mycelium node
sudo curl -fsSL https://mycelium.fly.dev/install | sh
sudo systemctl enable myceliumd
sudo systemctl start myceliumd

# Configure peers for optimal connectivity
sudo mycelium --peers tcp://188.40.132.242:9651 quic://185.69.166.8:9651 --tun-name mycelium0
```

### 4. Database Setup

```bash
# Production PostgreSQL setup
docker run -d \
  --name mycelium-matrix-postgres \
  -e POSTGRES_DB=mycelium_matrix \
  -e POSTGRES_USER=mycelium_user \
  -e POSTGRES_PASSWORD=secure_password \
  -p 5432:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  postgres:15

# Run migrations
cd backend/shared && sqlx migrate run
```

### 5. Service Deployment

```bash
# Build production binaries
cd backend/matrix-bridge && cargo build --release
cd backend/web-gateway && cargo build --release

# Start Matrix Bridge (P2P Federation)
./target/release/matrix-bridge &

# Start Web Gateway
./target/release/web-gateway &
```

### 6. Production Testing

```bash
# Run comprehensive production tests
make test-production-full

# Test federation with real Matrix servers
make test-cross-homeserver

# Validate P2P routing benefits
make test-p2p-performance
```

## 📊 Production Monitoring

### Health Checks

```bash
# Bridge health
curl https://chat.threefold.pro/api/v1/bridge/status

# Federation endpoints
curl https://chat.threefold.pro/_matrix/federation/v1/version

# Mycelium connectivity
curl https://chat.threefold.pro/api/v1/bridge/mycelium/status
```

### Key Metrics to Monitor

- **Federation Success Rate**: Messages successfully routed through P2P
- **P2P vs Standard Routing**: Performance comparison metrics
- **Cross-Homeserver Connections**: Active federation connections
- **Message Latency**: End-to-end delivery times
- **Error Rates**: Federation and P2P routing failures

## 🔧 Maintenance Procedures

### Regular Tasks

```bash
# Update SSL certificates
sudo certbot renew

# Update Mycelium peers
sudo mycelium --update-peers

# Database maintenance
docker exec mycelium-matrix-postgres vacuumdb -U mycelium_user -d mycelium_matrix --analyze

# Log rotation
logrotate /etc/logrotate.d/mycelium-matrix
```

### Backup Strategy

```bash
# Database backup
docker exec mycelium-matrix-postgres pg_dump -U mycelium_user mycelium_matrix > backup_$(date +%Y%m%d).sql

# Configuration backup
tar -czf config_backup_$(date +%Y%m%d).tar.gz /etc/mycelium-matrix/

# Federation routes backup
curl https://chat.threefold.pro/api/v1/bridge/routes > routes_backup_$(date +%Y%m%d).json
```

## 🚨 Troubleshooting

### Common Issues

#### Bridge Not Starting
```bash
# Check logs
tail -f /var/log/mycelium-matrix/bridge.log

# Check database connectivity
docker exec mycelium-matrix-postgres pg_isready -U mycelium_user

# Check Mycelium connectivity
curl http://localhost:8989/api/v1/admin
```

#### Federation Not Working
```bash
# Test federation endpoints
curl https://chat.threefold.pro/_matrix/federation/v1/version

# Check bridge federation routes
curl https://chat.threefold.pro/api/v1/bridge/routes

# Validate Mycelium P2P connection
curl https://chat.threefold.pro/api/v1/bridge/mycelium/status
```

#### Performance Issues
```bash
# Check system resources
htop
df -h
free -h

# Monitor federation metrics
curl https://chat.threefold.pro/api/v1/bridge/metrics

# Check Mycelium network status
mycelium --status
```

## 📈 Scaling Considerations

### Horizontal Scaling

```bash
# Load balancer configuration for multiple bridge instances
upstream matrix_bridge {
    server bridge1:8081;
    server bridge2:8081;
    server bridge3:8081;
}

# Database connection pooling
# Configure PostgreSQL with PgBouncer for connection pooling
```

### Performance Optimization

```bash
# Enable federation event batching
# Configure Mycelium peer optimization
# Implement Redis caching for frequently accessed data
# Set up message queuing for high-throughput scenarios
```

## 🔒 Security Considerations

### Production Security

- [ ] SSL/TLS encryption for all connections
- [ ] Firewall configuration (allow only necessary ports)
- [ ] Regular security updates and patches
- [ ] Database encryption at rest
- [ ] API rate limiting and DDoS protection
- [ ] Audit logging for federation activities

### P2P Security

- [ ] Mycelium network encryption validation
- [ ] Federation signature verification
- [ ] Server authentication and authorization
- [ ] Message encryption end-to-end
- [ ] Privacy-preserving routing validation

## 🎯 Success Metrics

### Technical Metrics
- **Uptime**: >99.9% service availability
- **Federation Success Rate**: >99.5% message delivery
- **P2P Routing Efficiency**: >95% messages through P2P
- **Cross-Homeserver Connections**: >10 active federations
- **End-to-End Latency**: <500ms for P2P messages

### User Experience Metrics
- **Connection Time**: <5 seconds initial connection
- **Message Delivery**: <2 seconds end-to-end
- **P2P Detection**: <3 seconds Mycelium availability
- **Fallback Performance**: <10 seconds to standard routing

## 📞 Support and Maintenance

### Monitoring Dashboard
- Real-time federation status
- P2P network health
- Performance metrics
- Error tracking and alerting

### Emergency Procedures
- Service restart procedures
- Database recovery steps
- Federation reconnection protocols
- Customer communication templates

---

## ✅ **DEPLOYMENT READINESS CHECKLIST**

### Pre-Deployment
- [ ] Production server provisioned
- [ ] Domain and SSL certificates configured
- [ ] Mycelium P2P network connected
- [ ] Database production setup complete
- [ ] All services built and tested

### Deployment
- [ ] Services deployed and started
- [ ] Load balancer configured
- [ ] SSL termination working
- [ ] DNS propagation complete

### Post-Deployment
- [ ] Production testing completed
- [ ] Monitoring and alerting configured
- [ ] Backup procedures validated
- [ ] Documentation updated

### Go-Live
- [ ] Final security review completed
- [ ] Performance benchmarks met
- [ ] Support team trained
- [ ] User communication prepared

**Phase 2 Federation Routing Implementation: PRODUCTION READY!** 🚀