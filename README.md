cat > README.md << 'EOF'
# Terminal Training

A web-based terminal application designed for training environments, perfect for students to learn Linux commands and deploy applications like Tyk Gateway on AWS EC2.

## Features

- 🌐 Browser-based terminal interface using xterm.js
- 🔌 Real-time WebSocket communication
- 🐧 Full Linux shell access on EC2
- 🚀 One-click EC2 deployment
- 🔒 Secure and isolated training environment

## Quick Deployment

### 1. Launch EC2 Instance
- Create Ubuntu 24.04 EC2 instance
- Open ports 22 (SSH) and 80 (HTTP) in security groups

### 2. Deploy Application
```bash
# Run deployment script
./deploy.sh

# Upload application files
./upload-to-ec2.sh
```

### 3. Access Terminal
- Open browser to: `http://YOUR_EC2_IP`
- Start using the terminal immediately!

## Local Development

```bash
npm install
npm run dev
```

## Training Use Cases

- Linux command training
- Application deployment (Tyk Gateway, etc.)
- Container management
- Network configuration
- File system operations

## Requirements

- Node.js 18+
- Ubuntu 24.04 (for EC2)
- Nginx (auto-installed by deploy script)

## Security

- Each student gets isolated EC2 instance
- No local machine access required
- Secure SSH-backed connections
EOF

# Add and commit README
git add README.md
git commit -m "Add comprehensive README for training use"
git push
