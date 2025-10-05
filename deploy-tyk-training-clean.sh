#!/bin/bash

# Tyk Training Environment Deployment Script
# Based on working CloudFormation template pattern

set -e

# Configuration
REGION="ap-southeast-1"  # Change to your preferred region
KEY_PAIR_NAME="tyk_training_instance"         # Set this to your existing key pair
INSTANCE_TYPE="t3.small"
AMI_ID="ami-09f03fa5572692399"  # Ubuntu 22.04 LTS
INSTANCE_COUNT=1  # Number of instances to create (1-10)
SECURITY_GROUP_NAME="tyk-training-sg"
VPC_CIDR="10.42.0.0/16"
SUBNET_CIDR="10.42.1.0/24"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if key pair name is provided
if [ -z "$KEY_PAIR_NAME" ]; then
    print_error "Please set KEY_PAIR_NAME variable in the script"
    exit 1
fi

# Check if key pair exists
if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$REGION" &> /dev/null; then
    print_error "Key pair '$KEY_PAIR_NAME' not found in region '$REGION'"
    exit 1
fi

# Validate instance count
if [[ ! "$INSTANCE_COUNT" =~ ^[1-9][0-9]*$ ]] || [ "$INSTANCE_COUNT" -gt 10 ]; then
    print_error "INSTANCE_COUNT must be a number between 1 and 10. Current value: $INSTANCE_COUNT"
    exit 1
fi

print_status "Starting Tyk Training Environment deployment..."

# Create VPC
print_status "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block "$VPC_CIDR" \
    --region "$REGION" \
    --query 'Vpc.VpcId' \
    --output text)

aws ec2 modify-vpc-attribute \
    --vpc-id "$VPC_ID" \
    --enable-dns-support \
    --region "$REGION"

aws ec2 modify-vpc-attribute \
    --vpc-id "$VPC_ID" \
    --enable-dns-hostnames \
    --region "$REGION"

aws ec2 create-tags \
    --resources "$VPC_ID" \
    --tags Key=Name,Value=tyk-training-vpc \
    --region "$REGION"

print_status "VPC created: $VPC_ID"

# Create Internet Gateway
print_status "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
    --region "$REGION" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

aws ec2 attach-internet-gateway \
    --vpc-id "$VPC_ID" \
    --internet-gateway-id "$IGW_ID" \
    --region "$REGION"

aws ec2 create-tags \
    --resources "$IGW_ID" \
    --tags Key=Name,Value=tyk-training-igw \
    --region "$REGION"

print_status "Internet Gateway created: $IGW_ID"

# Create Subnet
print_status "Creating Subnet..."
SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$SUBNET_CIDR" \
    --availability-zone "${REGION}a" \
    --region "$REGION" \
    --query 'Subnet.SubnetId' \
    --output text)

aws ec2 modify-subnet-attribute \
    --subnet-id "$SUBNET_ID" \
    --map-public-ip-on-launch \
    --region "$REGION"

aws ec2 create-tags \
    --resources "$SUBNET_ID" \
    --tags Key=Name,Value=tyk-training-subnet \
    --region "$REGION"

print_status "Subnet created: $SUBNET_ID"

# Create Route Table
print_status "Creating Route Table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --region "$REGION" \
    --query 'RouteTable.RouteTableId' \
    --output text)

aws ec2 create-route \
    --route-table-id "$ROUTE_TABLE_ID" \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID" \
    --region "$REGION"

aws ec2 associate-route-table \
    --subnet-id "$SUBNET_ID" \
    --route-table-id "$ROUTE_TABLE_ID" \
    --region "$REGION"

aws ec2 create-tags \
    --resources "$ROUTE_TABLE_ID" \
    --tags Key=Name,Value=tyk-training-rt \
    --region "$REGION"

print_status "Route Table created: $ROUTE_TABLE_ID"

# Create Security Group
print_status "Creating Security Group..."
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "Tyk Training Environment Security Group" \
    --vpc-id "$VPC_ID" \
    --region "$REGION" \
    --query 'GroupId' \
    --output text)

# Add security group rules
aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region "$REGION"

aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region "$REGION"

aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region "$REGION"

aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 3000 \
    --cidr 0.0.0.0/0 \
    --region "$REGION"

aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 8080 \
    --cidr 0.0.0.0/0 \
    --region "$REGION"

print_status "Security Group created: $SECURITY_GROUP_ID"

# Create UserData script - Simplified like your working template
print_status "Preparing UserData script..."
USER_DATA=$(cat << 'EOF'
#!/bin/bash
set -ex
apt-get update
apt-get install -y gnupg curl net-tools

# Install Node.js and dependencies
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs build-essential python3-dev nginx apache2-utils ufw

# Install Docker (required for Kubernetes)
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Install kind (Kubernetes in Docker) for local K8s cluster
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
mv ./kind /usr/local/bin/kind

# Install Helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
apt-get update
apt-get install -y helm

# Create training user
useradd -m -s /bin/bash training
echo "training:training123" | chpasswd
usermod -aG docker training

# Configure sudo for training user
echo "ubuntu ALL=(training) NOPASSWD: /bin/bash" | tee /etc/sudoers.d/training
echo "training ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt, /usr/bin/systemctl, /usr/bin/curl, /usr/bin/wget, /usr/bin/git, /usr/bin/npm, /usr/bin/node, /usr/bin/htop, /usr/bin/ss, /usr/bin/lsof, /usr/bin/tail, /usr/bin/head, /usr/bin/cat, /usr/bin/grep, /usr/bin/find, /usr/bin/ls, /usr/bin/mkdir, /usr/bin/rmdir, /usr/bin/touch, /usr/bin/cp, /usr/bin/mv, /usr/bin/rm, /usr/bin/chmod, /usr/bin/chown, /usr/bin/ln, /usr/bin/tar, /usr/bin/gzip, /usr/bin/zip, /usr/bin/unzip, /usr/bin/nano, /usr/bin/vim, /usr/bin/vi, /usr/bin/less, /usr/bin/more, /usr/bin/echo, /usr/bin/printf, /usr/bin/date, /usr/bin/uptime, /usr/bin/whoami, /usr/bin/id, /usr/bin/env, /usr/bin/which, /usr/bin/whereis, /usr/bin/locate, /usr/bin/updatedb, /usr/local/bin/kubectl, /usr/local/bin/helm, /usr/local/bin/kind, /usr/bin/docker" | tee -a /etc/sudoers.d/training
chmod 0440 /etc/sudoers.d/training

# Create application directory
mkdir -p /var/lib/instant-terminal
chown ubuntu:ubuntu /var/lib/instant-terminal
cd /var/lib/instant-terminal

# Create package.json
cat > package.json << 'PKG_EOF'
{
  "name": "tyk-training-terminal",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2",
    "cors": "^2.8.5",
    "node-pty": "^1.0.0"
  }
}
PKG_EOF

# Install dependencies
npm install --unsafe-perm=true --allow-root

# Create server.js
cat > server.js << 'SRV_EOF'
const express=require('express'); const http=require('http'); const {Server}=require('ws');
const cors=require('cors'); const pty=require('node-pty');
const app=express(); app.use(cors()); app.use(express.static('public'));
const server=http.createServer(app); const wss=new Server({server,path:'/tty'});
wss.on('connection',ws=>{ 
  const p=pty.spawn('sudo',['-u','training','bash'],{name:'xterm-256color',cols:120,rows:30,cwd:'/home/ubuntu',env:{...process.env,TERM:'xterm-256color',COLORTERM:'truecolor',FORCE_COLOR:'1'}});
  p.onData(d=>{ try{ws.send(d);}catch{}}); 
  ws.on('message',m=>{ try{const {type,data}=JSON.parse(m.toString()); if(type==='input')p.write(data); if(type==='resize'){const {cols,rows}=data||{}; if(cols&&rows)p.resize(cols,rows);} }catch{ p.write(m.toString()); }});
  ws.on('close',()=>{try{p.kill();}catch{}}); ws.on('error',()=>{try{p.kill();}catch{}}); 
});
const PORT=process.env.PORT||3000; server.listen(PORT,()=>console.log('Listening on http://localhost:'+PORT));
SRV_EOF

# Download application files from GitHub
git clone https://github.com/Fadzli-fast/Terminal-Training-Bash-Aws-CLI.git /tmp/tyk-training
cp -r /tmp/tyk-training/public /var/lib/instant-terminal/
rm -rf /tmp/tyk-training

# Set ownership
chown -R ubuntu:ubuntu /var/lib/instant-terminal

# Create systemd service
cat > /etc/systemd/system/instant-terminal.service << 'SVC_EOF'
[Unit]
Description=Instant Terminal Web App
After=network.target
[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/var/lib/instant-terminal
Environment=NODE_ENV=production
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
SVC_EOF

# Setup authentication
htpasswd -bc /etc/nginx/.htpasswd training_user training123

# Configure nginx
cat > /etc/nginx/sites-available/instant-terminal << 'NGX_EOF'
server {
  listen 80; server_name _;
  location ~ /\. { deny all; }
  location ~ \.(json|env|log)$ { deny all; }
  location / {
    auth_basic "Tyk Training Environment";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass http://localhost:3000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 86400;
  }
}
NGX_EOF

# Enable nginx site
ln -sf /etc/nginx/sites-available/instant-terminal /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t

# Start services
systemctl daemon-reload
systemctl enable instant-terminal
systemctl start instant-terminal
systemctl restart nginx

# Create kind cluster config file
cat > /tmp/kind-config.yaml << 'KIND_EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
KIND_EOF

# Create local Kubernetes cluster with kind (as ubuntu user)
runuser -l ubuntu -c "kind create cluster --name tyk-training --config /tmp/kind-config.yaml"

# Copy kubeconfig to training user
mkdir -p /home/training/.kube
cp /home/ubuntu/.kube/config /home/training/.kube/config
chown -R training:training /home/training/.kube

# Add Tyk Helm repository (as ubuntu user)
runuser -l ubuntu -c "helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/"
runuser -l ubuntu -c "helm repo update"

# Install NGINX Ingress Controller for Tyk (as ubuntu user)
runuser -l ubuntu -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml"
runuser -l ubuntu -c "kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s"

# Clean up
rm /tmp/kind-config.yaml

# Configure firewall
ufw allow 22/tcp || true
ufw allow 80/tcp || true
ufw allow 3000/tcp || true
ufw allow 8080/tcp || true
ufw allow 8443/tcp || true
ufw --force enable || true

echo "Tyk Training Environment with Kubernetes setup completed successfully!"
echo "Kubernetes cluster 'tyk-training' is ready!"
echo "Tyk Helm repository added and updated!"
echo ""
echo "Training users can now:"
echo "  - Use 'kubectl get nodes' to check cluster status"
echo "  - Use 'helm search repo tyk-helm' to see available Tyk charts"
echo "  - Deploy Tyk Gateway: 'helm install tyk-gateway tyk-helm/tyk-gateway'"
echo "  - Deploy Tyk Dashboard: 'helm install tyk-dashboard tyk-helm/tyk-dashboard'"
EOF
)

# Launch EC2 instances
print_status "Launching EC2 instances..."

INSTANCE_IDS=()
for i in $(seq 1 $INSTANCE_COUNT); do
    print_status "Launching instance $i..."
    
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --count 1 \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_PAIR_NAME" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --subnet-id "$SUBNET_ID" \
        --user-data "$USER_DATA" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=tyk-training-$i}]" \
        --region "$REGION" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    INSTANCE_IDS+=("$INSTANCE_ID")
    print_status "Instance $i launched: $INSTANCE_ID"
done

# Wait for instances to be running
print_status "Waiting for instances to be running..."
for instance_id in "${INSTANCE_IDS[@]}"; do
    aws ec2 wait instance-running \
        --instance-ids "$instance_id" \
        --region "$REGION"
    print_status "Instance $instance_id is running"
done

# Get public IPs
print_status "Getting public IP addresses..."
PUBLIC_IPS=()
for instance_id in "${INSTANCE_IDS[@]}"; do
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    PUBLIC_IPS+=("$PUBLIC_IP")
done

# Display results
echo ""
print_status "🎉 Deployment completed successfully!"
echo ""
print_status "Instance Details:"
for i in "${!INSTANCE_IDS[@]}"; do
    echo "  Instance $((i+1)):"
    echo "    ID: ${INSTANCE_IDS[$i]}"
    echo "    Public IP: ${PUBLIC_IPS[$i]}"
    echo "    URL: http://${PUBLIC_IPS[$i]}"
    echo "    Direct App: http://${PUBLIC_IPS[$i]}:3000"
    echo ""
done

print_status "Access Instructions:"
echo "  1. Wait 2-3 minutes for the application to fully start"
echo "  2. Open any of the URLs above in your browser"
echo "  3. Login with username: training_user, password: training123"
echo "  4. The terminal will be logged in as the 'training' user"
echo ""

print_status "Configuration used:"
echo "  Region: $REGION"
echo "  Instance Type: $INSTANCE_TYPE"
echo "  Instance Count: $INSTANCE_COUNT"
echo "  Key Pair: $KEY_PAIR_NAME"
echo ""
print_status "Cleanup command (when you're done):"
echo "  ./cleanup-tyk-training.sh $REGION"
