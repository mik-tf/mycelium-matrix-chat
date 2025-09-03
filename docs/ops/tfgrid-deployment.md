# ThreeFold Grid Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the Mycelium-Matrix Chat application on the ThreeFold Grid. The deployment process is automated and takes approximately 15-20 minutes.

**🚀 Ultimate One-Liner (No Repo Required):**

```bash
# 1. Deploy Ubuntu 24.04 VM with Mycelium on TFGrid Dashboard
# 2. Get the Mycelium IP from TFGrid (e.g., 400::abcd:1234:5678:9abc)
# 3. Run this single command on your LOCAL MACHINE (no repo needed):
curl -fsSL https://raw.githubusercontent.com/mik-tf/mycelium-matrix-chat/main/scripts/deploy-remote.sh | bash -s 400::abcd:1234:5678:9abc
```

**That's it!** 🎉 The script will:
- ✅ Download and run the deployment script automatically
- ✅ Validate SSH connectivity to your TFGrid VM
- ✅ Set up `muser` with passwordless sudo privileges
- ✅ Install all prerequisites (Docker, Rust, Node.js, etc.)
- ✅ Deploy the complete Mycelium-Matrix Chat application
- ✅ Monitor progress and report completion
- ✅ Your application is running when it completes!

**Requirements:**
- Mycelium network connected on your local machine
- Ubuntu 20.04+ on the TFGrid VM
- SSH key (TFGrid provides this automatically)

**Time Estimate:** 25-35 minutes total

## Prerequisites

### System Requirements
- ThreeFold Grid account
- Ubuntu 24.04 LTS VM (2 vCPUs, 4 GB RAM minimum)
- Basic familiarity with Linux commands
- Domain name (optional, but recommended for production)

### Required Software Packages
The deployment requires the following software to be installed on your Ubuntu 24.04 VM.

**Important Security Note**: This application should NOT be run as root. The deployment script requires running as a regular user with sudo privileges. On TFGrid VMs, create a dedicated user for deployment.

#### Core System Tools
```bash
# Update system and install basic tools
sudo apt update && sudo apt upgrade -y
sudo apt install -y git make curl wget build-essential pkg-config libssl-dev
```

#### Docker and Container Tools
```bash
# Install Docker and Docker Compose
sudo apt install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
# Note: You may need to log out and back in for docker group changes to take effect
```

#### Rust Toolchain (for backend services)
```bash
# Install Rust using rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
# Add Rust to PATH permanently by adding to ~/.bashrc:
# echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
```

#### Node.js and npm (for frontend)
```bash
# Install Node.js 20.x LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
# Verify installation
node --version
npm --version
```

#### Web Server and SSL
```bash
# Install Nginx and Certbot
sudo apt install -y nginx certbot python3-certbot-nginx
sudo systemctl enable nginx
```

#### Mycelium Client (for P2P networking)
```bash
# Download and install Mycelium
wget https://github.com/threefoldtech/mycelium/releases/latest/download/mycelium-linux-x64
chmod +x mycelium-linux-x64
sudo mv mycelium-linux-x64 /usr/local/bin/mycelium
# Verify installation
mycelium --version
```

### Quick Prerequisites Installation Script
To install all prerequisites in one go, run this script on your Ubuntu 24.04 VM:

```bash
#!/bin/bash
set -e

echo "🚀 Installing Mycelium-Matrix Chat Prerequisites..."

# Security check: Do not run as root
if [ "$EUID" -eq 0 ]; then
    echo "❌ Security Error: This script should NOT be run as root."
    echo "📝 Please create a non-root user with sudo privileges and run as that user."
    echo ""
    echo "To create a deployment user automatically:"
    echo "  useradd -m -s /bin/bash muser"
    echo "  usermod -aG sudo muser"
    echo "  passwd muser"
    echo "  su - muser"
    echo "  ./install-prerequisites.sh"
    exit 1
fi

# Check sudo access
if ! sudo -n true 2>/dev/null; then
    echo "❌ Error: This script requires sudo privileges."
    echo "📝 Please ensure your user has sudo access."
    exit 1
fi

echo "📝 Running as $(whoami) with sudo privileges"
SUDO="sudo"

# Update system
$SUDO apt update && $SUDO apt upgrade -y

# Install core system tools
$SUDO apt install -y git curl wget build-essential pkg-config libssl-dev

# Install Docker
$SUDO apt install -y docker.io docker-compose
$SUDO systemctl enable docker
$SUDO systemctl start docker
if [ "$EUID" -ne 0 ]; then
    $SUDO usermod -aG docker $USER
fi

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO bash -
$SUDO apt-get install -y nodejs

# Install Nginx and Certbot
$SUDO apt install -y nginx certbot python3-certbot-nginx
$SUDO systemctl enable nginx

# Install Mycelium
wget https://github.com/threefoldtech/mycelium/releases/latest/download/mycelium-linux-x64
chmod +x mycelium-linux-x64
if [ "$EUID" -eq 0 ]; then
    mv mycelium-linux-x64 /usr/local/bin/mycelium
else
    $SUDO mv mycelium-linux-x64 /usr/local/bin/mycelium
fi

echo "✅ All prerequisites installed!"
if [ "$EUID" -ne 0 ]; then
    echo "📝 Note: You may need to log out and back in for Docker group changes to take effect"
fi
```

Save this as `install-prerequisites.sh`, make it executable with `chmod +x install-prerequisites.sh`, and run it with `./install-prerequisites.sh`.

**Optional: Create a non-root user with sudo privileges**
If you prefer not to run as root (recommended for security), create a user with sudo access:

```bash
# Create a new user (replace 'muser' with your preferred username)
useradd -m -s /bin/bash muser
usermod -aG sudo muser
usermod -aG docker muser

# Set password for the user
passwd muser

# Switch to the new user
su - muser

# Now you can use sudo for privileged operations
# Update the PATH for Rust if needed
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Security Note**: All commands in this guide include `sudo` and should be run as a non-root user with sudo privileges. The deployment script will refuse to run as root for security reasons. Services will run as the deployment user, not as root.

### Verification Commands
After installing all prerequisites, verify with:
```bash
# Check all required tools
docker --version
docker-compose --version
cargo --version
node --version
npm --version
mycelium --version
nginx -v
certbot --version
```

## Step 0: Prepare TFGrid VM (Automated Setup)

**Important**: TFGrid VMs start as root, but the deployment requires a non-root user with sudo privileges for security. Use the automated preparation script:

```bash
# Download and run the preparation script (run as root)
curl -fsSL https://raw.githubusercontent.com/mik-tf/mycelium-matrix-chat/main/scripts/prepare-tfgrid-vm.sh -o prepare-tfgrid-vm.sh
chmod +x prepare-tfgrid-vm.sh
./prepare-tfgrid-vm.sh
```

**Alternative: Direct execution (if you have the repo)**
```bash
# If you already have the repository cloned:
cd mycelium-matrix-chat/scripts
./prepare-tfgrid-vm.sh
```

**What the script does automatically:**
- ✅ Creates `muser` with passwordless sudo privileges
- ✅ Installs all prerequisites (Docker, Rust, Node.js, Mycelium, etc.)
- ✅ Configures firewall and security
- ✅ Verifies installation
- ✅ **Automatically switches to `muser` and deploys the application**
- ✅ **Your Mycelium-Matrix Chat is running when it completes!**

**Time Estimate:** 25-35 minutes (includes full deployment)

After the script completes, switch to the deployment user:

```bash
# Switch to the deployment user
su - muser

# Change the default password immediately
passwd
```

**Manual Setup** (if you prefer to do it step-by-step):

```bash
# Create dedicated deployment user (run as root)
useradd -m -s /bin/bash muser
usermod -aG sudo muser
passwd muser

# Switch to the deployment user
su - muser
```

## Step 1: Deploy Ubuntu 24.04 VM with Mycelium

### Using ThreeFold Grid Dashboard

1. **Access ThreeFold Grid**
   - Go to [ThreeFold Grid Dashboard](https://dashboard.grid.tf/)
   - Log in to your account

2. **Create New Deployment**
   - Click "Deploy" → "Virtual Machine"
   - Select "Full Virtual Machine" option

3. **Configure VM Specifications**
   ```
   Name: mycelium-matrix-chat
   OS Image: Ubuntu 24.04
   CPU: 2 vCPUs (minimum)
   Memory: 4 GB RAM (minimum)
   Storage: 50 GB SSD (minimum)
   ```

4. **Enable Mycelium Network**
   - In the "Network" section, enable "Mycelium"
   - Note down the Mycelium IP address (will be shown after deployment)

5. **Deploy the VM**
   - Review configuration
   - Click "Deploy"
   - Wait for deployment to complete (usually 2-3 minutes)

## Step 2: Configure Mycelium Network

### Find Your Mycelium Connection Details

After deployment, you'll see:
- **Mycelium IP**: Something like `400::abcd:1234:5678:9abc`
- **Note**: This is the IPv6 address you'll use to SSH into your VM

### Configure Mycelium Peers (Required First)

Before you can SSH into your VM, you need to configure Mycelium peers on your **local machine** to establish the P2P network:

```bash
# Configure Mycelium with working peers
sudo mycelium --peers \
  tcp://188.40.132.242:9651 \
  "quic://[2a01:4f8:212:fa6::2]:9651" \
  tcp://185.69.166.7:9651 \
  "quic://[2a02:1802:5e:0:ec4:7aff:fe51:e36b]:9651" \
  tcp://65.21.231.58:9651 \
  "quic://[2a01:4f9:5a:1042::2]:9651" \
  "tcp://[2604:a00:50:17b:9e6b:ff:fe1f:e054]:9651" \
  quic://5.78.122.16:9651 \
  "tcp://[2a01:4ff:2f0:3621::1]:9651" \
  quic://142.93.217.194:9651 \
  --tun-name mycelium0
```

**Important**: Run this command on your **local machine**, not on the VM. This establishes the Mycelium P2P network that allows you to connect to your VM.

### Verify Mycelium Connection

```bash
# Check if Mycelium is running and connected
mycelium status

# You should see output indicating peers are connected
```

## Step 3: Access Your VM via Mycelium

### Connect via SSH

Now that Mycelium is configured and connected, you can SSH into your VM:

```bash
# SSH into your VM using Mycelium as the deployment user
ssh muser@[YOUR_MYCELIUM_IP]

# Example:
ssh muser@44a:1bca:f2:c72d:ff0f:0:200:2
```

**Note**: The first connection might take a few seconds as Mycelium establishes the P2P connection.

### VSCode Remote SSH Configuration

For VSCode Remote Explorer to work properly with Mycelium IPv6 addresses:

#### Working SSH Config (No Brackets Needed)
```bash
# Add to ~/.ssh/config
Host mycelium-chat
    HostName [YOUR_MYCELIUM_IP]
    User muser
    IdentityFile ~/.ssh/id_ed25519

# Example:
Host mycelium-chat
    HostName 44a:1bca:f2:c72d:ff0f:0:200:2
    User muser
    IdentityFile ~/.ssh/id_ed25519
```

#### Connect in VSCode
1. Open VSCode
2. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
3. Type "Remote-SSH: Connect to Host..."
4. Select `mycelium-chat` from the list
5. VSCode will open the remote explorer

#### Alternative Direct Connection
If the hostname doesn't work, connect directly:
```
ssh muser@[YOUR_MYCELIUM_IP]
```

### Verify Connection

Once connected, you should see:
```bash
Welcome to Ubuntu 24.04 LTS (GNU/Linux 6.8.0-31-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

Last login: [timestamp] from [your-local-ip]
muser@vm-name:~$
```

## Step 3: Clone the Repository

### Clone the Mycelium-Matrix Chat Repository

```bash
# Clone the repository
git clone https://github.com/mik-tf/mycelium-matrix-chat

# Navigate to the project directory
cd mycelium-matrix-chat
```

### Verify Clone Success

```bash
# Check that files are present
ls -la

# You should see:
# - backend/ (Rust services)
# - frontend/ (React application)
# - scripts/ (deployment scripts)
# - docs/ (documentation)
# - Makefile (build automation)
```

## Step 4: Run Production Deployment

### Execute the Automated Deployment

```bash
# Run the production deployment script
make ops-production
```

### What Happens During Deployment

**Important**: Ensure all prerequisites are installed before running the deployment script. If the script fails due to missing dependencies, install them using the commands in the Prerequisites section above.

The deployment script will:

1. **Pre-flight Checks**
   - Verify Ubuntu 24.04 compatibility
   - Check Mycelium connectivity
   - Validate system requirements (Docker, Rust, Node.js, etc.)

2. **System Setup**
   - Verify prerequisite installations
   - Set up PostgreSQL database via Docker
   - Configure firewall and security
   - Set up SSL certificates with Certbot

3. **Application Deployment**
   - Build Matrix Bridge (Rust)
   - Build Web Gateway (Rust)
   - Build React frontend
   - Configure systemd services
   - Set up Docker containers for database and services

4. **Production Validation**
   - Test all services
   - Verify API endpoints
   - Validate SSL certificates
   - Check database connectivity

### Deployment Output

You'll see progress indicators like:
```
🚀 Starting Mycelium-Matrix Chat Production Deployment...

🔧 Pre-deployment Checklist:
  ✅ ThreeFold Grid VM deployed with Ubuntu 24.04
  ✅ Mycelium P2P network configured
  ✅ SSH access via Mycelium established

🔄 Executing production deployment script...
📦 Installing system dependencies...
⚡ Installing Rust...
🌐 Installing Node.js...
💾 Setting up PostgreSQL...
🔒 Configuring firewall...
🔐 Setting up SSL certificates...
⚙️ Building application...
🚀 Deploying services...
✅ Deployment validation passed

==================================================================================
🎉 DEPLOYMENT COMPLETE!
🌐 Website: https://chat.projectmycelium.org
🔧 API: https://chat.projectmycelium.org/api
📊 Matrix Bridge: https://chat.projectmycelium.org/_matrix/federation/v1/version
==================================================================================
```

## Step 5: Configure DNS (Optional but Recommended)

### Get Your VM's Public IP

```bash
# On your VM, get the public IP
curl -s ifconfig.me
# or
curl -s icanhazip.com
```

### Configure DNS Records

1. **Go to your domain registrar** (Namecheap, GoDaddy, etc.)
2. **Add A record**:
   ```
   Type: A
   Host: @
   Value: [YOUR_VM_PUBLIC_IP]
   TTL: 300
   ```
3. **Add CNAME record** (optional):
   ```
   Type: CNAME
   Host: www
   Value: chat.projectmycelium.org
   TTL: 300
   ```

### Verify DNS Propagation

```bash
# Test DNS resolution
nslookup chat.projectmycelium.org

# Should return your VM's public IP
```

## Step 6: Access Your Application

### Web Interface

Once DNS is configured (or immediately using IP):
- **URL**: `https://chat.projectmycelium.org` (or `https://[YOUR_IP]`)
- **Features**:
  - Matrix chat interface
  - Mycelium P2P status
  - Real-time messaging
  - Federation with other Matrix servers

### API Endpoints

- **Health Check**: `https://chat.projectmycelium.org/api/health`
- **Matrix Federation**: `https://chat.projectmycelium.org/_matrix/federation/v1/version`
- **Mycelium Status**: `https://chat.projectmycelium.org/api/mycelium/status`

## Monitoring and Maintenance

### Check Service Status

```bash
# On your VM
make ops-status
```

### View Logs

```bash
# View all service logs
make ops-logs

# Or individual services
sudo journalctl -u matrix-bridge -f
sudo journalctl -u web-gateway -f
sudo journalctl -u mycelium-frontend -f
```

### Create Backup

```bash
# Create production backup
make ops-backup
```

## Troubleshooting

### Common Issues

#### Missing Prerequisites
```bash
# If deployment fails with missing tools, install prerequisites:
# Note: Omit 'sudo' if running as root (TFGrid VMs)
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget build-essential pkg-config libssl-dev
sudo apt install -y docker.io docker-compose nginx certbot python3-certbot-nginx

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt-get install -y nodejs

# Install Mycelium
wget https://github.com/threefoldtech/mycelium/releases/latest/download/mycelium-linux-x64
chmod +x mycelium-linux-x64
sudo mv mycelium-linux-x64 /usr/local/bin/mycelium

# Then retry deployment
make ops-production
```

#### SSH Connection Fails
```bash
# Try again (Mycelium might need time to establish connection)
ssh mycelium@[YOUR_MYCELIUM_IP]

# Check Mycelium status on your local machine
mycelium status
```

#### Deployment Fails
```bash
# Check deployment logs
sudo tail -f /var/log/mycelium-matrix-deployment.log

# Retry deployment
make ops-production
```

#### Services Not Starting
```bash
# Check service status
sudo systemctl status matrix-bridge
sudo systemctl status web-gateway
sudo systemctl status mycelium-frontend

# Restart services
sudo systemctl restart matrix-bridge
sudo systemctl restart web-gateway
sudo systemctl restart mycelium-frontend
```

### Getting Help

- **Documentation**: `./docs/ops/production-deployment.md`
- **DNS Setup**: `./docs/ops/dns-setup.md`
- **Logs**: `make ops-logs`
- **Status**: `make ops-status`

## Next Steps

1. **Test the Application**
   - Create a Matrix account
   - Join rooms and test messaging
   - Verify P2P routing benefits

2. **Configure Additional Features**
   - Set up monitoring alerts
   - Configure backup automation
   - Add SSL certificate renewal

3. **Scale as Needed**
   - Add more CPU/memory if needed
   - Set up load balancing for high traffic
   - Configure database replication

## Security Notes

- SSH access is secured via Mycelium P2P
- All web traffic uses SSL/TLS encryption
- Services run with minimal privileges
- Firewall is automatically configured

## Performance Tips

- Monitor resource usage with `htop`
- Check logs regularly with `make ops-logs`
- Set up automated backups with cron
- Consider upgrading VM specs for high traffic

---

## Complete Workflow Summary

| Step | Action | Time | User |
|------|--------|------|------|
| 1 | Deploy Ubuntu 24.04 VM on TFGrid | 2-3 min | TFGrid Dashboard |
| 2 | Configure Mycelium peers locally | 1-2 min | Local machine |
| 3 | **One-command deployment** | 25-30 min | Root → muser (automatic) |
| 4 | Configure DNS (optional) | 5-10 min | Domain registrar |
| **Total Time** | | **25-35 minutes** | |

**🎯 One-Command Deployment:**
```bash
# Single command as root - handles everything automatically:
curl -fsSL https://raw.githubusercontent.com/mik-tf/mycelium-matrix-chat/main/scripts/prepare-tfgrid-vm.sh | bash
```

**What happens automatically:**
- ✅ Creates `muser` with passwordless sudo
- ✅ Installs all prerequisites
- ✅ Switches to `muser` and clones repository
- ✅ Builds and deploys the application
- ✅ Starts all services

**Security Notes:**
- VM starts as root (TFGrid default)
- Preparation script creates `muser` with sudo privileges
- Deployment runs as `muser` (not root) for security
- Services run as `muser` user
- All prerequisites installed automatically

**Maintenance**: Regular log checks and backups
**Support**: Comprehensive documentation available

**Happy deploying! 🚀**