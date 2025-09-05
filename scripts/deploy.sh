#!/bin/bash

set -e

echo "🚀 Starting deployment to chat.projectmycelium.org..."

# Update system
sudo apt update && sudo apt upgrade -y

# Install required dependencies
sudo apt install -y docker.io docker-compose nginx certbot python3-certbot-nginx curl

# Navigate to project directory (assume this script is run from the project root)
cd "$(dirname "$0")"

# Copy environment file
cp .env.production .env

# Install SSL certificate using Let's Encrypt
sudo certbot certonly --nginx \
  --email admin@threefold.io \
  --agree-tos \
  --no-eff-email \
  -d chat.projectmycelium.org \
  -d www.chat.projectmycelium.org

# Create ssl directory and copy certificates
mkdir -p ssl
sudo cp /etc/letsencrypt/live/chat.projectmycelium.org/fullchain.pem ssl/cert.pem
sudo cp /etc/letsencrypt/live/chat.projectmycelium.org/privkey.pem ssl/key.pem

# Build and start production services
export DB_USER="${DB_USER:-production_user}"
export DB_PASSWORD="${DB_PASSWORD:-secure_production_password_replace_this}"

docker-compose -f docker/docker-compose.prod.yml pull
docker-compose -f docker/docker-compose.prod.yml build --no-cache
docker-compose -f docker/docker-compose.prod.yml up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to start..."
sleep 30

# Test deployment
echo "🔍 Testing deployment..."
curl -k https://chat.projectmycelium.org/api/v1/health || echo "Health check failed"
curl -I -k https://chat.projectmycelium.org/ || echo "Frontend check failed"

# Set up SSL auto-renewal
sudo systemctl enable nginx
sudo systemctl reload nginx

# Add renewal hook
echo "#!/bin/bash
docker-compose -f $(pwd)/docker/docker-compose.prod.yml stop nginx
docker-compose -f $(pwd)/docker/docker-compose.prod.yml up -d nginx
" | sudo tee /etc/letsencrypt/renewal-hooks/post/nginx-renewal.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/post/nginx-renewal.sh

# Display success message
echo "✅ Deployment completed successfully!"
echo "🌐 Access your application at https://chat.projectmycelium.org/"
echo "🔧 Monitoring logs: docker-compose -f docker/docker-compose.prod.yml logs -f"

# Add cron job for monitoring (optional)
# echo "*/5 * * * * $(pwd)/scripts/health-check.sh >> /var/log/mycelium-matrix-health.log" | crontab -
