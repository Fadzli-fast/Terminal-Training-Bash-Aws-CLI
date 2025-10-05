# Tyk Training Environment - Complete Deployment Guide

This guide provides step-by-step instructions for deploying the Tyk Training Environment from scratch on a fresh Ubuntu 24.04 EC2 instance.

## 📋 Prerequisites

- Fresh Ubuntu 24.04 EC2 instance
- EC2 key pair (.pem file)
- SSH access to the instance
- Basic knowledge of Linux commands

## 🚀 Step-by-Step Deployment

### Step 1: Initial Server Setup

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential build tools
sudo apt install -y build-essential python3-dev curl wget git

# Install Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install Nginx
sudo apt install -y nginx

# Verify installations
node --version
npm --version
nginx -v
```

### Step 2: Create Application Directory and User

```bash
# Create application directory
sudo mkdir -p /var/lib/instant-terminal
sudo chown ubuntu:ubuntu /var/lib/instant-terminal

# Create training user
sudo useradd -m -s /bin/bash training
sudo passwd training  # Set password: training123

# Remove training user from sudo group (security)
sudo deluser training sudo
```

### Step 3: Configure Sudo Permissions

```bash
# Create sudoers configuration for training user
sudo tee /etc/sudoers.d/training > /dev/null << 'EOF'
# Allow ubuntu to spawn bash as training user (for terminal app)
ubuntu ALL=(training) NOPASSWD: /bin/bash

# Training user can only run specific commands with sudo (NO su or sudo su)
training ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt, /usr/bin/systemctl, /usr/bin/docker, /usr/bin/docker-compose, /usr/bin/curl, /usr/bin/wget, /usr/bin/git, /usr/bin/npm, /usr/bin/node, /usr/bin/tyk, /usr/bin/redis-cli, /usr/bin/mysql, /usr/bin/psql, /usr/bin/htop, /usr/bin/iotop, /usr/bin/netstat, /usr/bin/ss, /usr/bin/lsof, /usr/bin/tail, /usr/bin/head, /usr/bin/cat, /usr/bin/grep, /usr/bin/find, /usr/bin/ls, /usr/bin/mkdir, /usr/bin/rmdir, /usr/bin/touch, /usr/bin/cp, /usr/bin/mv, /usr/bin/rm, /usr/bin/chmod, /usr/bin/chown, /usr/bin/ln, /usr/bin/tar, /usr/bin/gzip, /usr/bin/zip, /usr/bin/unzip, /usr/bin/nano, /usr/bin/vim, /usr/bin/vi, /usr/bin/less, /usr/bin/more, /usr/bin/echo, /usr/bin/printf, /usr/bin/date, /usr/bin/uptime, /usr/bin/whoami, /usr/bin/id, /usr/bin/env, /usr/bin/which, /usr/bin/whereis, /usr/bin/locate, /usr/bin/updatedb
EOF

# Validate sudoers configuration
sudo visudo -c
```

### Step 4: Deploy Application Files

```bash
# Navigate to application directory
cd /var/lib/instant-terminal

# Create package.json
sudo tee package.json > /dev/null << 'EOF'
{
  "name": "tyk-training-terminal",
  "version": "1.0.0",
  "description": "Tyk API Gateway Training Environment",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2",
    "node-pty": "^1.0.0",
    "cors": "^2.8.5"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOF

# Install dependencies
npm install

# Create server.js
sudo tee server.js > /dev/null << 'EOF'
const express = require('express');
const http = require('http');
const { Server } = require('ws');
const cors = require('cors');
const os = require('os');
const pty = require('node-pty');

const app = express();
app.use(cors());
app.use(express.static('public'));
app.use('/node_modules', express.static('node_modules'));

const server = http.createServer(app);
const wss = new Server({ server, path: '/tty' });

wss.on('connection', (ws) => {
  console.log('New WebSocket connection established');
  
  const shell = os.platform() === 'win32' ? 'powershell.exe' : 'sudo';
  const shellArgs = os.platform() === 'win32' ? [] : ['-u', 'training', 'bash'];
  console.log('Spawning shell:', shell, 'with args:', shellArgs);
  
  const ptyProcess = pty.spawn(shell, shellArgs, {
    name: 'xterm-256color',
    cols: 120,
    rows: 30,
    cwd: '/home/ubuntu',
    env: { 
      ...process.env, 
      TERM: 'xterm-256color',
      COLORTERM: 'truecolor',
      FORCE_COLOR: '1'
    },
  });
  
  console.log('PTY process spawned with PID:', ptyProcess.pid);

  ptyProcess.onExit((code, signal) => {
    console.log('PTY process exited with code:', code, 'signal:', signal);
  });

  const send = (data) => {
    if (ws.readyState === 1) { // WebSocket.OPEN
      try {
        ws.send(data);
      } catch (error) {
        console.error('Error sending data:', error);
      }
    }
  };

  ptyProcess.onData(send);

  ws.on('message', (msg) => {
    console.log('Received message:', msg.toString());
    try {
      const { type, data } = JSON.parse(msg.toString());
      if (type === 'input') {
        ptyProcess.write(data);
      } else if (type === 'resize') {
        const { cols, rows } = data || {};
        if (cols && rows) {
          ptyProcess.resize(cols, rows);
        }
      }
    } catch (e) {
      console.log('JSON parse error, treating as raw input:', e.message);
      ptyProcess.write(msg.toString());
    }
  });

  ws.on('close', () => {
    console.log('Connection closed');
    try { 
      ptyProcess.kill(); 
    } catch (error) {
      console.error('Error killing pty process:', error);
    }
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
    try { 
      ptyProcess.kill(); 
    } catch (e) {
      console.error('Error killing pty process on error:', e);
    }
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Server listening on http://localhost:${PORT}`);
});
EOF

# Create public directory and index.html
sudo mkdir -p public
sudo tee public/index.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Instant Terminal</title>

    <!-- Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600&display=swap" rel="stylesheet">

    <!-- xterm.css is REQUIRED to avoid weird cursor/scroll bugs -->
    <link rel="stylesheet" href="/node_modules/xterm/css/xterm.css" />

    <style>
      :root { color-scheme: dark; }
      html, body { height: 100%; }
      body {
        margin: 0;
        font-family: Inter, system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
        background: #0b0f1a; /* page backdrop */
        color: #e6e9ef;
      }

      /* Fake course page so the floating terminal feels like the screenshot */
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
      .pill { font-size: 12px; padding: 4px 8px; border: 1px solid #243049; border-radius: 999px; color: #9bb1d0; }
      .content-area { position: relative; padding: 28px; display: grid; grid-template-columns: 1fr 1fr; gap: 32px; }
      
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
    <script src="/node_modules/xterm/lib/xterm.js"></script>
    <script src="/node_modules/xterm-addon-fit/lib/xterm-addon-fit.js"></script>

    <script>
      // --- Terminal setup ---
      const term = new window.Terminal({
        cursorBlink: true,
        scrollback: 2000,
        fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
        fontSize: 14,
        theme: { background: '#101826', foreground: '#e6e9ef' }
      });
      const fitAddon = new window.FitAddon.FitAddon();
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
    </script>
  </body>
</html>
EOF

# Set proper ownership
sudo chown -R ubuntu:ubuntu /var/lib/instant-terminal
```

### Step 5: Configure Systemd Service

```bash
# Create systemd service file
sudo tee /etc/systemd/system/instant-terminal.service > /dev/null << 'EOF'
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
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable instant-terminal
sudo systemctl start instant-terminal

# Check service status
sudo systemctl status instant-terminal
```

### Step 6: Configure Nginx

```bash
# Create Nginx configuration
sudo tee /etc/nginx/sites-available/instant-terminal > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;

    # Block access to sensitive files and directories
    location ~ /\. {
        deny all;
    }
    
    location ~ \.(json|env|log)$ {
        deny all;
    }

    # Allow access to node_modules for frontend libraries
    location /node_modules/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
    }
    
    location ~ /etc/ {
        deny all;
    }

    location / {
        auth_basic "Tyk Training Environment";
        auth_basic_user_file /etc/nginx/.htpasswd;
        
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
    }
}
EOF

# Enable the site
sudo ln -sf /etc/nginx/sites-available/instant-terminal /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
sudo nginx -t
```

### Step 7: Set Up Basic HTTP Authentication

```bash
# Install apache2-utils for htpasswd
sudo apt install -y apache2-utils

# Create password file
sudo htpasswd -c /etc/nginx/.htpasswd training_user
# Enter password: training123

# Restart Nginx
sudo systemctl restart nginx
```

### Step 8: Configure Firewall (Optional)

```bash
# Allow HTTP traffic
sudo ufw allow 80/tcp
sudo ufw allow 22/tcp
sudo ufw --force enable
```

### Step 9: Test the Deployment

```bash
# Check if all services are running
sudo systemctl status instant-terminal
sudo systemctl status nginx

# Test the application
curl -I http://localhost:3000
curl -I http://localhost

# Check logs if needed
sudo journalctl -u instant-terminal -f
```

## 🔧 Configuration Summary

### Application Details
- **Port**: 3000 (internal), 80 (external via Nginx)
- **User**: `training` (restricted sudo access)
- **Authentication**: Basic HTTP Auth (training_user / training123)
- **Documentation**: Live Tyk docs embedded

### Security Features
- ✅ Basic HTTP Authentication
- ✅ Restricted sudo access for training user
- ✅ File system protection via Nginx
- ✅ No root access for students

### Allowed Commands for Training User
- Package management: `sudo apt-get`, `sudo apt`
- Service management: `sudo systemctl`
- Container tools: `sudo docker`, `sudo docker-compose`
- Development tools: `sudo npm`, `sudo node`, `sudo git`
- File operations: `sudo chmod`, `sudo chown`, `sudo cp`, `sudo mv`
- Text editors: `sudo nano`, `sudo vim`
- System monitoring: `sudo htop`, `sudo netstat`

### Blocked Commands
- ❌ `sudo su` (no root escalation)
- ❌ `sudo sudo` (no privilege escalation)
- ❌ Access to sensitive system files

## 🚨 Troubleshooting

### Common Issues

1. **Service won't start**
   ```bash
   sudo journalctl -u instant-terminal -f
   ```

2. **WebSocket connection fails**
   ```bash
   sudo nginx -t
   sudo systemctl restart nginx
   ```

3. **Permission denied errors**
   ```bash
   sudo chown -R ubuntu:ubuntu /var/lib/instant-terminal
   ```

4. **Authentication issues**
   ```bash
   sudo htpasswd -c /etc/nginx/.htpasswd training_user
   ```

### Log Locations
- Application logs: `sudo journalctl -u instant-terminal`
- Nginx logs: `/var/log/nginx/access.log`, `/var/log/nginx/error.log`
- System logs: `/var/log/syslog`

## 📝 Post-Deployment

1. **Access the application**: `http://YOUR_EC2_IP`
2. **Login credentials**: `training_user` / `training123`
3. **Terminal user**: Students will be logged in as `training` user
4. **Documentation**: Live Tyk docs are embedded in the left panel

## 🔄 Updates and Maintenance

### Updating the Application
```bash
cd /var/lib/instant-terminal
sudo systemctl stop instant-terminal
# Update files
sudo systemctl start instant-terminal
```

### Adding New Sudo Commands
```bash
sudo visudo -f /etc/sudoers.d/training
# Add new commands to the training user line
```

### Changing Authentication
```bash
sudo htpasswd /etc/nginx/.htpasswd new_user
```

---

**Deployment Complete!** 🎉

Your Tyk Training Environment is now ready for students to use. The system provides a secure, isolated environment with controlled access to system resources while maintaining the ability to install and configure Tyk API Gateway.
