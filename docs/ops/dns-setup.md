# DNS Configuration Guide for Mycelium-Matrix Chat

## Overview

This guide explains how to configure DNS settings for `chat.projectmycelium.org` to point to your ThreeFold Grid VM running the Mycelium-Matrix Chat application.

## Prerequisites

- Domain registrar account (where `projectmycelium.org` is registered)
- ThreeFold Grid VM deployed and running
- Public IP address of your TF Grid VM
- SSH access to your VM via Mycelium

## Step 1: Get Your VM's IP Address

First, get the public IP address of your ThreeFold Grid VM:

```bash
# On your local machine, SSH into the VM via Mycelium
ssh mycelium@<mycelium-peer-id>

# Once connected to the VM, get the public IP
curl -s ifconfig.me
# or
curl -s icanhazip.com
# or
curl -s ipinfo.io/ip
```

**Save this IP address** - you'll need it for the DNS configuration.

## Step 2: Access Your Domain Registrar

Log into your domain registrar's control panel where `projectmycelium.org` is registered. Common registrars include:

- Namecheap
- GoDaddy
- Google Domains
- Cloudflare
- Route 53 (AWS)

## Step 3: Configure DNS Records

### Primary A Record

Create an **A record** for the root domain:

```
Type: A
Host: @
Value: <YOUR_VM_IP_ADDRESS>
TTL: 300 (5 minutes)
```

This makes `chat.projectmycelium.org` point to your VM's IP address.

### WWW CNAME Record (Optional)

Create a **CNAME record** for the www subdomain:

```
Type: CNAME
Host: www
Value: chat.projectmycelium.org
TTL: 300 (5 minutes)
```

This makes `www.chat.projectmycelium.org` redirect to `chat.projectmycelium.org`.

## Step 4: Verify DNS Propagation

After configuring the DNS records, wait 5-10 minutes for propagation, then verify:

```bash
# Check A record
nslookup chat.projectmycelium.org

# Or use dig
dig chat.projectmycelium.org

# Should return your VM's IP address
```

## Step 5: SSL Certificate Setup

The deployment script automatically sets up SSL certificates using Let's Encrypt. However, you may need to configure DNS challenges if your registrar requires it.

### For Cloudflare Users

If using Cloudflare, ensure the DNS records are set to **DNS only** (not proxied) during SSL setup:

1. In Cloudflare dashboard, go to DNS settings
2. For the A record, click the cloud icon to make it gray (DNS only)
3. Run the deployment script
4. After SSL is configured, you can optionally enable Cloudflare proxy (orange cloud)

### Manual SSL Setup (if needed)

If automatic SSL setup fails, you can manually configure SSL:

```bash
# On your VM
sudo certbot certonly --manual --preferred-challenges dns -d chat.projectmycelium.org

# Follow the prompts to add the TXT record to your DNS
# Then complete the certificate generation
```

## DNS Configuration Examples

### Namecheap

1. Log into Namecheap dashboard
2. Go to Domain List → Manage
3. Click "Advanced DNS"
4. Add records as specified above

### GoDaddy

1. Log into GoDaddy dashboard
2. Go to Domain Settings
3. Click "Manage DNS"
4. Add records as specified above

### Cloudflare

1. Log into Cloudflare dashboard
2. Select your domain
3. Go to DNS settings
4. Add records as specified above
5. Set to "DNS only" (gray cloud) initially

### Google Domains

1. Log into Google Domains
2. Select your domain
3. Go to DNS settings
4. Add custom records as specified above

## Troubleshooting

### DNS Not Propagating

If DNS changes aren't taking effect:

```bash
# Check current DNS resolution
dig chat.projectmycelium.org

# Clear DNS cache (on local machine)
# Windows: ipconfig /flushdns
# macOS: sudo killall -HUP mDNSResponder
# Linux: sudo systemd-resolve --flush-caches
```

### SSL Certificate Issues

If SSL certificates aren't working:

```bash
# Check certificate status
curl -I https://chat.projectmycelium.org

# Renew certificates
sudo certbot renew

# Check Certbot logs
sudo journalctl -u certbot
```

### Connection Issues

If you can't connect to the domain:

```bash
# Test basic connectivity
ping chat.projectmycelium.org

# Test HTTP
curl -I http://chat.projectmycelium.org

# Test HTTPS
curl -I https://chat.projectmycelium.org

# Check firewall on VM
sudo ufw status
```

## Advanced Configuration

### CDN Setup (Optional)

For better performance, you can set up a CDN:

1. Configure DNS records to point to CDN
2. Set up CDN to proxy to your VM
3. Configure SSL certificates on CDN

### Load Balancing (Future)

When scaling to multiple VMs:

1. Create A records for multiple IPs
2. Set up load balancer
3. Configure health checks
4. Update DNS with load balancer IP

## Monitoring DNS

### Regular Checks

Set up monitoring to check DNS health:

```bash
# Add to cron for regular DNS monitoring
*/5 * * * * /usr/local/bin/check-dns.sh

# check-dns.sh content:
#!/bin/bash
EXPECTED_IP="<your-vm-ip>"
CURRENT_IP=$(dig +short chat.projectmycelium.org)

if [ "$CURRENT_IP" != "$EXPECTED_IP" ]; then
    echo "DNS mismatch! Expected: $EXPECTED_IP, Got: $CURRENT_IP" | mail -s "DNS Alert" admin@projectmycelium.org
fi
```

### DNS Monitoring Services

Consider using external DNS monitoring services:
- DNS Checker
- MX Toolbox
- DNS Watch
- Monitor DNS

## Security Considerations

### DNSSEC

Enable DNSSEC if your registrar supports it:
1. Generate DNSSEC keys
2. Add DS records to registrar
3. Enable DNSSEC in registrar dashboard

### Rate Limiting

Configure rate limiting for DNS queries to prevent abuse.

## Support

If you encounter issues with DNS configuration:

1. Check this documentation
2. Verify with your domain registrar's support
3. Test with online DNS tools
4. Check VM firewall and network settings
5. Review deployment script logs

## Next Steps

After DNS is configured and propagated:

1. Run the deployment script: `make ops-production`
2. Test the application: https://chat.projectmycelium.org
3. Set up monitoring and backups
4. Configure additional security measures

---

**Domain**: `chat.projectmycelium.org`  
**Expected IP**: `<your-vm-ip-address>`  
**SSL**: Let's Encrypt (automatic)  
**CDN**: Optional (Cloudflare, etc.)

**Last Updated**: September 2, 2025