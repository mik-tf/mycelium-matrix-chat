# Mycelium-Matrix Chat Deployment Flow: Complete Guide for Newcomers

## **What is Mycelium-Matrix Chat?**
A decentralized chat application that combines Matrix protocol's federation with Mycelium's P2P networking. It runs on ThreeFold Grid (a decentralized cloud platform) and provides both standard web chat and enhanced P2P features.

## **High-Level Architecture**
```
Your Local Machine → ThreeFold Grid VM → MMC Application
     ↓                        ↓              ↓
  Terraform/Ansible       Ubuntu 24.04    Frontend + Backend
  Deployment Tools        + Mycelium      + Database + Services
```

## **Deployment Tools Overview**
- **Terraform/OpenTofu**: Infrastructure as Code - creates the virtual machine on ThreeFold Grid
- **Ansible**: Configuration management - sets up the VM with required software
- **Makefile**: Orchestrates the entire deployment process with simple commands
- **Docker**: Containerizes the application components for easy deployment

## **Application Components**
- **Frontend** (`frontend/`): React/TypeScript web application with Matrix SDK
- **Backend** (`backend/`): 
  - `matrix-bridge/`: Rust service for Matrix-Mycelium integration
  - `web-gateway/`: HTTPS gateway service
  - `shared/`: Common Rust code and database models
- **Infrastructure** (`infrastructure/`): Terraform configs for VM deployment
- **Platform** (`platform/`): Ansible playbooks for VM configuration

## **Complete Deployment Flow**

### **Step 1: Prerequisites Setup**
```bash
# Install required tools
# - OpenTofu or Terraform
# - Ansible  
# - ThreeFold account with TFT tokens
# - SSH keys configured

# Set up secure credentials
set +o history
export TF_VAR_mnemonic="your_threefold_mnemonic"
set -o history
```

### **Step 2: Infrastructure Deployment (`make vm`)**
**What happens:**
- Terraform/OpenTofu connects to ThreeFold Grid
- Deploys an Ubuntu 24.04 virtual machine
- Configures Mycelium IPv6 networking automatically
- Generates SSH access and network configuration
- Creates secure WireGuard VPN for management

**Result:** A ready-to-use VM on ThreeFold Grid with Mycelium networking

### **Step 3: VM Preparation (`make prepare`)**
**What happens:**
- Ansible connects to the deployed VM via SSH
- Installs all required software:
  - Docker and Docker Compose
  - Rust toolchain
  - Node.js and npm
  - Nginx web server
  - PostgreSQL database
  - Mycelium P2P client
  - Security hardening (firewall, SSH config)
- Configures systemd services
- Sets up SSL certificates (Let's Encrypt)
- Applies enterprise security practices

**Result:** A fully configured server ready for application deployment

### **Step 4: Application Deployment (`make app`)**
**What happens:**
- Builds the Rust backend services (`cargo build --release`)
- Builds the React frontend (`npm run build`)
- Creates Docker images for all components
- Deploys containers using Docker Compose:
  - Matrix Bridge service (Rust)
  - Web Gateway service (Rust) 
  - Frontend web application (React)
  - PostgreSQL database
  - Nginx reverse proxy
- Configures systemd services for auto-start
- Sets up health checks and monitoring

**Result:** Fully running MMC application accessible via web browser

### **Step 5: Validation (`make validate`)**
**What happens:**
- Runs automated health checks
- Tests service connectivity
- Verifies Matrix federation
- Confirms SSL certificates
- Validates Mycelium networking

**Result:** Confirmation that everything is working correctly

## **How It All Works Together**

1. **Single Command Deployment**: `make deploy` runs vm → prepare → app → validate
2. **Modular Approach**: Each step can be run separately for debugging
3. **Infrastructure as Code**: Everything is defined in code, reproducible
4. **Security First**: Enterprise-grade security with credential management
5. **Decentralized**: Runs on ThreeFold Grid

## **Accessing Your Deployment**
- **Web App**: Visit the VM's IP address in browser
- **SSH Access**: `make connect` for server management
- **Status Check**: `make status` to see running services
- **Logs**: `make logs` for troubleshooting

## **Key Benefits of This Approach**
- **Automated**: One command deploys everything
- **Secure**: Built-in security practices
- **Scalable**: Can be extended for multiple nodes
- **Maintainable**: Infrastructure defined as code
- **Decentralized**: No reliance on traditional cloud providers

This deployment system makes it easy for anyone to run their own instance of Mycelium-Matrix Chat on decentralized infrastructure, with the same reliability as enterprise deployments but without vendor lock-in.