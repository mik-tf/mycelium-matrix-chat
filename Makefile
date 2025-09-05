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

# Deploy VM using OpenTofu/Terraform (alternative to tfcmd)
vm-tofu:
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
	@ansible-playbook -i inventory/hosts.ini site.yml --tags preparation -v

# Deploy MMC application (ansible application roles)
app: inventory
	@echo "🚀 Deploying MMC application..."
	@ansible-playbook -i inventory/hosts.ini site.yml --tags deploy,application -v

# Validate deployment
validate: inventory
	@echo "🔍 Validating deployment..."
	@ansible-playbook -i inventory/hosts.ini site.yml --tags validate -v

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
	@if grep -q "^[[:space:]]*[^#].*ansible_host" inventory/hosts.ini; then \
		VM_IP=$$(grep "^[[:space:]]*[^#].*ansible_host" inventory/hosts.ini | head -1 | sed 's/.*ansible_host=//' | awk '{print $$1}'); \
		if [ -z "$$VM_IP" ]; then \
			echo "❌ Could not parse VM IP from inventory"; \
			exit 1; \
		fi; \
		echo "Connecting to: $$VM_IP"; \
		if echo "$$VM_IP" | grep -q ':'; then \
			ssh -i ~/.ssh/id_ed25519 root@[$$VM_IP]; \
		else \
			ssh -i ~/.ssh/id_ed25519 root@$$VM_IP; \
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
	@if grep -q "^[[:space:]]*[^#].*ansible_host" inventory/hosts.ini; then \
		echo "✅ Found deployed VM in inventory"; \
		VM_IP=$$(grep "^[[:space:]]*[^#].*ansible_host" inventory/hosts.ini | head -1 | sed 's/.*ansible_host=//' | awk '{print $$1}'); \
		if [ -z "$$VM_IP" ]; then \
			echo "❌ Could not parse VM IP from inventory"; \
			exit 1; \
		fi; \
		echo "🌐 VM IP: $$VM_IP"; \
		echo ""; \
		echo "🔍 Checking services..."; \
		ansible -i inventory/hosts.ini mmc_servers -m shell -a "systemctl list-units --type=service --state=running | grep mmc" --one-line 2>/dev/null || echo "⚠️  Could not check services (VM may not be ready or ansible not configured)"; \
	else \
		echo "ℹ️  No deployed VM found in inventory"; \
		echo "   Run 'make deploy' to deploy MMC first"; \
		echo ""; \
		echo "📋 Current inventory:"; \
		cat inventory/hosts.ini | grep -v "^#" | grep -v "^$$" | head -5; \
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
	@read -p "Continue? (y/N): " confirm && \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		echo "💥 Destroying VM..."; \
		if [ -f "scripts/tfcmd-cancel.sh" ]; then \
			chmod +x scripts/tfcmd-cancel.sh; \
			./scripts/tfcmd-cancel.sh || echo "⚠️  VM destruction may have failed"; \
		elif [ -d "infrastructure" ] && [ -f "infrastructure/main.tf" ]; then \
			echo "   Trying infrastructure cleanup..."; \
			cd infrastructure && (tofu destroy -auto-approve 2>/dev/null || terraform destroy -auto-approve 2>/dev/null) || echo "⚠️  Infrastructure cleanup may have failed"; \
		else \
			echo "⚠️  No cleanup script found, skipping VM destruction"; \
		fi; \
		rm -f ansible.log; \
		rm -f inventory/hosts.ini.backup; \
		rm -f wg-mmc.conf; \
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
	@echo "  make deploy       - Complete deployment (tfcmd + ansible)"
	@echo "  make vm           - Deploy VM only using tfcmd"
	@echo "  make vm-tofu      - Deploy VM only using OpenTofu (falls back to Terraform)"
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
	@echo "  make deploy              # Complete deployment (tfcmd)"
	@echo "  make vm-tofu             # Deploy VM with OpenTofu (auto-fallback to Terraform)"
	@echo "  make vm && make prepare  # Step-by-step deployment"
	@echo "  make status              # Check if everything is running"
	@echo "  make connect             # SSH into VM"
	@echo ""
	@echo "Deployment Methods:"
	@echo "  tfcmd:     Simple CLI tool (default)"
	@echo "  tofu:      Infrastructure as Code (alternative)"
	@echo ""
	@echo "For detailed documentation: docs/ops/ansible-deployment.md"

