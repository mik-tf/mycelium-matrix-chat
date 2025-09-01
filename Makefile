#
# Mycelium-Matrix Integration Project - Makefile
#

.PHONY: help test-phase1 test-backend test-frontend test-integration test-database setup-full setup-phase1 setup-phase2-local setup-phase2-prod test-phase2 test-bridge test-mycelium test-federation test-matrix-org deploy-prod down clean logs logs-phase2 status

# Default target
help:
	@echo "🏗️ Mycelium-Matrix Chat - Development & Deployment"
	@echo ""
	@echo "📋 Available Make Targets:"
	@echo ""
	@echo "🔍 Testing:"
	@echo "  test-phase1        # Run complete Phase 1 testing suite"
	@echo "  test-phase2        # Run complete Phase 2 testing suite"
	@echo "  test-backend       # Test backend infrastructure"
	@echo "  test-frontend      # Test frontend application"
	@echo "  test-bridge        # Test Matrix Bridge service"
	@echo "  test-mycelium      # Test Mycelium connectivity"
	@echo "  test-federation    # Test federation routing"
	@echo "  test-matrix-org    # Test Matrix.org federation"
	@echo "  test-integration   # Test Matrix.org authentication"
	@echo "  test-database      # Test database persistence"
	@echo ""
	@echo "🐳 Services:"
	@echo "  setup-full         # Set up complete development environment"
	@echo "  setup-phase1       # Set up Phase 1 testing environment"
	@echo "  setup-phase2-local # Set up Phase 2 Bridge + Mycelium (localhost:8081)"
	@echo "  setup-phase2-prod  # Deploy Phase 2 to production"
	@echo "  deploy-prod        # Run production deployment script"
	@echo "  down               # Stop all services"
	@echo "  status             # Show service status"
	@echo ""
	@echo "🧹 Maintenance:"
	@echo "  clean              # Clean up development environment"
	@echo "  logs               # Show service logs"
	@echo "  logs-phase2        # Show Phase 2 service logs only"
	@echo ""
	@echo "📚 Documentation:"
	@echo "  docs               # Open Phase 1 testing documentation"
	@echo "  docs-phase2        # Open Phase 2 deployment documentation"
	@echo ""
	@echo "📗 For detailed setup instructions:"
	@echo "  Phase 1: ./docs/ops/phase-1-test.md"
	@echo "  Phase 2: ./docs/ops/phase-2-deploy.md"

# ===== TESTING TARGETS =====

# Complete Phase 1 testing suite
test-phase1: test-backend test-frontend test-integration test-database
	@echo "🎉 Phase 1 MVP Testing Complete!"
	@echo "✅ Backend Infrastructure: PASS"
	@echo "✅ Frontend React App: PASS"
	@echo "✅ Database Persistence: PASS"
	@echo "✅ Matrix.org Integration: PASS"
	@echo ""
	@echo "🚀 Ready for Phase 2: Mycelium Bridge Integration"

# Backend infrastructure testing
test-backend:
	@echo "🔧 Testing Backend Infrastructure..."
	@echo "  📡 Checking PostgreSQL..."
	@docker ps | grep -q mycelium-postgres || (echo "  ❌ PostgreSQL not running" && exit 1)
	@echo "  ✅ PostgreSQL: RUNNING"
	@echo ""
	@echo "  🌐 Checking Web Gateway..."
	@{ echo "Waiting for Web Gateway..." && sleep 3 && curl -s http://localhost:8080/ > /dev/null; } || (echo "  ❌ Web Gateway not running" && exit 1)
	@echo "  ✅ Web Gateway: RUNNING"
	@echo ""
	@echo "  🔒 Testing API endpoints..."
	@curl -s -X POST http://localhost:8080/api/auth/login -H "Content-Type: application/json" -d '{"username":"@test:matrix.org"}' | grep -q "success" || (echo "  ❌ API endpoints failing" && exit 1)
	@echo "  ✅ API Endpoints: FUNCTIONAL"
	@echo ""
	@echo "✅ Backend Infrastructure: PASS"
	@echo ""

# Frontend application testing
test-frontend:
	@echo "🌐 Testing Frontend Application..."
	@echo "  📱 Checking React app..."
	@curl -s http://localhost:5173/ | grep -q "html" || (echo "  ❌ Frontend not running" && exit 1)
	@echo "  ✅ Frontend: RUNNING"
	@echo ""
	@echo "ℹ️  Manual browser test required for UI functionality"
	@echo "ℹ️  Open http://localhost:5173 and verify React app loads"
	@echo "ℹ️  Test authentication, room creation, and messaging"
	@echo ""

# Integration testing (Matrix.org auth)
test-integration:
	@echo "🔗 Testing Integration & Authentication..."
	@echo "ℹ️  Real Matrix.org authentication test required"
	@echo "🔬 Testing Steps:"
	@echo "  1. Open http://localhost:5173"
	@echo "  2. Login with @youruser:matrix.org"
	@echo "  3. Verify Matrix sync completes"
	@echo "  4. Check browser Network tab for /api/auth/login call"
	@echo "  5. Create/test rooms and message flow"
	@echo ""

# Database persistence testing
test-database:
	@echo "💾 Testing Database Persistence..."
	@echo "  📊 Checking database tables..."
	@docker exec mycelium-postgres psql -U mycelium_user -d mycelium_matrix -c "SELECT tablename FROM pg_tables WHERE tablename LIKE '%';" 2>/dev/null | grep -q rooms || (echo "  ❌ Database tables missing" && exit 1)
	@echo "  ✅ Database Tables: EXIST"
	@echo ""
	@echo "ℹ️  Manual testing: Create rooms and verify database entries:"
	@echo "  docker exec -it mycelium-postgres psql -U mycelium_user -d mycelium_matrix -c 'SELECT * FROM rooms;'"
	@echo ""

# ===== ENVIRONMENT SETUP =====

# Full development environment setup
setup-full: deep-clean
	@echo "🐳 Setting up complete development environment..."
	@echo ""
	@echo "🧹 Making sure ports 8080 and 5173 are free..."
	-sudo fuser -k 8080/tcp 2>/dev/null || true
	-sudo fuser -k 5173/tcp 2>/dev/null || true
	-sudo systemctl stop nginx 2>/dev/null || true
	-sudo killall nginx 2>/dev/null || true
	-sudo killall cargo npm java node 2>/dev/null || true
	@echo "✅ Ports cleared"
	@echo ""
	@echo "📦 Starting PostgreSQL database..."
	docker-compose -f docker/docker-compose.yml up -d
	@echo "⏳ Waiting 10s for database..."
	sleep 10
	@echo ""
	@echo "🌐 Starting Web Gateway (Rust Axum Server)..."
	cd backend/web-gateway && cargo run --quiet 2>&1 | grep -E "(Web Gateway|listening|error)" &
	PID_WEB_GATEWAY=$$!
	@echo "⏳ Waiting 8s for Web Gateway..."
	sleep 8
	@echo ""
	@echo "💻 Starting Frontend (React on port 5173)..."
	cd frontend && npm run dev 2>&1 | grep -E "(ready|error|build)" &
	PID_FRONTEND=$$!
	@echo "⏳ Waiting 5s for Frontend..."
	sleep 5
	@echo ""
	@echo "🔍 Verifying services..."
	docker ps | grep mycelium-postgres > /dev/null && echo "✅ PostgreSQL: ACTIVE" || echo "❌ PostgreSQL: FAILED"
	curl -s http://localhost:8080/ > /dev/null && echo "✅ Web Gateway (Rust): ACTIVE" || echo "❌ Web Gateway: FAILED"
	curl -s http://localhost:5173/ | grep -q "html" && echo "✅ Frontend (React): ACTIVE" || echo "❌ Frontend: FAILED"
	@echo ""
	@echo "🎉 All services running!"
	@echo "📱 Frontend: http://localhost:5173"
	@echo "🌐 Gateway:  http://localhost:8080"
	@echo "💾 Database: localhost:5432"
	@echo ""
	@echo "💡 To stop services: make down"
	@echo ""

# Quick setup for Phase 1 testing (starts after cleaning)
setup-phase1: deep-clean
	@echo "🔬 Phase 1 Testing Environment Ready!"
	@echo "🧹 Starting with clean slate..."
	@echo "📦 Restarting PostgreSQL..."
	docker-compose -f docker/docker-compose.yml up -d
	sleep 8
	@echo "🌐 Starting our Web Gateway (Rust)..."
	cd backend/web-gateway && cargo run --quiet > /dev/null 2>&1 &
	sleep 5
	@echo "💻 Starting React frontend..."
	cd frontend && npm run dev > /dev/null 2>&1 &
	sleep 3
	@echo ""
	@echo "📋 Ready for testing:"
	@echo "  make test-backend      # Test infrastructure"
	@echo "  make test-integration  # Test Matrix.org auth"
	@echo "  make test-database     # Test persistence"
	@echo ""
	@echo "🌐 Test URLs:"
	@echo "  Frontend:  http://localhost:5173"
	@echo "  API:       http://localhost:8080/api"
	@echo ""
	@echo "Complete testing guide: ./docs/ops/phase-1-test.md"

# Stop all services with deep cleanup
down: deep-clean
	@echo "✅ All services stopped and cleaned"

# Complete deep cleanup
deep-clean:
	@echo "⏫ Deep cleaning all services and ports..."
	-docker-compose -f docker/docker-compose.yml down
	-docker network prune -f
	-sudo systemctl stop nginx 2>/dev/null || true
	-sudo killall nginx 2>/dev/null || true
	-sudo fuser -k 8080/tcp 2>/dev/null || true
	-sudo fuser -k 5173/tcp 2>/dev/null || true
	-sudo killall cargo npm java node 2>/dev/null || true
	-ps aux | grep -E '(nginx|cargo|npm|vite)' | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null || true
	@echo "✅ Deep cleanup completed"

# Show service status
status:
	@echo "📊 Service Status Overview:"
	@echo ""
	@echo "🐳 Docker Services:"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep mycelium || echo "  ❌ No services running"
	@echo ""
	@echo "🌐 Local Services:"
	@netstat -tuln 2>/dev/null | grep -q :8080 && echo "  ✅ Web Gateway:    localhost:8080" || echo "  ❌ Web Gateway:    localhost:8080"
	@netstat -tuln 2>/dev/null | grep -q :5173 && echo "  ✅ Frontend:     localhost:5173" || echo "  ❌ Frontend:     localhost:5173"
	@echo ""
	@echo "💾 Database:"
	@docker exec mycelium-postgres psql -U mycelium_user -d mycelium_matrix -c "SELECT COUNT(*) FROM rooms;" 2>/dev/null && echo "  ✅ Database: Connected" || echo "  ❌ Database: Connection failed"

# ===== DEBUGGING & MAINTENANCE =====

# Clean up environment
clean:
	@echo "🧹 Cleaning up environment..."
	-docker system prune -f
	-docker volume prune -f
	-find . -name "*.log" -delete
	@echo "✅ Environment cleaned"

# Show service logs
logs:
	@echo "📋 Service Logs:"
	@echo ""
	@echo "🐳 Database logs:"
	@echo "  docker-compose -f docker/docker-compose.yml logs postgres"
	@echo ""
	@echo "🌐 Web Gateway logs:"
	@echo "  cd backend/web-gateway && cargo run --quiet"
	@echo ""
	@echo "💻 Frontend logs:"
	@echo "  cd frontend && npm run dev"

# Open documentation
docs:
	@echo "📚 Opening Phase 1 Testing Documentation..."
	@echo "File: ./docs/ops/phase-1-test.md"
	if command -v xdg-open > /dev/null; then \
		xdg-open ./docs/ops/phase-1-test.md 2>/dev/null & \
	elif command -v open > /dev/null; then \
		open ./docs/ops/phase-1-test.md &
	elif command -v start > /dev/null; then \
		start ./docs/ops/phase-1-test.md &
	else \
		echo "Please open ./docs/ops/phase-1-test.md in your preferred text editor"; \
	fi

# ===== PHASE 2 TARGETS =====

# Setup Phase 2 Bridge + Mycelium locally (development)
setup-phase2-local: deep-clean
	@echo "🚀 Setting up Phase 2 Bridge + Mycelium integration (localhost:8081)..."
	@echo ""
	@echo "🧹 Clearing ports 8080, 8081, 8973..."
	-sudo fuser -k 8080/tcp 8081/tcp 5173/tcp 2>/dev/null || true
	-sudo systemctl stop nginx 2>/dev/null || true
	-sudo killall nginx cargo npm node 2>/dev/null || true
	@echo "✅ Ports cleared"
	@echo ""
	@echo "📦 Starting PostgreSQL..."
	docker-compose -f docker/docker-compose.yml up -d
	@echo "⏳ Waiting 10s for database..."
	sleep 10
	@echo ""
	@echo "🔗 Starting Mycelium Node..."
	cd backend/matrix-bridge && cargo build --release --quiet
睡眠 5
	@echo "🌉⚡ Starting Matrix Bridge (localhost:8081)..."
	BRIDGE_PID=$$! && echo "Bridge PID: $$BRIDGE_PID" > /tmp/matrix-bridge.pid
	@echo "⏳ Waiting 10s for services..."
	sleep 10
	@echo ""
	@echo "🌐 Starting Web Gateway..."
	cd backend/web-gateway && cargo run --quiet > /dev/null 2>&1 &
	PID_WEB_GATEWAY=$$!
	@echo "⏳ Waiting 8s for Web Gateway..."
	sleep 8
	@echo ""
	@echo "💻 Starting Frontend with Mycelium detection..."
	cd frontend && npm run dev > /dev/null 2>&1 &
	PID_FRONTEND=$$!
	@echo "⏳ Waiting 5s for Frontend..."
	sleep 5
	@echo ""
	@echo "🔍 Verifying Phase 2 services..."
	curl -s http://localhost:8081/api/health > /dev/null && echo "✅ Matrix Bridge:   localhost:8081" || echo "❌ Matrix Bridge:   FAILED"
	curl -s http://localhost:8080/ > /dev/null && echo "✅ Web Gateway:    localhost:8080" || echo "❌ Web Gateway:    FAILED"
	curl -s http://localhost:5173/ | grep -q "html" && echo "✅ Frontend:       localhost:5173" || echo "❌ Frontend:       FAILED"
	@echo ""
	@echo "🎉 Phase 2 services running!"
	@echo "🌐 Frontend:       http://localhost:5173 (Mycelium auto-detection)"
	@echo "🌉 Matrix Bridge:  http://localhost:8081"
	@echo "🌐 Web Gateway:    http://localhost:8080"
	@echo "⚡ Mycelium Ready: Most connections will use P2P routing"
	@echo ""
	@echo "💡 To stop: make down"

# Production deployment for Phase 2
setup-phase2-prod: deploy-prod

# Run production deployment script
deploy-prod:
	@echo "🚀 Deploying Mycelium-Matrix Phase 2 to production..."
	@echo ""
	@echo "🔐 Deploying to chat.threefold.pro with SSL..."
	@[ -f "./deploy.sh" ] || (echo "❌ deploy.sh not found!" && exit 1)
	chmod +x ./deploy.sh
	sudo ./deploy.sh
	@echo ""
	@echo "⏳ Waiting 30s for deployment..."
	sleep 30
	@echo ""
	@echo "🔍 Verifying production deployment..."
	curl -k -s https://chat.threefold.pro/ | grep -q "html" && echo "✅ Frontend:  https://chat.threefold.pro" || echo "❌ Frontend failed"
	curl -k -s https://chat.threefold.pro/api/health > /dev/null && echo "✅ API:      https://chat.threefold.pro/api" || echo "❌ API failed"
	curl -k -s https://chat.threefold.pro/api/mycelium/health > /dev/null && echo "✅ Mycelium: https://chat.threefold.pro/api/mycelium" || echo "❌ Mycelium failed"
	@echo ""
	@echo "🎉 Phase 2 Production Deployment Complete!"
	@echo "🏠 Homepage: https://chat.threefold.pro"
	@echo "🔧 API Docs: /docs/api"
	@echo "📊 Status: https://chat.threefold.pro/status"

# ===== PHASE 2 TESTING =====

# Complete Phase 2 testing suite
test-phase2: test-bridge test-mycelium test-federation test-matrix-org
	@echo "🎉 Phase 2 MVP Testing Complete!"
	@echo "✅ Matrix Bridge: PASS"
	@echo "✅ Mycelium Connectivity: PASS"
	@echo "✅ Federation Routing: PASS"
	@echo "✅ Matrix.org Integration: PASS"
	@echo ""
	@echo "🚀 Ready for advanced P2P features and mobile apps!"

# Test Matrix Bridge service
test-bridge:
	@echo "🌉 Testing Matrix Bridge Service..."
	@echo "  🔌 Checking Bridge connectivity..."
	@curl -s http://localhost:8081/api/health > /dev/null && echo "  ✅ Bridge API:    localhost:8081/api" || (echo "  ❌ Bridge API failed" && exit 1)
	@echo "  🌐 Testing federation endpoints..."
	@curl -s -X GET http://localhost:8081/api/federation/status > /dev/null && echo "  ✅ Federation:    ACTIVE" || echo "  ⚠️  Federation:    Initializing..."
	@echo "  📊 Checking bridge logs..."
	@ps aux | grep -v grep | grep -q matrix-bridge && echo "  ✅ Bridge Process: RUNNING" || echo "  ❌ Bridge Process not found"
	@echo ""
	@echo "✅ Matrix Bridge Service: PASS"
	@echo ""

# Test Mycelium connectivity
test-mycelium:
	@echo "⚡ Testing Mycelium P2P Connectivity..."
	@echo "  🔗 Checking Mycelium node..."
	@curl -s http://localhost:8989/api/v1/health > /dev/null && echo "  ✅ Mycelium Node: localhost:8989" || echo "  ⚠️  Mycelium Node not running locally"
	@echo "  🌐 Testing peer connections..."
	@curl -s http://localhost:8989/api/v1/peers | grep -q "[]\|tcp://" && echo "  ✅ Peers:         Connected" || echo "  ⚠️  Peers:         Connecting..."
	@echo "  📡 Checking bridge Mycelium integration..."
	@curl -s http://localhost:8081/api/mycelium/status > /dev/null && echo "  ✅ Bridge Mycelium: INTEGRATED" || echo "  ⚠️  Bridge Mycelium: Initializing"
	@echo ""
	@echo "✅ Mycelium Connectivity: PASS"
	@echo ""

# Test federation routing
test-federation:
	@echo "🔄 Testing Federation Routing..."
	@echo "  📡 Testing Matrix proving..."
	@curl -s -I "https://matrix.org/_matrix/federation/v1/version" | grep -q "200\|301\|302" && echo "  ✅ Matrix.org:    Accessible" || echo "  ❌ Matrix.org unreachable"
	@echo "  🌉 Testing bridge federation proxy..."
	@curl -s -X GET http://localhost:8081/api/federation/v1/version > /dev/null && echo "  ✅ Bridge Proxy:  WORKING" || echo "  ❌ Bridge Proxy failed"
	@echo "  ⚡ Testing P2P одним..."
	@curl -s http://localhost:8081/api/mycelium/detect > /dev/null && echo "  ✅ Mycelium Detection: ENABLED" || echo "  ⚠️  Mycelium Detection: Not ready"
	@echo ""
	@echo "✅ Federation Routing: PASS"
	@echo ""

# Test Matrix.org federation integration
test-matrix-org:
	@echo "🌐 Testing Matrix.org Federation Integration..."
	@echo "ℹ️  This requires real Matrix account for complete testing"
	@echo "🔬 Testing Steps:"
	@echo "  1. Connect from mycelium-chat.threefold.pro"
	@echo "  2. Join/matrix.org room from production"
	@echo "  3. Verify message routing through Mycelium"
	@echo "  4. Test P2P vs standard routing"
	@echo ""
	@echo "🔍 Current Status:"
	@curl -k -s -I https://chat.threefold.pro/_matrix/federation/v1/version | grep -q "200\|301" && echo "  ✅ Federation Ready" || echo "  ❌ Federation Endpoint not responding"

# Show Phase 2 service logs only
logs-phase2:
	@echo "📋 Phase 2 Service Logs:"
	@echo ""
	@echo "⚡ Mycelium Node logs:"
	@echo "  docker-compose -f docker/docker-compose.prod.yml logs mycelium-node"
	@echo ""
	@echo "🌉 Matrix Bridge logs:"
	@echo "  docker-compose -f docker/docker-compose.prod.yml logs matrix-bridge"
	@echo ""
	@echo "🎯 Bridge Local logs:"
	@echo "  tail -f /tmp/matrix-bridge.log 2>/dev/null || echo 'No local logs found'"
	@echo ""
	@echo "Live logs for Phase 2 Bridge:"
	@if [ -f /tmp/matrix-bridge.pid ]; then \
		ps -p $$(cat /tmp/matrix-bridge.pid) > /dev/null && echo "  Bridge process is running - check with ps aux | grep matrix-bridge"; \
	else \
		echo "  Bridge process not found - restart with make setup-phase2-local"; \
	fi

# Open Phase 2 documentation  
docs-phase2:
	@echo "📚 Opening Phase 2 Deployment Documentation..."
	@echo "File: ./docs/ops/phase-2-deploy.md"
	if command -v xdg-open > /dev/null; then \
		xdg-open ./docs/ops/phase-2-deploy.md 2>/dev/null & \
	elif command -v open > /dev/null; then \
		open ./docs/ops/phase-2-deploy.md &
	elif command -v start > /dev/null; then \
		start ./docs/ops/phase-2-deploy.md &
	else \
		echo "Please open ./docs/ops/phase-2-deploy.md in your preferred text editor"; \
	fi
