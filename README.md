# Tyk API Gateway Training Environment

A web-based terminal application designed for training environments, perfect for students to learn Tyk API Gateway deployment and management on AWS EC2.

<img width="1704" height="933" alt="image" src="https://github.com/user-attachments/assets/c3d7bf1d-8207-4c80-bb3c-3437f740bc44" />


## Features

- 🌐 **Browser-based terminal interface** using xterm.js with split-screen layout
- 📚 **Live Tyk documentation** embedded on the left panel
- 🔌 **Real-time WebSocket communication** for seamless terminal experience
- 🐧 **Full Linux shell access** on EC2 as `training` user
- 🚀 **One-click multi-instance deployment** (1-10 instances configurable)
- 🔒 **Secure training environment** with Basic HTTP Authentication
- 🎯 **Tyk-specific setup** with proper sudo permissions for training

## Quick Deployment

### Prerequisites
- AWS CLI configured with appropriate permissions
- EC2 Key Pair in your target region
- Node.js 18+ (for local development)

### 1. Configure Deployment
Edit the configuration in `deploy-tyk-training-clean.sh`:
```bash
REGION="ap-southeast-1"                    # Your preferred AWS region
KEY_PAIR_NAME=""      # Your existing EC2 key pair
INSTANCE_TYPE="t3.medium"                  # EC2 instance type
INSTANCE_COUNT=3                           # Number of instances (1-10)
```

### 2. Deploy Training Environment
```bash
# Make script executable
chmod +x deploy-tyk-training-clean.sh

# Deploy to AWS (creates VPC, security groups, and EC2 instances)
./deploy-tyk-training-clean.sh
```

### 3. Access Training Environment
- Wait 2-3 minutes for full deployment
- Open browser to any of the provided URLs
- Login with: 
- Terminal automatically logs in as `training` user

## Configuration Options

### Instance Count
Easily scale your training environment:
```bash
# For testing (1 instance)
INSTANCE_COUNT=1

# For small class (5 instances)  
INSTANCE_COUNT=5

# For large class (10 instances)
INSTANCE_COUNT=10
```

### Instance Types
Choose appropriate instance types:
- `t3.small` - Basic training
- `t3.medium` - Standard training (default)
- `t3.large` - Advanced training with more resources

## Training Features

### 🎯 **Tyk-Specific Setup**
- Pre-configured for Tyk API Gateway training
- Live Tyk documentation embedded in the interface
- Proper sudo permissions for Tyk installation and configuration
- Isolated training user environment

### 🔒 **Security Features**
- Basic HTTP Authentication for web access
- Training user with restricted sudo access
- No root access for students
- Secure WebSocket connections

### 📚 **Learning Environment**
- Split-screen layout: Documentation + Terminal
- Auto-scroll terminal with manual controls
- Professional terminal interface
- Responsive design for different screen sizes

## Local Development

```bash
# Install dependencies
npm install

# Start development server
npm run dev

# Access at http://localhost:3000
```

## Training Use Cases

- **Tyk API Gateway** installation and configuration
- **Linux command training** and system administration
- **Container management** with Docker
- **Network configuration** and troubleshooting
- **File system operations** and permissions
- **Application deployment** and monitoring

## Architecture

The training environment includes:
- **VPC** with public subnet for EC2 instances
- **Security Groups** allowing SSH (22) and HTTP (80) access
- **EC2 Instances** with Ubuntu 24.04 and Node.js
- **Nginx** reverse proxy with WebSocket support
- **Systemd service** for automatic application startup

## Cleanup

When training is complete, clean up AWS resources:
```bash
./cleanup-tyk-training.sh ap-southeast-1
```

## Requirements

- **AWS CLI** configured with EC2 permissions
- **EC2 Key Pair** in target region
- **Ubuntu 24.04** AMI (auto-configured)
- **Node.js 20+** (auto-installed on EC2)
- **Nginx** (auto-installed and configured)

## Security Notes

- Each student gets an isolated EC2 instance
- Training user has specific sudo permissions (no `sudo su`)
- Web access protected by Basic HTTP Authentication
- No local machine access required for students
- All instances are in a dedicated VPC

## Support

For issues or questions:
1. Check the deployment logs in AWS CloudFormation
2. Verify EC2 instance status and systemd service
3. Review Nginx configuration and logs
4. Ensure security groups allow proper access

## License

This project is designed for educational and training purposes.
