class WebSocketScalingDemo {
    constructor() {
        this.socket = null;
        this.connectionId = null;
        this.isConnected = false;
        this.messageCount = 0;
        this.startTime = null;
        this.loadTestConnections = [];
        this.loadTestInterval = null;
        this.metricsInterval = null;
        
        this.initializeUI();
        this.setupEventListeners();
        this.startMetricsRefresh();
    }
    
    initializeUI() {
        this.elements = {
            serverUrl: document.getElementById('serverUrl'),
            connectBtn: document.getElementById('connectBtn'),
            disconnectBtn: document.getElementById('disconnectBtn'),
            connectionStatus: document.getElementById('connectionStatus'),
            uptime: document.getElementById('uptime'),
            messageCount: document.getElementById('messageCount'),
            messageType: document.getElementById('messageType'),
            roomGroup: document.getElementById('roomGroup'),
            roomName: document.getElementById('roomName'),
            messageContent: document.getElementById('messageContent'),
            sendMessage: document.getElementById('sendMessage'),
            connectionCount: document.getElementById('connectionCount'),
            messageRate: document.getElementById('messageRate'),
            startLoadTest: document.getElementById('startLoadTest'),
            stopLoadTest: document.getElementById('stopLoadTest'),
            loadProgress: document.getElementById('loadProgress'),
            loadStatus: document.getElementById('loadStatus'),
            refreshMetrics: document.getElementById('refreshMetrics'),
            clearLog: document.getElementById('clearLog'),
            messageLog: document.getElementById('messageLog'),
            activeConnections: document.getElementById('activeConnections'),
            memoryUsage: document.getElementById('memoryUsage'),
            messagesPerSecond: document.getElementById('messagesPerSecond'),
            serverUptime: document.getElementById('serverUptime')
        };
    }
    
    setupEventListeners() {
        this.elements.connectBtn.addEventListener('click', () => this.connect());
        this.elements.disconnectBtn.addEventListener('click', () => this.disconnect());
        this.elements.sendMessage.addEventListener('click', () => this.sendMessage());
        this.elements.messageType.addEventListener('change', () => this.handleMessageTypeChange());
        this.elements.startLoadTest.addEventListener('click', () => this.startLoadTest());
        this.elements.stopLoadTest.addEventListener('click', () => this.stopLoadTest());
        this.elements.refreshMetrics.addEventListener('click', () => this.refreshMetrics());
        this.elements.clearLog.addEventListener('click', () => this.clearLog());
        
        // Enter key to send message
        this.elements.messageContent.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                this.sendMessage();
            }
        });
    }
    
    connect() {
        const url = this.elements.serverUrl.value.trim();
        if (!url) {
            this.logMessage('Error: Please enter a server URL', 'error');
            return;
        }
        
        this.updateConnectionStatus('connecting', 'Connecting...');
        this.elements.connectBtn.disabled = true;
        
        try {
            this.socket = new WebSocket(url);
            
            this.socket.onopen = () => {
                this.isConnected = true;
                this.startTime = Date.now();
                this.updateConnectionStatus('connected', 'Connected');
                this.elements.connectBtn.disabled = true;
                this.elements.disconnectBtn.disabled = false;
                this.elements.sendMessage.disabled = false;
                this.logMessage('Connected to server', 'system');
                this.startUptimeCounter();
            };
            
            this.socket.onmessage = (event) => {
                this.handleMessage(JSON.parse(event.data));
            };
            
            this.socket.onclose = () => {
                this.isConnected = false;
                this.updateConnectionStatus('disconnected', 'Disconnected');
                this.elements.connectBtn.disabled = false;
                this.elements.disconnectBtn.disabled = true;
                this.elements.sendMessage.disabled = true;
                this.logMessage('Disconnected from server', 'system');
            };
            
            this.socket.onerror = (error) => {
                this.logMessage(`Connection error: ${error.message || 'Unknown error'}`, 'error');
                this.updateConnectionStatus('disconnected', 'Connection Failed');
                this.elements.connectBtn.disabled = false;
            };
            
        } catch (error) {
            this.logMessage(`Failed to connect: ${error.message}`, 'error');
            this.updateConnectionStatus('disconnected', 'Connection Failed');
            this.elements.connectBtn.disabled = false;
        }
    }
    
    disconnect() {
        if (this.socket) {
            this.socket.close();
        }
        this.stopLoadTest();
    }
    
    handleMessage(message) {
        this.messageCount++;
        this.elements.messageCount.textContent = this.messageCount.toLocaleString();
        
        switch (message.type) {
            case 'welcome':
                this.connectionId = message.connectionId;
                this.logMessage(`Welcome! Connection ID: ${this.connectionId}`, 'received');
                this.logMessage(`Server PID: ${message.serverInfo.pid}, Total Connections: ${message.serverInfo.totalConnections}`, 'system');
                break;
                
            case 'pong':
                const latency = Date.now() - message.timestamp;
                this.logMessage(`Pong received (${latency}ms latency)`, 'received');
                break;
                
            case 'broadcast':
                this.logMessage(`Broadcast from ${message.from}: ${message.message}`, 'received');
                break;
                
            case 'room_message':
                this.logMessage(`Room ${message.room} - ${message.from}: ${message.content}`, 'received');
                break;
                
            case 'room_joined':
                this.logMessage(`Joined room: ${message.room}`, 'system');
                break;
                
            case 'room_left':
                this.logMessage(`Left room: ${message.room}`, 'system');
                break;
                
            default:
                this.logMessage(`Received: ${JSON.stringify(message)}`, 'received');
        }
    }
    
    sendMessage() {
        if (!this.isConnected || !this.socket) {
            this.logMessage('Not connected to server', 'error');
            return;
        }
        
        const messageType = this.elements.messageType.value;
        const content = this.elements.messageContent.value.trim();
        
        if (!content && messageType !== 'ping') {
            this.logMessage('Please enter a message', 'error');
            return;
        }
        
        let message = { type: messageType };
        
        switch (messageType) {
            case 'broadcast':
                message.content = content;
                break;
                
            case 'room_message':
                const room = this.elements.roomName.value.trim();
                if (!room) {
                    this.logMessage('Please enter a room name', 'error');
                    return;
                }
                message.room = room;
                message.content = content;
                break;
                
            case 'ping':
                message.timestamp = Date.now();
                break;
        }
        
        this.socket.send(JSON.stringify(message));
        this.logMessage(`Sent ${messageType}: ${content || 'ping'}`, 'sent');
        this.elements.messageContent.value = '';
    }
    
    handleMessageTypeChange() {
        const messageType = this.elements.messageType.value;
        this.elements.roomGroup.style.display = messageType === 'room_message' ? 'block' : 'none';
    }
    
    async startLoadTest() {
        const connectionCount = parseInt(this.elements.connectionCount.value);
        const messageRate = parseInt(this.elements.messageRate.value);
        
        if (connectionCount < 1 || messageRate < 1) {
            this.logMessage('Invalid load test parameters', 'error');
            return;
        }
        
        this.elements.startLoadTest.disabled = true;
        this.elements.stopLoadTest.disabled = false;
        this.elements.loadStatus.textContent = 'Creating connections...';
        
        this.logMessage(`Starting load test: ${connectionCount} connections, ${messageRate} msg/sec`, 'system');
        
        // Create connections gradually to avoid overwhelming the server
        for (let i = 0; i < connectionCount; i++) {
            setTimeout(() => {
                this.createLoadTestConnection(i, messageRate);
                const progress = ((i + 1) / connectionCount) * 100;
                this.elements.loadProgress.style.width = `${progress}%`;
                
                if (i === connectionCount - 1) {
                    this.elements.loadStatus.textContent = `Running (${connectionCount} connections)`;
                }
            }, i * 50); // 50ms delay between connections
        }
    }
    
    createLoadTestConnection(index, messageRate) {
        const url = this.elements.serverUrl.value.trim();
        const socket = new WebSocket(url);
        
        socket.onopen = () => {
            this.loadTestConnections.push(socket);
            
            // Send periodic messages
            const interval = setInterval(() => {
                if (socket.readyState === WebSocket.OPEN) {
                    socket.send(JSON.stringify({
                        type: 'broadcast',
                        content: `Load test message from connection ${index}`
                    }));
                } else {
                    clearInterval(interval);
                }
            }, 1000 / messageRate);
        };
        
        socket.onerror = (error) => {
            this.logMessage(`Load test connection ${index} error: ${error.message}`, 'error');
        };
    }
    
    stopLoadTest() {
        this.elements.startLoadTest.disabled = false;
        this.elements.stopLoadTest.disabled = true;
        this.elements.loadStatus.textContent = 'Stopping...';
        this.elements.loadProgress.style.width = '0%';
        
        // Close all load test connections
        this.loadTestConnections.forEach(socket => {
            if (socket.readyState === WebSocket.OPEN) {
                socket.close();
            }
        });
        
        this.loadTestConnections = [];
        this.elements.loadStatus.textContent = 'Ready';
        this.logMessage('Load test stopped', 'system');
    }
    
    async refreshMetrics() {
        try {
            const response = await fetch(`${this.getHttpUrl()}/metrics`);
            const metrics = await response.json();
            
            this.elements.activeConnections.textContent = metrics.connections.toLocaleString();
            this.elements.memoryUsage.textContent = Math.round(metrics.memory.heapUsed / 1024 / 1024);
            this.elements.messagesPerSecond.textContent = Math.round(metrics.messagesProcessed / ((Date.now() - metrics.startTime) / 1000));
            this.elements.serverUptime.textContent = this.formatDuration(Date.now() - metrics.startTime);
            
        } catch (error) {
            this.logMessage(`Failed to fetch metrics: ${error.message}`, 'error');
        }
    }
    
    startMetricsRefresh() {
        this.metricsInterval = setInterval(() => {
            if (this.isConnected) {
                this.refreshMetrics();
            }
        }, 5000); // Refresh every 5 seconds
    }
    
    updateConnectionStatus(status, text) {
        const statusElement = this.elements.connectionStatus;
        statusElement.className = `connection-status ${status}`;
        statusElement.innerHTML = `
            <span class="material-icons">${status === 'connected' ? 'wifi' : status === 'connecting' ? 'wifi_protected_setup' : 'wifi_off'}</span>
            <span>${text}</span>
        `;
    }
    
    startUptimeCounter() {
        setInterval(() => {
            if (this.isConnected && this.startTime) {
                const uptime = Date.now() - this.startTime;
                this.elements.uptime.textContent = this.formatDuration(uptime);
            }
        }, 1000);
    }
    
    formatDuration(ms) {
        const seconds = Math.floor(ms / 1000);
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const secs = seconds % 60;
        
        return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }
    
    getHttpUrl() {
        const wsUrl = this.elements.serverUrl.value.trim();
        return wsUrl.replace('ws://', 'http://').replace('wss://', 'https://');
    }
    
    logMessage(message, type = 'system') {
        const timestamp = new Date().toLocaleTimeString();
        const logEntry = document.createElement('div');
        logEntry.className = `log-entry ${type}`;
        logEntry.innerHTML = `
            <span class="timestamp">[${timestamp}]</span>
            <span class="message">${message}</span>
        `;
        
        this.elements.messageLog.appendChild(logEntry);
        this.elements.messageLog.scrollTop = this.elements.messageLog.scrollHeight;
        
        // Limit log entries to prevent memory issues
        const entries = this.elements.messageLog.children;
        if (entries.length > 100) {
            this.elements.messageLog.removeChild(entries[0]);
        }
    }
    
    clearLog() {
        this.elements.messageLog.innerHTML = `
            <div class="log-entry system">
                <span class="timestamp">[${new Date().toLocaleTimeString()}]</span>
                <span class="message">Log cleared.</span>
            </div>
        `;
    }
}

// Initialize the demo when the page loads
document.addEventListener('DOMContentLoaded', () => {
    new WebSocketScalingDemo();
});
