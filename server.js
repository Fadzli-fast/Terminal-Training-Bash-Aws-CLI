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
  
  const shell = os.platform() === 'win32' ? 'powershell.exe' : process.env.SHELL || 'bash';
  
  const ptyProcess = pty.spawn(shell, [], {
    name: 'xterm-256color',
    cols: 120,
    rows: 30,
    cwd: process.env.HOME,
    env: { 
      ...process.env, 
      TERM: 'xterm-256color',
      COLORTERM: 'truecolor',
      FORCE_COLOR: '1'
    },
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
