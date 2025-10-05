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
sudo apt-get install gnupg curl -y && sudo apt install net-tools -y

# Install Node.js and dependencies
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt-get install -y nodejs build-essential python3-dev nginx apache2-utils ufw

# Create training user
sudo useradd -m -s /bin/bash training
echo "training:training123" | sudo chpasswd

# Configure sudo for training user
echo "ubuntu ALL=(training) NOPASSWD: /bin/bash" | sudo tee /etc/sudoers.d/training
echo "training ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt, /usr/bin/systemctl, /usr/bin/curl, /usr/bin/wget, /usr/bin/git, /usr/bin/npm, /usr/bin/node, /usr/bin/htop, /usr/bin/ss, /usr/bin/lsof, /usr/bin/tail, /usr/bin/head, /usr/bin/cat, /usr/bin/grep, /usr/bin/find, /usr/bin/ls, /usr/bin/mkdir, /usr/bin/rmdir, /usr/bin/touch, /usr/bin/cp, /usr/bin/mv, /usr/bin/rm, /usr/bin/chmod, /usr/bin/chown, /usr/bin/ln, /usr/bin/tar, /usr/bin/gzip, /usr/bin/zip, /usr/bin/unzip, /usr/bin/nano, /usr/bin/vim, /usr/bin/vi, /usr/bin/less, /usr/bin/more, /usr/bin/echo, /usr/bin/printf, /usr/bin/date, /usr/bin/uptime, /usr/bin/whoami, /usr/bin/id, /usr/bin/env, /usr/bin/which, /usr/bin/whereis, /usr/bin/locate, /usr/bin/updatedb" | sudo tee -a /etc/sudoers.d/training
sudo chmod 0440 /etc/sudoers.d/training

# Create application directory
sudo mkdir -p /var/lib/instant-terminal
sudo chown ubuntu:ubuntu /var/lib/instant-terminal
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

# Create public directory and index.html
mkdir -p public
cat > public/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Tyk Training Terminal</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css" />
    <style>
      :root { color-scheme: dark; }
      html, body { height: 100%; }
      body {
        margin: 0;
        font-family: Inter, system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
        background: #0b0f1a;
        color: #e6e9ef;
      }
      .page-wrapper {
        min-height: 100%;
        display: grid;
        grid-template-rows: auto 1fr;
      }
      header.page {
        display: flex; align-items: center; gap: 12px;
        padding: 14px 20px; background: #0e1422; border-bottom: 1px solid #1c2333;
      }
      .title { font-weight: 600; }
      .header-controls {
        margin-left: auto;
        display: flex;
        gap: 8px;
      }
      .panel-toggle {
        padding: 6px 12px;
        font-size: 12px;
        font-weight: 500;
        border: 1px solid #243049;
        border-radius: 6px;
        background: #18213c;
        color: #dbe8ff;
        cursor: pointer;
        transition: all 0.2s ease;
        display: flex;
        align-items: center;
        gap: 6px;
      }
      .panel-toggle:hover {
        background: #223055;
        border-color: #2d3748;
      }
      .panel-toggle.active {
        background: #1e40af;
        border-color: #3b82f6;
        color: white;
      }
      .panel-toggle:disabled {
        opacity: 0.5;
        cursor: not-allowed;
      }
      .content-area { position: relative; padding: 28px; display: grid; grid-template-columns: 1fr 1fr; gap: 32px; transition: all 0.3s ease; }
      
      /* Panel states */
      .content-area.docs-only { grid-template-columns: 1fr 0; gap: 0; }
      .content-area.terminal-only { grid-template-columns: 0 1fr; gap: 0; }
      .content-area.split-view { grid-template-columns: 1fr 1fr; gap: 32px; }
      
      .panel-hidden { display: none !important; }
      
      /* Training content area */
      .training-content {
        padding: 20px;
        background: #0e1422;
        border: 1px solid #1c2333;
        border-radius: 12px;
        box-shadow: 0 4px 12px rgba(0,0,0,.3);
        height: calc(100vh - 120px);
        display: flex;
        flex-direction: column;
        min-height: 700px;
      }
      
      .training-title {
        font-size: 18px;
        font-weight: 600;
        color: #e6e9ef;
        margin-bottom: 16px;
        display: flex;
        align-items: center;
        gap: 8px;
      }
      
      /* Documentation Content */
      .docs-content {
        position: relative;
        flex: 1;
        display: flex;
        flex-direction: column;
      }
      
      .doc-section {
        display: block;
        flex: 1;
        display: flex;
        flex-direction: column;
      }
      
      .doc-section h3 {
        color: #e6e9ef;
        font-size: 16px;
        margin: 0 0 8px 0;
        font-weight: 600;
      }
      
      .doc-section p {
        color: #aab9d3;
        font-size: 14px;
        margin: 0 0 16px 0;
      }
      
      .doc-iframe-container {
        background: white;
        border-radius: 8px;
        overflow: hidden;
        box-shadow: 0 2px 8px rgba(0,0,0,.1);
        flex: 1;
        min-height: 700px;
      }
      
      .doc-iframe {
        width: 100%;
        height: 100%;
        border: none;
        display: block;
        flex: 1;
      }
      
      /* Terminal window */
      .terminal-window {
        position: relative;
        width: 100%;
        height: calc(100vh - 120px);
        display: grid; 
        grid-template-rows: auto 1fr;
        background: #0e1422; 
        border: 1px solid #1c2333; 
        border-radius: 10px;
        box-shadow: 0 10px 30px rgba(0,0,0,.55);
        overflow: hidden;
        resize: vertical;
        min-height: 500px;
      }
      .tw-header {
        display: flex; align-items: center; gap: 12px;
        padding: 10px 12px; background: #0f172a; border-bottom: 1px solid #18213c;
        cursor: default;
      }
      .tw-header .dots {
        display: inline-flex; gap: 6px; margin-right: 6px;
      }
      .tw-header .dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
      .dot.red { background: #f87171; }
      .dot.yellow { background: #fbbf24; }
      .dot.green { background: #34d399; }
      .tw-title { font-size: 13px; color: #aab9d3; }
      .tw-actions { margin-left: auto; display: flex; gap: 8px; }
      .btn {
        padding: 4px 8px; font-size: 12px; line-height: 1; cursor: pointer;
        background: #18213c; color: #dbe8ff; border: 1px solid #243049; border-radius: 6px;
      }
      .btn.secondary { background: #223055; }

      /* xterm host */
      #terminal-host { background: #101826; flex: 1; display: flex; }
      #terminal { width: 100%; height: 100%; }

      /* Helpful selection color inside terminal */
      .xterm-selection { background-color: rgba(56, 139, 253, 0.28); }

      /* Responsive: keep it visible on small screens */
      @media (max-width: 1200px) {
        .content-area { grid-template-columns: 1fr; }
        .terminal-window { height: 400px; }
        .training-content { height: 500px; }
      }
      
      @media (max-width: 820px) {
        .terminal-window { height: 350px; }
        .training-content { height: 400px; }
      }
    </style>
  </head>
  <body>
    <div class="page-wrapper">
      <header class="page">
        <div class="title">Tyk API Gateway Training Environment</div>
        <div class="header-controls">
          <button class="panel-toggle active" id="docsToggle">
            📚 Docs
          </button>
          <button class="panel-toggle active" id="terminalToggle">
            💻 Terminal
          </button>
          <button class="panel-toggle" id="splitToggle">
            ⚙️ Split View
          </button>
        </div>
      </header>

      <div class="content-area">
        <!-- Training content -->
        <div class="training-content">
          <div class="training-title">
            📚 Tyk Quick Start Guide
          </div>
          
          <!-- Live Documentation Content -->
          <div class="docs-content">
            <div class="doc-section active">
              <h3>🚀 Get Tyk Running in Minutes</h3>
              <p>Follow the official Tyk documentation to deploy and configure your API Gateway.</p>
              <div class="doc-iframe-container">
                <iframe 
                  src="https://tyk.io/docs/apim/open-source/installation/" 
                  class="doc-iframe"
                  title="Tyk Installation Documentation">
                </iframe>
              </div>
            </div>
          </div>
        </div>
        
        <!-- Floating terminal like the screenshot -->
        <section class="terminal-window" id="tw">
          <div class="tw-header">
            <span class="dots"><span class="dot red"></span><span class="dot yellow"></span><span class="dot green"></span></span>
            <span class="tw-title">Tyk Training Terminal</span>
            <span class="pill" id="status" style="margin-left:8px;">connecting…</span>
            <div class="tw-actions">
              <button class="btn" id="autoScrollToggle">Auto‑scroll: ON</button>
              <button class="btn secondary" id="scrollToBottom">↓ Bottom</button>
            </div>
          </div>
          <div id="terminal-host">
            <div id="terminal"></div>
          </div>
        </section>
      </div>
    </div>

    <!-- xterm + fit addon (UMD) -->
    <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.js"></script>

    <script>
      // --- Terminal setup ---
      const term = new Terminal({
        cursorBlink: true,
        scrollback: 2000,
        fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
        fontSize: 14,
        theme: { background: '#101826', foreground: '#e6e9ef' }
      });
      const fitAddon = new FitAddon.FitAddon();
      term.loadAddon(fitAddon);
      term.open(document.getElementById('terminal'));

      // Make sure fonts/css are ready before measuring for an accurate fit
      const fitNow = () => { try { fitAddon.fit(); } catch(e){} };
      document.fonts?.ready.then(fitNow);
      setTimeout(fitNow, 120);

      // Keep terminal sized with element changes
      const host = document.getElementById('terminal-host');
      new ResizeObserver(() => {
        fitNow();
        // inform backend of the new size
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'resize', data: { cols: term.cols, rows: term.rows } }));
        }
      }).observe(host);

      // --- Connection (adjust the path to your backend) ---
      const statusEl = document.getElementById('status');
      const autoScrollBtn = document.getElementById('autoScrollToggle');
      const scrollBottomBtn = document.getElementById('scrollToBottom');

      const params = new URLSearchParams(location.search);
      const mode = params.get('mode') === 'ssh' ? 'ssh' : 'tty';
      const wsBase = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.hostname + (location.port ? ':' + location.port : '');
      const wsUrl = `${wsBase}/${mode}`; // e.g. wss://your-host/ssh

      let ws;
      let autoScroll = true;

      function connect() {
        ws = new WebSocket(wsUrl);
        ws.binaryType = 'arraybuffer';

        ws.onopen = () => {
          statusEl.textContent = 'connected';
          ws.send(JSON.stringify({ type: 'resize', data: { cols: term.cols, rows: term.rows } }));
          term.focus();
        };
        ws.onclose = () => { statusEl.textContent = 'disconnected'; };
        ws.onerror = () => { statusEl.textContent = 'error'; };

        ws.onmessage = (ev) => {
          const data = typeof ev.data === 'string' ? ev.data : new TextDecoder().decode(ev.data);
          term.write(data);
          if (autoScroll) term.scrollToBottom();
        };
      }
      connect();

      // send keystrokes/raw data to backend
      term.onData(data => {
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'input', data }));
        }
        if (autoScroll) term.scrollToBottom();
      });

      // Optional: when user scrolls up, pause auto-scroll until they jump back down
      term.onScroll(() => {
        const atBottom = term.buffer.active.baseY === term.buffer.active.cursorY || term.buffer.active.viewportY + term.rows >= term.buffer.active.baseY;
        if (!atBottom) {
          autoScroll = false; autoScrollBtn.textContent = 'Auto‑scroll: OFF'; autoScrollBtn.style.opacity = 0.85;
        }
      });

      // UI buttons
      autoScrollBtn.addEventListener('click', () => {
        autoScroll = !autoScroll;
        autoScrollBtn.textContent = autoScroll ? 'Auto‑scroll: ON' : 'Auto‑scroll: OFF';
        if (autoScroll) term.scrollToBottom();
      });
      scrollBottomBtn.addEventListener('click', () => { autoScroll = true; autoScrollBtn.textContent = 'Auto‑scroll: ON'; term.scrollToBottom(); });

      // Keyboard shortcuts (Ctrl+Home/End/Up/Down)
      document.addEventListener('keydown', (e) => {
        if (!e.ctrlKey) return;
        if (e.key === 'Home') { e.preventDefault(); term.scrollToTop(); }
        if (e.key === 'End')  { e.preventDefault(); term.scrollToBottom(); }
        if (e.key === 'ArrowUp')   { e.preventDefault(); term.scrollLines(-1); }
        if (e.key === 'ArrowDown') { e.preventDefault(); term.scrollLines(1); }
      });

      // Focus terminal when the window is clicked
      document.getElementById('tw').addEventListener('mousedown', () => term.focus());

      // --- Panel Toggle Functionality ---
      const contentArea = document.querySelector('.content-area');
      const docsToggle = document.getElementById('docsToggle');
      const terminalToggle = document.getElementById('terminalToggle');
      const splitToggle = document.getElementById('splitToggle');
      
      let currentView = 'split'; // 'split', 'docs-only', 'terminal-only'
      
      function updateView(view) {
        currentView = view;
        
        // Remove all classes
        contentArea.classList.remove('split-view', 'docs-only', 'terminal-only');
        
        // Update button states
        docsToggle.classList.remove('active');
        terminalToggle.classList.remove('active');
        splitToggle.classList.remove('active');
        
        // Apply new view
        switch(view) {
          case 'docs-only':
            contentArea.classList.add('docs-only');
            docsToggle.classList.add('active');
            break;
          case 'terminal-only':
            contentArea.classList.add('terminal-only');
            terminalToggle.classList.add('active');
            break;
          case 'split':
          default:
            contentArea.classList.add('split-view');
            docsToggle.classList.add('active');
            terminalToggle.classList.add('active');
            splitToggle.classList.add('active');
            break;
        }
        
        // Trigger terminal resize
        setTimeout(() => {
          if (fitAddon) {
            try { fitAddon.fit(); } catch(e) {}
            if (ws && ws.readyState === 1) {
              ws.send(JSON.stringify({ type: 'resize', data: { cols: term.cols, rows: term.rows } }));
            }
          }
        }, 100);
        
        // Save preference
        localStorage.setItem('panelView', view);
      }
      
      // Load saved view
      const savedView = localStorage.getItem('panelView') || 'split';
      updateView(savedView);
      
      // Event listeners
      docsToggle.addEventListener('click', () => {
        if (currentView === 'docs-only') {
          updateView('split');
        } else {
          updateView('docs-only');
        }
      });
      
      terminalToggle.addEventListener('click', () => {
        if (currentView === 'terminal-only') {
          updateView('split');
        } else {
          updateView('terminal-only');
        }
      });
      
      splitToggle.addEventListener('click', () => {
        updateView('split');
      });
    </script>
  </body>
</html>
HTML_EOF

# Set ownership
sudo chown -R ubuntu:ubuntu /var/lib/instant-terminal

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

# Configure firewall
ufw allow 22/tcp || true
ufw allow 80/tcp || true
ufw allow 3000/tcp || true
ufw allow 8080/tcp || true
ufw --force enable || true

echo "Tyk Training Environment setup completed successfully!"
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
