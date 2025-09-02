# ThreeFold Grid Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the Mycelium-Matrix Chat application on the ThreeFold Grid. The deployment process is automated and takes approximately 15-20 minutes.

## Prerequisites

- ThreeFold Grid account
- Basic familiarity with Linux commands
- Domain name (optional, but recommended for production)

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
# SSH into your VM using Mycelium
ssh root@[YOUR_MYCELIUM_IP]

# Example:
ssh root@44a:1bca:f2:c72d:ff0f:0:200:2
```

**Note**: The first connection might take a few seconds as Mycelium establishes the P2P connection.

### VSCode Remote SSH Configuration

For VSCode Remote Explorer to work properly with Mycelium IPv6 addresses:

#### Working SSH Config (No Brackets Needed)
```bash
# Add to ~/.ssh/config
Host mycelium-chat
    HostName [YOUR_MYCELIUM_IP]
    User root
    IdentityFile ~/.ssh/id_ed25519

# Example:
Host mycelium-chat
    HostName 44a:1bca:f2:c72d:ff0f:0:200:2
    User root
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
ssh root@[YOUR_MYCELIUM_IP]
```

### Verify Connection

Once connected, you should see:
```bash
Welcome to Ubuntu 24.04 LTS (GNU/Linux 6.8.0-31-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

Last login: [timestamp] from [your-local-ip]
mycelium@vm-name:~$
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

The deployment script will:

1. **Pre-flight Checks**
   - Verify Ubuntu 24.04 compatibility
   - Check Mycelium connectivity
   - Validate system requirements

2. **System Setup**
   - Install Rust, Node.js, PostgreSQL, Nginx
   - Configure firewall and security
   - Set up SSL certificates

3. **Application Deployment**
   - Build Matrix Bridge (Rust)
   - Build Web Gateway (Rust)
   - Build React frontend
   - Configure systemd services

4. **Production Validation**
   - Test all services
   - Verify API endpoints
   - Validate SSL certificates

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

**Deployment Time**: ~15-20 minutes
**Maintenance**: Regular log checks and backups
**Support**: Comprehensive documentation available

**Happy deploying! 🚀**