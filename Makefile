#!/usr/bin/make
.PHONY: all deploy prepare app connect clean status logs help validate inventory wireguard ping

# Default target - complete deployment
all: deploy

# Complete deployment (VM + preparation + application)
deploy: vm prepare app validate
	@echo "🚀 Complete MMC deployment finished!"
	@echo "   Use 'make connect' to SSH into the VM"
	@echo "   Use 'make status' to check deployment status"
	@echo ""
	@echo "📋 Deployment Summary:"
	@if [ "$$TF_VAR_enable_public_ipv4" = "true" ]; then \
		echo "   Type: IPv4 + Domain (~1.0 TFT/month)"; \
		echo "   Public IP: Check 'terraform output vm_public_ip'"; \
		echo "   Domain: Configure DNS to point to public IP"; \
	else \
		echo "   Type: Mycelium-Only (~0.5 TFT/month)"; \
	fi
	@echo ""
	@echo "🔗 Access Information:"
	@echo "   Mycelium: Check 'terraform output vm_mycelium_ip'"
	@if [ "$$TF_VAR_enable_public_ipv4" = "true" ]; then \
		echo "   Domain: https://yourdomain.com (after DNS setup)"; \
	fi
	@echo ""
	@echo "📖 See docs/PRODUCTION_DEPLOYMENT_GUIDE.md for complete setup instructions"

# Deploy VM using OpenTofu/Terraform (alternative to tfcmd)
vm:
	@echo "🚀 Deploying VM using OpenTofu/Terraform..."
	@if [ ! -f "infrastructure/credentials.auto.tfvars" ]; then \
		echo "❌ credentials.auto.tfvars not found!"; \
		echo "   Copy infrastructure/credentials.auto.tfvars.example to infrastructure/credentials.auto.tfvars"; \
		echo "   and configure your settings."; \
		exit 1; \
	fi
	@echo "   Checking for ThreeFold mnemonic..."
	@if [ -n "$$TF_VAR_mnemonic" ]; then \
		echo "   ✅ Using TF_VAR_mnemonic environment variable"; \
	elif [ -f "$$HOME/.config/threefold/mnemonic" ]; then \
		echo "   ✅ Using mnemonic from $$HOME/.config/threefold/mnemonic"; \
		MNEMONIC_VALUE=$$(cat "$$HOME/.config/threefold/mnemonic" | tr -d '\n'); \
		TF_VAR_mnemonic="$$MNEMONIC_VALUE" terraform -chdir=infrastructure init && \
		TF_VAR_mnemonic="$$MNEMONIC_VALUE" terraform -chdir=infrastructure validate && \
		TF_VAR_mnemonic="$$MNEMONIC_VALUE" terraform -chdir=infrastructure plan -out=tfplan && \
		TF_VAR_mnemonic="$$MNEMONIC_VALUE" terraform -chdir=infrastructure apply tfplan; \
	else \
		echo "❌ ThreeFold mnemonic not found!"; \
		echo "   Please set it using one of these methods:"; \
		echo "   "; \
		echo "   1. Environment variable:"; \
		echo "      Bash/Zsh: export TF_VAR_mnemonic='your_mnemonic_here'"; \
		echo "      Fish:     set -x TF_VAR_mnemonic 'your_mnemonic_here'"; \
		echo "   "; \
		echo "   2. Config file (recommended for development):"; \
		echo "      mkdir -p ~/.config/threefold"; \
		echo "      echo 'your_mnemonic_here' > ~/.config/threefold/mnemonic"; \
		echo "      chmod 600 ~/.config/threefold/mnemonic"; \
		echo "   "; \
		echo "   3. Alternative location:"; \
		echo "      mkdir -p ~/.threefold"; \
		echo "      echo 'your_mnemonic_here' > ~/.threefold/mnemonic"; \
		echo "      chmod 600 ~/.threefold/mnemonic"; \
		exit 1; \
	fi
	@echo "✅ Infrastructure deployment completed"
	@echo "   Use 'make connect' to SSH into the VM"
	@echo "   Use 'make prepare' to run ansible preparation"

# Prepare VM (ansible preparation roles)
prepare: inventory
	@echo "📦 Preparing VM with ansible..."
	@echo "   First, checking VM connectivity over mycelium..."
	@if ! make ping >/dev/null 2>&1; then \
		echo "❌ VM connectivity check failed. Aborting preparation."; \
		exit 1; \
	fi
	@echo "✅ VM is reachable, proceeding with Ansible preparation..."
	@for i in 1 2 3 4 5; do \
		echo "   Attempt $$i of 5..."; \
		if ANSIBLE_CONFIG=platform/ansible.cfg ansible-playbook -i platform/inventory/hosts.ini platform/site.yml --tags preparation -vv; then \
			echo "✅ Ansible preparation completed successfully"; \
			exit 0; \
		fi; \
		if [ $$i -lt 5 ]; then \
			echo "   ⚠️  Attempt $$i failed, waiting 30 seconds before retry..."; \
			sleep 30; \
		fi; \
	done; \
	echo "❌ All attempts failed. VM may not be ready yet."; \
	exit 1

# Deploy MMC application (ansible application roles)
app: inventory
	@echo "🚀 Deploying MMC application..."
	@for i in 1 2 3 4 5; do \
		echo "   Attempt $$i of 5..."; \
		if ANSIBLE_CONFIG=platform/ansible.cfg ansible-playbook -i platform/inventory/hosts.ini platform/site.yml --tags deploy,application -vv; then \
			echo "✅ Ansible application deployment completed successfully"; \
			exit 0; \
		fi; \
		if [ $$i -lt 5 ]; then \
			echo "   ⚠️  Attempt $$i failed, waiting 30 seconds before retry..."; \
			sleep 30; \
		fi; \
	done; \
	echo "❌ All attempts failed. VM may not be ready yet."; \
	exit 1

# Validate deployment
validate: inventory
	@echo "🔍 Validating deployment..."
	@for i in 1 2 3; do \
		echo "   Attempt $$i of 3..."; \
		if ANSIBLE_CONFIG=platform/ansible.cfg ansible-playbook -i platform/inventory/hosts.ini platform/site.yml --tags validate -vv; then \
			echo "✅ Ansible validation completed successfully"; \
			exit 0; \
		fi; \
		if [ $$i -lt 3 ]; then \
			echo "   ⚠️  Attempt $$i failed, waiting 15 seconds before retry..."; \
			sleep 15; \
		fi; \
	done; \
	echo "❌ All attempts failed. VM may not be ready yet."; \
	exit 1

# Generate ansible inventory from deployed VM
inventory:
	@echo "📝 Checking/generating ansible inventory..."
	@if [ ! -f "platform/inventory/hosts.ini" ] || ! grep -q "ansible_host" platform/inventory/hosts.ini; then \
		echo "❌ No valid inventory found. Please run 'make deploy' first or create inventory manually."; \
		exit 1; \
	fi
	@echo "✅ Inventory ready"

# Connect to deployed VM
connect: inventory
	@echo "🔗 Connecting to MMC server..."
	@if grep -q "^[[:space:]]*[^#].*ansible_host" platform/inventory/hosts.ini; then \
		VM_IP=$$(grep "^[[:space:]]*[^#].*ansible_host" platform/inventory/hosts.ini | head -1 | sed 's/.*ansible_host=//' | awk '{print $$1}'); \
		if [ -z "$$VM_IP" ]; then \
			echo "❌ Could not parse VM IP from inventory"; \
			exit 1; \
		fi; \
		echo "Connecting to: $$VM_IP"; \
		if echo "$$VM_IP" | grep -q ':'; then \
			ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 root@$$VM_IP; \
		else \
			ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 root@$$VM_IP; \
		fi; \
	else \
		echo "ℹ️  No deployed VM found in inventory"; \
		echo "   Run 'make deploy' to deploy MMC first"; \
		exit 1; \
	fi

# Check deployment status
status: inventory
	@echo "📊 MMC Deployment Status"
	@echo "========================"
	@if grep -q "^[[:space:]]*[^#].*ansible_host" platform/inventory/hosts.ini; then \
		echo "✅ Found deployed VM in inventory"; \
		VM_IP=$$(grep "^[[:space:]]*[^#].*ansible_host" platform/inventory/hosts.ini | head -1 | sed 's/.*ansible_host=//' | awk '{print $$1}'); \
		if [ -z "$$VM_IP" ]; then \
			echo "❌ Could not parse VM IP from inventory"; \
			exit 1; \
		fi; \
		echo "🌐 VM IP: $$VM_IP"; \
		echo ""; \
		echo "🔍 Checking services..."; \
		ANSIBLE_CONFIG=platform/ansible.cfg ansible -i platform/inventory/hosts.ini mmc_servers -m shell -a "systemctl list-units --type=service --state=running | grep mmc" --one-line 2>/dev/null || echo "⚠️  Could not check services (VM may not be ready or ansible not configured)"; \
		echo ""; \
		echo "💡 Tip: If services check fails, try again in a few minutes as the VM may still be initializing"; \
	else \
		echo "ℹ️  No deployed VM found in inventory"; \
		echo "   Run 'make deploy' to deploy MMC first"; \
		echo ""; \
		echo "📋 Current inventory:"; \
		cat platform/inventory/hosts.ini | grep -v "^#" | grep -v "^$$" | head -5; \
	fi

# Show ansible logs
logs:
	@echo "📋 Ansible Logs"
	@echo "==============="
	@if [ -f "ansible.log" ]; then \
		tail -50 ansible.log; \
	else \
		echo "No ansible.log found. Run deployment first."; \
	fi

# Clean up deployment artifacts
clean:
	@echo "🧹 Cleaning up MMC deployment..."
	@echo "⚠️  This will remove inventory and logs, but NOT the VM itself"
	@echo ""
	@read -p "Continue? (y/N): " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		rm -f ansible.log; \
		rm -f platform/inventory/hosts.ini.backup; \
		echo "✅ Cleanup completed"; \
	else \
		echo "❌ Cleanup cancelled"; \
	fi

# Clean up everything including VM
clean-all:
	@echo "🧹 Cleaning up everything including VM..."
	@echo "⚠️  This will destroy the VM and remove all deployment artifacts"
	@echo ""
	@read -p "Continue? (y/N): " confirm && \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		echo "💥 Destroying VM..."; \
		echo "   Checking for ThreeFold mnemonic..."; \
		if [ -n "$$TF_VAR_mnemonic" ]; then \
			echo "   ✅ Using TF_VAR_mnemonic environment variable"; \
			MNEMONIC_VALUE="$$TF_VAR_mnemonic"; \
		elif [ -f "$$HOME/.config/threefold/mnemonic" ]; then \
			echo "   ✅ Using mnemonic from $$HOME/.config/threefold/mnemonic"; \
			MNEMONIC_VALUE=$$(cat "$$HOME/.config/threefold/mnemonic" | tr -d '\n'); \
		else \
			echo "⚠️  ThreeFold mnemonic not found for terraform destroy. Skipping infrastructure cleanup."; \
			MNEMONIC_VALUE=""; \
		fi; \
		if [ -d "infrastructure" ] && [ -f "infrastructure/main.tf" ] && [ -n "$$MNEMONIC_VALUE" ]; then \
		    echo "   Trying infrastructure cleanup..."; \
		    cd infrastructure && ( TF_VAR_mnemonic="$$MNEMONIC_VALUE" tofu destroy -auto-approve 2>/dev/null || TF_VAR_mnemonic="$$MNEMONIC_VALUE" terraform destroy -auto-approve 2>/dev/null ) || echo "⚠️  Infrastructure cleanup may have failed"; \
		    cd ..; \
		fi; \
		if [ -d "infrastructure" ]; then \
			echo "   Cleaning up Terraform files..."; \
			cd infrastructure && rm -rf .terraform/ .terraform.lock.hcl state.json terraform.tfstate* tfplan .terraform* terraform.tfstate*; \
		fi; \
		rm -rf infrastructure/.terraform/ infrastructure/.terraform.lock.hcl infrastructure/state.json infrastructure/terraform.tfstate* infrastructure/tfplan infrastructure/.terraform* infrastructure/terraform.tfstate* \
		rm -f ansible.log; \
		rm -f platform/inventory/hosts.ini.backup; \
		echo "✅ Full cleanup completed"; \
	else \
		echo "❌ Cleanup cancelled"; \
	fi

# Test connectivity to deployed VM
ping:
	@echo "🔗 Testing connectivity to MMC VM..."
	@chmod +x scripts/ping.sh
	@./scripts/ping.sh

# Set up wireguard connection
wireguard:
	@echo "🔗 Setting up WireGuard connection..."
	@chmod +x scripts/wg.sh
	@./scripts/wg.sh

# Phase 2 Testing Suite
.PHONY: test-phase2 test-phase2-quick test-bridge-health test-mycelium-detect test-frontend-load test-end-to-end test-bridge test-mycelium test-federation test-matrix-org test-backend test-frontend test-database test-bridge-comprehensive test-federation-routing test-message-transformation test-server-discovery test-p2p-benefits

# Quick Phase 2 health checks
test-phase2-quick: test-bridge-health test-mycelium-detect test-frontend-load
	@echo "✅ Phase 2 quick health check completed"

test-bridge-health:
	@echo "🔍 Testing Matrix Bridge health..."
	@if curl -s http://localhost:8081/api/v1/bridge/status >/dev/null 2>&1; then \
		echo "✅ Matrix Bridge is responding"; \
	else \
		echo "❌ Matrix Bridge not responding on localhost:8081"; \
		exit 1; \
	fi

test-mycelium-detect:
	@echo "🔍 Testing Mycelium detection..."
	@if curl -s http://localhost:8989/api/v1/admin >/dev/null 2>&1; then \
		echo "✅ Mycelium API detected"; \
	else \
		echo "⚠️  Mycelium API not detected (expected if Mycelium not running)"; \
	fi

test-frontend-load:
	@echo "🔍 Testing frontend loading..."
	@if curl -s http://localhost:5173 >/dev/null 2>&1; then \
		echo "✅ Frontend is loading"; \
	else \
		echo "❌ Frontend not responding on localhost:5173"; \
		exit 1; \
	fi

# Comprehensive Phase 2 testing
test-phase2: test-bridge-comprehensive test-federation-routing test-message-transformation test-server-discovery test-p2p-benefits test-end-to-end
	@echo "✅ Complete Phase 2 testing suite completed"

test-bridge-comprehensive:
	@echo "🔍 Testing Matrix Bridge comprehensive functionality..."
	@if curl -s http://localhost:8081/api/v1/bridge/status | grep -q "connected_servers"; then \
		echo "✅ Bridge status OK"; \
	else \
		echo "❌ Bridge status failed"; \
		exit 1; \
	fi

test-federation-routing:
	@echo "🔍 Testing federation message routing..."
	@if curl -s -X POST http://localhost:8081/api/v1/bridge/test/federation/matrix.org -H "Content-Type: application/json" -d '{"test": "federation"}' | grep -q "status"; then \
		echo "✅ Federation routing OK"; \
	else \
		echo "❌ Federation routing failed"; \
		exit 1; \
	fi

test-message-transformation:
	@echo "🔍 Testing message transformation..."
	@if curl -s -X POST http://localhost:8081/api/v1/bridge/test/message-transform -H "Content-Type: application/json" -d '{"event_type": "m.room.message", "content": {"body": "test"}}' | grep -q "transformed"; then \
		echo "✅ Message transformation OK"; \
	else \
		echo "❌ Message transformation failed"; \
		exit 1; \
	fi

test-server-discovery:
	@echo "🔍 Testing server discovery..."
	@if curl -s http://localhost:8081/api/v1/bridge/routes | grep -q "routes"; then \
		echo "✅ Server discovery OK"; \
	else \
		echo "❌ Server discovery failed"; \
		exit 1; \
	fi

test-p2p-benefits:
	@echo "🔍 Testing P2P benefits analysis..."
	@if curl -s http://localhost:8081/api/v1/bridge/test/p2p-benefits | grep -q "benefits"; then \
		echo "✅ P2P benefits analysis OK"; \
	else \
		echo "❌ P2P benefits analysis failed"; \
		exit 1; \
	fi

test-end-to-end:
	@echo "🔍 Running end-to-end test flow..."
	@if curl -s -X POST http://localhost:8081/api/v1/bridge/test/end-to-end -H "Content-Type: application/json" -d '{"test_flow": "complete"}' | grep -q "success"; then \
		echo "✅ End-to-end test flow OK"; \
	else \
		echo "❌ End-to-end test flow failed"; \
		exit 1; \
	fi

# Individual component testing
test-bridge: test-bridge-comprehensive
test-mycelium: test-mycelium-detect
test-federation: test-federation-routing
test-matrix-org: test-federation
test-backend: test-bridge-health
test-frontend: test-frontend-load
test-database:
	@echo "🔍 Testing database connectivity..."
	@if curl -s http://localhost:8080/api/health >/dev/null 2>&1; then \
		echo "✅ Database connectivity OK"; \
	else \
		echo "❌ Database connectivity failed"; \
		exit 1; \
	fi

# Show help information
help:
	@echo "MMC Ansible Deployment & Testing Makefile"
	@echo "=========================================="
	@echo ""
	@echo "Deployment Targets:"
	@echo "  make              - Run complete deployment (VM + preparation + app)"
	@echo "  make all          - Same as 'make'"
	@echo "  make deploy       - Complete deployment (Terraform/OpenTofu + Ansible)"
	@echo "  make vm           - Deploy VM only using OpenTofu (falls back to Terraform)"
	@echo "  make prepare      - Run ansible preparation roles only"
	@echo "  make app          - Deploy MMC application only"
	@echo "  make validate     - Validate deployment"
	@echo "  make connect      - SSH into deployed VM"
	@echo "  make status       - Check deployment status"
	@echo "  make ping         - Test connectivity to deployed VM"
	@echo "  make logs         - Show ansible logs"
	@echo "  make clean        - Clean deployment artifacts (keeps VM)"
	@echo "  make clean-all    - Clean everything including VM"
	@echo ""
	@echo "Phase 2 Testing Targets:"
	@echo "  make test-phase2-quick    - Basic health validation"
	@echo "  make test-bridge-health   - Bridge connectivity"
	@echo "  make test-mycelium-detect - Mycelium availability"
	@echo "  make test-frontend-load   - Frontend loading"
	@echo "  make test-phase2          - Complete Phase 2 validation suite"
	@echo "  make test-bridge          - Matrix Bridge service testing"
	@echo "  make test-mycelium        - Mycelium P2P connectivity testing"
	@echo "  make test-federation      - Federation routing testing"
	@echo "  make test-matrix-org      - Matrix.org federation integration"
	@echo "  make test-backend         - Infrastructure testing"
	@echo "  make test-frontend        - UI functionality testing"
	@echo "  make test-database        - Persistence layer testing"
	@echo "  make test-end-to-end      - Full workflow validation"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - OpenTofu or Terraform installed"
	@echo "  - ansible installed"
	@echo "  - SSH key pair exists (~/.ssh/id_ed25519)"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy              # Complete deployment (Terraform/OpenTofu + Ansible)"
	@echo "  make vm                  # Deploy VM with OpenTofu (auto-fallback to Terraform)"
	@echo "  make vm && make prepare  # Step-by-step deployment"
	@echo "  make ping                # Test connectivity to deployed VM"
	@echo "  make status              # Check if everything is running"
	@echo "  make connect             # SSH into VM"
	@echo "  make test-phase2-quick   # Quick Phase 2 health check"
	@echo "  make test-phase2         # Full Phase 2 testing suite"
	@echo ""
	@echo "Deployment Methods:"
	@echo "  OpenTofu:  Infrastructure as Code (recommended)"
	@echo "  Terraform: Infrastructure as Code (fallback)"
	@echo ""
	@echo "For detailed documentation: docs/ops/ansible-deployment.md"

