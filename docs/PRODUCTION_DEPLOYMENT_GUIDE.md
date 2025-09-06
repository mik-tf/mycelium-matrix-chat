# 🚀 Complete Production Deployment Guide
## Mycelium-Matrix Chat on TFGrid

This guide provides step-by-step instructions for deploying Mycelium-Matrix Chat to production on TFGrid with your own domain (e.g., `chat.example.com`).

## 📋 Prerequisites

### Required Accounts & Tools
- **ThreeFold Account**: With sufficient TFT balance (minimum 0.5 TFT)
- **Domain Registrar**: Access to DNS management for your domain
- **SSH Key Pair**: For secure VM access
- **Linux/macOS System**: With bash shell

### System Requirements
- OpenTofu or Terraform installed
- Ansible installed
- curl, git, and basic development tools

## 🌐 Step 1: DNS Configuration

### 1.1 Choose Your Domain
For this guide, we'll use `chat.example.com` as an example. Replace with your actual domain.

### 1.2 DNS Records Setup

#### **Option A: Standard HTTPS Access**
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

#### **Option B: Advanced Setup (Recommended)**
For better reliability, use a load balancer or CDN:

```
Type: CNAME
Name: chat
Value: your-load-balancer.example.com
TTL: 300
```

### 1.3 DNS Propagation
- DNS changes take 5-15 minutes to propagate globally
- Use tools like `dig chat.example.com` to verify propagation
- Test from multiple locations if possible

## 🏗️ Step 2: TFGrid Infrastructure Deployment

### 2.1 Set ThreeFold Credentials

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

### 2.2 Deploy Infrastructure

```bash
# Clone the repository
git clone https://github.com/mik-tf/mycelium-matrix-chat.git
cd mycelium-matrix-chat

# Deploy complete infrastructure (VM + preparation + application)
make deploy
```

This command will:
1. Deploy Ubuntu 24.04 VM on TFGrid
2. Generate mycelium IP for P2P networking
3. Run Ansible playbooks for complete setup
4. Deploy all MMC services

### 2.3 Verify Infrastructure

```bash
# Check deployment status
make status

# Get VM connection details
make connect

# Test basic connectivity
make ping
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

- [ ] Domain DNS configured and propagated
- [ ] TFGrid VM deployed successfully
- [ ] Ansible playbooks completed without errors
- [ ] SSL certificates installed and valid
- [ ] All services running (frontend, bridge, gateway)
- [ ] HTTPS access working at `https://chat.example.com`
- [ ] Mycelium P2P enhancement functional
- [ ] Chat functionality tested and working
- [ ] Monitoring and logging configured

## 🎉 Deployment Complete!

Your Mycelium-Matrix Chat is now live at `https://chat.example.com` with full P2P enhancement capabilities!

**Next Steps:**
1. Announce your new chat service to users
2. Monitor performance and usage
3. Plan Phase 3 features and improvements
4. Consider setting up monitoring/alerts

---

*This guide was created for Mycelium-Matrix Chat Phase 2 deployment. For the latest updates, check the project repository.*