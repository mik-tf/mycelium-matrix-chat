# MMC Ansible-Based Deployment Guide

This document describes the new ansible-based deployment system for Mycelium-Matrix Chat (MMC) on TFGrid, which replaces the previous shell script approach with a more robust and maintainable solution.

## Overview

The new deployment system combines:
- **OpenTofu/Terraform** for VM deployment on TFGrid
- **Ansible** for configuration management and application deployment
- **Modular roles** for different components (inspired by tfgrid-k3s)

## Architecture

```
OpenTofu/Terraform deploy → VM ready → Ansible inventory → Ansible playbooks → MMC deployed
     ↓              ↓              ↓              ↓              ↓
Deploy VM     Extract IP    Generate hosts   Run roles     Validate
```

## Directory Structure

```
mycelium-matrix-chat/
├── platform/                   # Ansible infrastructure (clean organization)
│   ├── ansible.cfg             # Ansible configuration
│   ├── site.yml                # Main playbook
│   ├── inventory/
│   │   └── hosts.ini          # Generated inventory file
│   ├── group_vars/
│   │   └── mmc_servers.yml    # Variables for MMC servers
│   └── roles/
│       ├── common/            # System preparation
│       ├── docker/            # Docker installation
│       ├── rust/              # Rust toolchain
│       ├── nodejs/            # Node.js installation
│       ├── mycelium/          # Mycelium client
│       ├── nginx/             # Web server
│       ├── security/          # Firewall and SSH hardening
│       ├── mmc_deploy/        # MMC application deployment
│       └── validation/        # Post-deployment validation
```

## Quick Start

### Prerequisites

1. **OpenTofu** or **Terraform** installed
2. **Ansible** installed (`pip install ansible`)
3. **SSH key pair** exists
4. **Mycelium network** connected (recommended)
5. **ThreeFold mnemonic** (see [Security Documentation](./security.md) for secure handling)

### Deploy MMC

```bash
# Use default settings
make deploy

# Or deploy step-by-step
make vm           # Deploy VM using OpenTofu/Terraform
make prepare      # Prepare VM with Ansible
make app          # Deploy MMC application
make validate     # Validate deployment
```

### Available Options

Use environment variables or the `infrastructure/credentials.auto.tfvars` file to customize:

```bash
# VM Configuration (via infrastructure/credentials.auto.tfvars)
vm_name = "myceliumchat"
cpu_cores = 4
memory_gb = 16
disk_gb = 250
node_id = 6883

# Or use environment variables
export TF_VAR_cpu_cores=2
export TF_VAR_memory_gb=8
```

### Alternative: OpenTofu/Terraform Deployment

For Infrastructure as Code approach:

```bash
# Setup credentials
cp infrastructure/credentials.auto.tfvars.example infrastructure/credentials.auto.tfvars
# Edit credentials.auto.tfvars with your mnemonic and settings

# Deploy VM with OpenTofu (auto-fallback to Terraform if needed)
make vm-tofu

# Continue with ansible preparation
make prepare
make app
make validate
```

**Note**: The `vm-tofu` command will automatically fall back to Terraform if the OpenTofu provider is not available, ensuring deployment works regardless of which tool you have installed.

## Deployment Process

### 1. VM Deployment (OpenTofu/Terraform)
- Deploys Ubuntu 24.04 VM on TFGrid
- Extracts mycelium IPv6 address
- Configures VM with specified resources

### 2. Inventory Generation
- Creates ansible inventory file
- Configures SSH connection parameters
- Sets up host variables

### 3. Ansible Preparation (Roles)
The following roles run in sequence:

#### common
- System updates and package installation
- User creation (`muser`) with sudo access
- SSH key setup for passwordless access

#### docker
- Installs Docker and Docker Compose
- Adds deploy user to docker group
- Enables and starts Docker service

#### rust
- Installs Rust toolchain for deploy user
- Configures PATH and environment

#### nodejs
- Installs Node.js 20.x LTS
- Sets up npm package manager

#### mycelium
- Downloads and installs Mycelium client
- Configures binary in `/usr/local/bin`

#### nginx
- Installs and configures Nginx
- Sets up reverse proxy for MMC services
- Enables SSL/TLS support

#### security
- Configures UFW firewall
- Hardens SSH configuration
- Sets up fail2ban (future)

### 4. Application Deployment (mmc_deploy)
- Clones MMC repository
- Builds Rust backend services
- Installs frontend dependencies
- Creates systemd services
- Starts all MMC components

### 5. Validation
- Tests health endpoints
- Verifies service status
- Checks Nginx configuration

## Manual Ansible Usage

If you prefer to run ansible manually after VM deployment:

```bash
# Generate inventory (replace IP with actual VM IP)
echo "[mmc_servers]
mmc-node-1 ansible_host=YOUR_VM_IP ansible_user=root

[mmc_servers:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=/usr/bin/python3" > platform/inventory/hosts.ini

# Run preparation
ANSIBLE_CONFIG=platform/ansible.cfg ansible-playbook -i platform/inventory/hosts.ini platform/site.yml --tags preparation

# Run deployment
ANSIBLE_CONFIG=platform/ansible.cfg ansible-playbook -i platform/inventory/hosts.ini platform/site.yml --tags deploy,application

# Run validation
ANSIBLE_CONFIG=platform/ansible.cfg ansible-playbook -i platform/inventory/hosts.ini platform/site.yml --tags validate
```

## Configuration

### Variables

Edit `platform/group_vars/mmc_servers.yml` to customize:

```yaml
# User configuration
deploy_user: muser
deploy_user_home: "/home/{{ deploy_user }}"

# Service ports
web_gateway_port: 8080
frontend_port: 5173
matrix_bridge_port: 8081

# Repository settings
mmc_repo: "https://github.com/mik-tf/mycelium-matrix-chat"
mmc_branch: "main"
```

### SSH Keys

The deployment uses your default SSH key (`~/.ssh/id_ed25519` or `~/.ssh/id_rsa`). To use a different key, modify the `infrastructure/credentials.auto.tfvars` file:

```hcl
ssh_private_key_path = "/path/to/your/private/key"
ssh_public_key_path = "/path/to/your/public/key.pub"
```

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   - Verify SSH key is correct
   - Check VM is fully booted
   - Ensure mycelium IP is correct

2. **Ansible Role Failed**
   - Check ansible logs: `ansible.log`
   - SSH into VM manually to debug
   - Run roles individually with `--tags`

3. **Service Not Starting**
   - Check systemd status: `systemctl status mmc-*`
   - View logs: `journalctl -u mmc-service-name`
   - Verify dependencies are installed

### Debug Mode

Run with verbose output:

```bash
ANSIBLE_CONFIG=platform/ansible.cfg ansible-playbook -i platform/inventory/hosts.ini platform/site.yml -vvv
```

### Manual Recovery

If deployment fails partway through:

```bash
# SSH into VM
ssh root@[VM_IP]

# Check what was installed
systemctl list-units --type=service | grep mmc

# Re-run specific role
ANSIBLE_CONFIG=platform/ansible.cfg ansible-playbook -i platform/inventory/hosts.ini platform/site.yml --tags role_name
```

## Security Considerations

- **SSH**: Root login disabled, key-based authentication only
- **Firewall**: UFW enabled with minimal ports open
- **Services**: Run as non-root user (`muser`)
- **Updates**: System kept up-to-date during deployment

## Comparison with Previous System

| Aspect | Old (Shell Scripts) | New (Ansible) |
|--------|-------------------|---------------|
| Maintainability | Low | High |
| Error Handling | Basic | Robust |
| Reusability | Limited | High |
| Testing | Manual | Automated |
| Documentation | Minimal | Comprehensive |
| Rollback | None | Partial |

## Future Enhancements

- Add monitoring (Prometheus/Grafana)
- Implement backup/restore
- Add load balancing
- Support multiple VMs
- Add CI/CD integration

## Support

For issues with the ansible deployment:

1. Check this documentation
2. Review ansible logs
3. Test individual roles
4. Check VM system logs
5. Report issues with detailed logs