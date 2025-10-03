#!/bin/bash
# Upload app to EC2 and deploy

set -e

EC2_HOST="13.214.188.221"
EC2_USER="ubuntu"
EC2_KEY="Tyk_fad_demo.pem"

echo "📦 Uploading files to EC2..."

# Create deployment package
tar -czf terminal-app.tar.gz \
  --exclude=node_modules \
  --exclude=.git \
  --exclude=*.log \
  server.js package.json public/

# Upload to EC2
scp -i "$EC2_KEY" terminal-app.tar.gz $EC2_USER@$EC2_HOST:/tmp/

# Deploy on EC2
ssh -i "$EC2_KEY" $EC2_USER@$EC2_HOST << 'EOF'
  # Extract app
  cd /opt/instant-terminal
  sudo tar -xzf /tmp/terminal-app.tar.gz
  
  # Install dependencies
  npm install
  
  # Restart service
  sudo systemctl restart instant-terminal
  
  # Clean up
  rm /tmp/terminal-app.tar.gz
EOF

# Clean up local
rm terminal-app.tar.gz

echo "✅ Upload complete!"
echo "🌐 Access: http://$EC2_HOST"
