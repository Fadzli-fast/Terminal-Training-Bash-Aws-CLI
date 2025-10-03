#!/bin/bash
# Deploy script for EC2 Ubuntu 24.04

set -e

echo "🚀 Deploying Instant Terminal to EC2..."

# Update system
sudo apt update -y
sudo apt upgrade -y

# Install Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install nginx
sudo apt install -y nginx

# Create app directory
sudo mkdir -p /opt/instant-terminal
sudo chown $USER:$USER /opt/instant-terminal
cd /opt/instant-terminal

# Copy app files (assuming you'll upload them)
echo "📁 Copy your app files to /opt/instant-terminal/"

# Install dependencies
npm install

# Create environment file
cat > .env << EOF
# SSH Target Configuration
SSH_HOST=localhost
SSH_PORT=22
SSH_USERNAME=ubuntu

# Server Configuration
PORT=3000
NODE_ENV=production
EOF

# Create systemd service
sudo tee /etc/systemd/system/instant-terminal.service > /dev/null << EOF
[Unit]
Description=Instant Terminal Web App
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/instant-terminal
Environment=NODE_ENV=production
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable instant-terminal
sudo systemctl start instant-terminal

# Configure nginx
sudo tee /etc/nginx/sites-available/instant-terminal > /dev/null << EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Enable nginx site
sudo ln -sf /etc/nginx/sites-available/instant-terminal /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# Configure firewall
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw --force enable

echo "✅ Deployment complete!"
echo "🌐 Access your terminal at: http://$(curl -s ifconfig.me)"
echo "🔧 Edit SSH target in: /opt/instant-terminal/.env"
echo "📊 Check status: sudo systemctl status instant-terminal"
echo "📝 View logs: sudo journalctl -u instant-terminal -f"
