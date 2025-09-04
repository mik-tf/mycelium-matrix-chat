#!/usr/bin/make
.PHONY: all deploy prepare app connect clean status logs help validate inventory

# Default target - complete deployment
all: deploy

# Complete deployment (VM + preparation + application)
deploy:
	@echo "🚀 Starting complete MMC deployment..."
	@chmod +x deploy-tfcmd-ansible.sh
	@./deploy-tfcmd-ansible.sh

# Deploy VM only (tfcmd)
vm:
	@echo "🚀 Deploying VM using tfcmd..."
	@chmod +x scripts/tfcmd-deploy.sh
	@./scripts/tfcmd-deploy.sh

# Prepare VM (ansible preparation roles)
prepare: inventory
	@echo "📦 Preparing VM with ansible..."
	@ansible-playbook -i inventory/hosts.ini site.yml --tags preparation

# Deploy MMC application (ansible application roles)
app: inventory
	@echo "🚀 Deploying MMC application..."
	@ansible-playbook -i inventory/hosts.ini site.yml --tags deploy,application

# Validate deployment
validate: inventory
	@echo "🔍 Validating deployment..."
	@ansible-playbook -i inventory/hosts.ini site.yml --tags validate

# Generate ansible inventory from deployed VM
inventory:
	@echo "📝 Checking/generating ansible inventory..."
	@if [ ! -f "inventory/hosts.ini" ] || ! grep -q "ansible_host" inventory/hosts.ini; then \
		echo "❌ No valid inventory found. Please run 'make deploy' first or create inventory manually."; \
		exit 1; \
	fi
	@echo "✅ Inventory ready"

# Connect to deployed VM
connect: inventory
	@echo "🔗 Connecting to MMC server..."
	@VM_IP=$$(grep "ansible_host" inventory/hosts.ini | head -1 | awk '{print $$2}' | cut -d'=' -f2); \
	if [ -z "$$VM_IP" ]; then \
		echo "❌ Could not find VM IP in inventory"; \
		exit 1; \
	fi; \
	echo "Connecting to: $$VM_IP"; \
	if [[ "$$VM_IP" =~ : ]]; then \
		ssh -i ~/.ssh/id_ed25519 root@[$$VM_IP]; \
	else \
		ssh -i ~/.ssh/id_ed25519 root@$$VM_IP; \
	fi

# Check deployment status
status: inventory
	@echo "📊 MMC Deployment Status"
	@echo "========================"
	@VM_IP=$$(grep "ansible_host" inventory/hosts.ini | head -1 | awk '{print $$2}' | cut -d'=' -f2); \
	if [ -z "$$VM_IP" ]; then \
		echo "❌ No VM IP found in inventory"; \
		exit 1; \
	fi; \
	echo "🌐 VM IP: $$VM_IP"; \
	echo ""; \
	echo "🔍 Checking services..."; \
	ansible -i inventory/hosts.ini mmc_servers -m shell -a "systemctl list-units --type=service --state=running | grep mmc" --one-line || echo "⚠️  Could not check services (VM may not be ready)"

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
		rm -f inventory/hosts.ini.backup; \
		echo "✅ Cleanup completed"; \
	else \
		echo "❌ Cleanup cancelled"; \
	fi

# Clean up everything including VM
clean-all:
	@echo "🧹 Cleaning up everything including VM..."
	@echo "⚠️  This will destroy the VM and remove all deployment artifacts"
	@echo ""
	@read -p "Continue? (y/N): " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		@echo "💥 Destroying VM..."; \
		if [ -f "scripts/tfcmd-cancel.sh" ]; then \
			chmod +x scripts/tfcmd-cancel.sh; \
			./scripts/tfcmd-cancel.sh || echo "⚠️  VM destruction may have failed"; \
		else \
			echo "⚠️  tfcmd-cancel.sh not found, skipping VM destruction"; \
		fi; \
		rm -f ansible.log; \
		rm -f inventory/hosts.ini.backup; \
		echo "✅ Full cleanup completed"; \
	else \
		echo "❌ Cleanup cancelled"; \
	fi

# Show help information
help:
	@echo "MMC Ansible Deployment Makefile"
	@echo "==============================="
	@echo ""
	@echo "Targets:"
	@echo "  make              - Run complete deployment (VM + preparation + app)"
	@echo "  make all          - Same as 'make'"
	@echo "  make deploy       - Complete deployment (VM + ansible)"
	@echo "  make vm           - Deploy VM only using tfcmd"
	@echo "  make prepare      - Run ansible preparation roles only"
	@echo "  make app          - Deploy MMC application only"
	@echo "  make validate     - Validate deployment"
	@echo "  make connect      - SSH into deployed VM"
	@echo "  make status       - Check deployment status"
	@echo "  make logs         - Show ansible logs"
	@echo "  make clean        - Clean deployment artifacts (keeps VM)"
	@echo "  make clean-all    - Clean everything including VM"
	@echo "  make help         - Show this help"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - tfcmd installed and configured"
	@echo "  - ansible installed"
	@echo "  - SSH key pair exists (~/.ssh/id_ed25519)"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy              # Complete deployment"
	@echo "  make vm && make prepare  # Step-by-step deployment"
	@echo "  make status              # Check if everything is running"
	@echo "  make connect             # SSH into VM"
	@echo ""
	@echo "For detailed documentation: docs/ops/ansible-deployment.md"
