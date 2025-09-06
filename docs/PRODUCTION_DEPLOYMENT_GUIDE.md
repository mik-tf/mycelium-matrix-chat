# 🚀 Complete Production Deployment Guide
## Mycelium-Matrix Chat on TFGrid

This guide provides step-by-step instructions for deploying Mycelium-Matrix Chat to production on TFGrid with flexible deployment options.

## 🎯 Quick Deployment Reference

### **Quick Start Commands:**

#### **Perfect Configuration File Method (Recommended)**
```bash
# 1. Clone the repository
git clone https://github.com/mik-tf/mycelium-matrix-chat.git
cd mycelium-matrix-chat

# 2. Copy and edit configuration
cp infrastructure/credentials.auto.tfvars.example infrastructure/credentials.auto.tfvars
nano infrastructure/credentials.auto.tfvars

# 3. Set your deployment type:
# enable_public_ipv4 = true   # IPv4 + Domain deployment
# enable_public_ipv4 = false  # Mycelium-only deployment

# 4. Deploy - automatically uses your configuration
make deploy

# 5. Get access URLs
make status
```
### **Infrastructure Configuration:**
The flexible deployment options are already configured in the infrastructure:

- **`infrastructure/variables.tf`** - Contains `enable_public_ipv4` variable
- **`infrastructure/main.tf`** - Uses the variable to control IPv4 deployment
- **Environment variables** - `TF_VAR_enable_public_ipv4=true/false` controls the deployment type

## 📋 Prerequisites

### Required Accounts & Tools
- **ThreeFold Account**: With sufficient balance
- **Domain Registrar**: Access to DNS management for your domain
- **SSH Key Pair**: For secure VM access
- **Linux/macOS System**: With bash shell

### System Requirements
- OpenTofu or Terraform installed
- Ansible installed
- curl, git, and basic development tools

## 🌐 Step 1: Choose Your Deployment Type

### 1.1 Deployment Options

#### **Option A: IPv4 + Domain (Public Production)**
- **Access**: `https://chat.example.com`
- **Use Case**: Public production deployment
- **Requirements**: Domain name + DNS configuration

#### **Option B: Mycelium-Only (Private P2P)**
- **Access**: `https://[mycelium-ip]:443`
- **Use Case**: Private deployment, testing
- **Requirements**: None (automatic mycelium IP)

#### **Option C: Dual Access (Maximum Flexibility)**
- **Access**: Both URLs above
- **Use Case**: Best of both worlds
- **Requirements**: Domain name + DNS configuration

### 1.2 Configuration Decision

Choose your deployment type by setting the `TF_VAR_enable_public_ipv4` variable:

```bash
# IPv4 + Domain deployment
export TF_VAR_enable_public_ipv4=true

# Mycelium-only deployment (default)
export TF_VAR_enable_public_ipv4=false
# or simply don't set the variable
```

## 🌐 Step 2: DNS Configuration (IPv4 Deployments Only)

### 2.1 Choose Your Domain
For this guide, we'll use `chat.example.com` as an example. Replace with your actual domain.

### 2.2 DNS Records Setup

#### **Standard HTTPS Access**
Add these records at your DNS provider:

```
Type: A
Name: chat
Value: [TFGrid VM Public IP - obtained after deployment]
TTL: 300

Type: CNAME (optional)
Name: www.chat
Value: chat.example.com
TTL: 300
```

#### **Advanced Setup (Recommended)**
For better reliability, use a load balancer or CDN:

```
Type: CNAME
Name: chat
Value: your-load-balancer.example.com
TTL: 300
```

### 2.3 DNS Propagation
- DNS changes take 5-15 minutes to propagate globally
- Use tools like `dig chat.example.com` to verify propagation
- Test from multiple locations if possible

**Note**: Skip DNS configuration for mycelium-only deployments

## 🏗️ Step 3: TFGrid Infrastructure Deployment

### 3.1 Set ThreeFold Credentials

#### **Method 1: Environment Variables (Recommended for CI/CD)**
```bash
# Use set +o history to prevent mnemonic from being stored in shell history
set +o history
export TF_VAR_mnemonic="your_threefold_mnemonic_here"
set -o history
```

#### **Method 2: Config File (Recommended for Development)**
```bash
# Create secure config directory
mkdir -p ~/.config/threefold
echo "your_mnemonic_here" > ~/.config/threefold/mnemonic
chmod 600 ~/.config/threefold/mnemonic
```

### 3.2 Choose and Deploy Your Infrastructure

#### **IPv4 + Domain Deployment**
```bash
# Clone the repository
git clone https://github.com/mik-tf/mycelium-matrix-chat.git
cd mycelium-matrix-chat

# Copy and configure deployment settings
cp infrastructure/credentials.auto.tfvars.example infrastructure/credentials.auto.tfvars
nano infrastructure/credentials.auto.tfvars

# Set: enable_public_ipv4 = true
# Also configure: node_id, vm_name, etc.

# Deploy complete infrastructure
make deploy
```

#### **Mycelium-Only Deployment**
```bash
# Clone the repository
git clone https://github.com/mik-tf/mycelium-matrix-chat.git
cd mycelium-matrix-chat

# Copy and configure deployment settings
cp infrastructure/credentials.auto.tfvars.example infrastructure/credentials.auto.tfvars
nano infrastructure/credentials.auto.tfvars

# Keep: enable_public_ipv4 = false (default)
# Also configure: node_id, vm_name, etc.

# Deploy complete infrastructure
make deploy
```

#### **Step-by-Step Deployment** (Any Type)
```bash
# Deploy VM only
make vm

# Prepare VM with ansible
make prepare

# Deploy MMC application
make app

# Validate deployment
make validate
```

### 3.3 Deployment Process

All deployment types follow the same process:

1. **VM Deployment**: Ubuntu 24.04 VM on TFGrid
2. **Mycelium Setup**: IPv6 overlay networking (always enabled)
3. **IPv4 Setup**: Public IP assignment (if enabled)
4. **Ansible Preparation**: Install Docker, Rust, Node.js, security
5. **Application Deployment**: Deploy all MMC services
6. **SSL Configuration**: Let's Encrypt certificates (IPv4 only)

### 3.4 Verify Infrastructure

```bash
# Check deployment status
make status

# Get VM connection details
make connect

# Test basic connectivity
make ping

# For IPv4 deployments, get the public IP
make status | grep "Public IP"
```

## 🔐 Step 3: SSL Certificate Setup

### 3.1 Automatic SSL with Let's Encrypt

The deployment includes automatic SSL certificate generation:

```bash
# SSH into the deployed VM
make connect

# Check SSL certificate status
sudo certbot certificates

# If needed, run certificate generation
sudo certbot --nginx -d chat.example.com
```

### 3.2 Manual SSL Certificate (Alternative)

If you prefer manual certificate management:

```bash
# Upload your certificates to the VM
scp cert.pem key.pem root@[vm-ip]:/etc/nginx/ssl/

# Update nginx configuration
sudo vi /etc/nginx/sites-available/mmc
# Add SSL certificate paths

# Reload nginx
sudo systemctl reload nginx
```

## 🧪 Step 4: Testing & Validation

### 4.1 Health Checks

```bash
# Test from your local machine
curl -k https://chat.example.com/health

# Test API endpoints
curl -k https://chat.example.com/api/v1/bridge/status

# Test Mycelium detection
curl -k https://chat.example.com/api/mycelium/api/v1/admin
```

### 4.2 Functional Testing

```bash
# Run Phase 2 test suite
make test-phase2

# Test Matrix federation
make test-federation

# Validate SSL
curl -v https://chat.example.com/ 2>&1 | grep "SSL certificate"
```

### 4.3 Browser Testing

1. **Open your browser** and navigate to `https://chat.example.com`
2. **Verify SSL certificate** - Should show valid certificate for your domain
3. **Test Mycelium detection** - Status should show "Mycelium Enhanced" if Mycelium is running locally
4. **Test chat functionality** - Create account, join rooms, send messages

## 🔧 Step 5: Configuration & Customization

### 5.1 Environment Variables

Update production environment variables:

```bash
# SSH into VM
make connect

# Edit environment file
sudo vi /opt/mmc/.env.production

# Key variables to configure:
DOMAIN=chat.example.com
SSL_CERT_PATH=/etc/nginx/ssl/cert.pem
SSL_KEY_PATH=/etc/nginx/ssl/key.pem
DB_PASSWORD=your_secure_db_password
```

### 5.2 Service Configuration

```bash
# Restart services after configuration changes
sudo systemctl restart mmc-*
sudo systemctl restart nginx

# Check service status
sudo systemctl status mmc-frontend
sudo systemctl status mmc-matrix-bridge
sudo systemctl status mmc-web-gateway
```

## 🌐 Step 6: Dual Access Configuration

### 6.1 Mycelium IP Access

After deployment, your VM will have both:
- **Public IP**: `chat.example.com` (standard HTTPS access)
- **Mycelium IP**: `[mycelium-ip]` (P2P enhanced access)

### 6.2 Testing Dual Access

```bash
# Get mycelium IP from deployment output
make status

# Test mycelium access
curl https://[mycelium-ip]/health

# Test enhanced P2P features
curl https://[mycelium-ip]/api/v1/bridge/status
```

## 📊 Step 6: Access Your Deployment

### 6.1 Access URLs by Deployment Type

#### **IPv4 + Domain Deployment**
```
🌐 Primary Access: https://chat.example.com
🔒 Mycelium Access: https://[mycelium-ip]:443 (enhanced P2P)
📱 Mobile Access: mycelium://[mycelium-ip]:443
```

#### **Mycelium-Only Deployment**
```
🔒 Primary Access: https://[mycelium-ip]:443
📱 Mobile Access: mycelium://[mycelium-ip]:443
🌐 Domain Access: Not available (no public IPv4)
```

### 6.2 Getting Your Access URLs

#### **Find Mycelium IP**
```bash
# After deployment, get the mycelium IP
make status

# Or check terraform output
cd infrastructure && terraform output vm_mycelium_ip
```

#### **Find Public IP (IPv4 deployments)**
```bash
# Get the public IPv4 address
make status | grep "Public IP"

# Or check terraform output
cd infrastructure && terraform output
```

### 6.3 User Experience

#### **Progressive Enhancement Flow**
1. **All Users**: Can access via available URLs
2. **Mycelium Users**: Automatically get P2P benefits
3. **Non-Mycelium Users**: Get standard Matrix federation
4. **Same Application**: Different access methods, same features

## 📊 Step 7: Monitoring & Maintenance

### 7.1 Service Monitoring

```bash
# Check all MMC services
sudo systemctl list-units --type=service | grep mmc

# View service logs
sudo journalctl -u mmc-matrix-bridge -f

# Monitor resource usage
sudo htop
```

### 7.2 Backup Strategy

```bash
# Database backup
sudo -u postgres pg_dump mycelium_matrix > backup.sql

# Configuration backup
sudo tar -czf config-backup.tar.gz /opt/mmc/

# SSL certificates backup
sudo tar -czf ssl-backup.tar.gz /etc/nginx/ssl/
```

### 7.3 Updates & Maintenance

```bash
# Update MMC application
cd /opt/mmc
git pull
make deploy-app

# Update SSL certificates
sudo certbot renew

# System updates
sudo apt update && sudo apt upgrade
```

## 🔧 Troubleshooting

### Common Issues & Solutions

#### **DNS Not Resolving**
```bash
# Check DNS propagation
dig chat.example.com

# Test from different locations
curl -I https://chat.example.com
```

#### **SSL Certificate Issues**
```bash
# Check certificate validity
openssl s_client -connect chat.example.com:443 -servername chat.example.com

# Renew certificates
sudo certbot renew --dry-run
```

#### **Service Not Starting**
```bash
# Check service status
sudo systemctl status mmc-matrix-bridge

# View detailed logs
sudo journalctl -u mmc-matrix-bridge --no-pager -n 50

# Restart services
sudo systemctl restart mmc-*
```

#### **Mycelium Not Detected**
```bash
# Check if Mycelium is running locally
ps aux | grep mycelium

# Test Mycelium API
curl http://localhost:8989/api/v1/admin

# Check browser console for errors
```

## 📞 Support & Community

### Getting Help
- **Documentation**: Check `/docs/` directory for detailed guides
- **Issues**: Report bugs on GitHub
- **Community**: Join Matrix rooms for support

### Useful Commands
```bash
# Quick health check
make test-phase2-quick

# Full system status
make status

# Emergency restart
sudo systemctl restart mmc-*

# View all logs
sudo journalctl -u mmc-* --since "1 hour ago"
```

## ✅ Success Checklist

### **For IPv4 + Domain Deployments**
- [ ] Domain DNS configured and propagated
- [ ] TF_VAR_enable_public_ipv4=true set
- [ ] TFGrid VM deployed with public IPv4
- [ ] DNS A record pointing to public IP
- [ ] Ansible playbooks completed without errors
- [ ] SSL certificates installed and valid
- [ ] All services running (frontend, bridge, gateway)
- [ ] HTTPS access working at `https://chat.example.com`
- [ ] Mycelium access working at `https://[mycelium-ip]:443`
- [ ] Mycelium P2P enhancement functional
- [ ] Chat functionality tested and working
- [ ] Monitoring and logging configured

### **For Mycelium-Only Deployments**
- [ ] TF_VAR_enable_public_ipv4=false (or not set)
- [ ] TFGrid VM deployed with mycelium networking
- [ ] Ansible playbooks completed without errors
- [ ] All services running (frontend, bridge, gateway)
- [ ] Mycelium access working at `https://[mycelium-ip]:443`
- [ ] Mycelium P2P enhancement functional
- [ ] Chat functionality tested and working
- [ ] Monitoring and logging configured

### **General Validation**
- [ ] Matrix Bridge responding on port 8081
- [ ] Frontend serving on correct port
- [ ] Mycelium detection working in browser
- [ ] Progressive enhancement active for mycelium users
- [ ] Database connectivity confirmed
- [ ] SSL/TLS working (IPv4 deployments)

## 🎉 Deployment Complete!

Your Mycelium-Matrix Chat is now live at `https://chat.example.com` with full P2P enhancement capabilities!

**Next Steps:**
1. Announce your new chat service to users
2. Monitor performance and usage
3. Plan Phase 3 features and improvements
4. Consider setting up monitoring/alerts

## 🎯 Deployment Decision Helper

### **Which Deployment Type Should You Choose?**

#### **Choose IPv4 + Domain If:**
- ✅ You want a traditional domain name (chat.yourcompany.com)
- ✅ You need public accessibility for all users
- ✅ You're building a public production service
- ✅ You want SSL certificates and standard HTTPS

#### **Choose Mycelium-Only If:**
- ✅ You want maximum privacy and P2P benefits
- ✅ You're deploying for private groups or testing
- ✅ You don't need traditional domain access
- ✅ Your users are technically savvy

#### **Both Options Provide:**
- ✅ Full Matrix chat functionality
- ✅ Mycelium P2P enhancement for compatible users
- ✅ Progressive enhancement (works for all users)
- ✅ Enterprise-grade security
- ✅ Production-ready infrastructure

---

*This guide was created for Mycelium-Matrix Chat Phase 2 deployment. For the latest updates, check the project repository.*