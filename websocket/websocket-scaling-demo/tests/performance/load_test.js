const WebSocket = require('ws');

class LoadTester {
    constructor(options = {}) {
        this.url = options.url || 'ws://localhost:8080';
        this.connections = options.connections || 100;
        this.messagesPerSecond = options.messagesPerSecond || 10;
        this.duration = options.duration || 60000; // 1 minute
        
        this.connectedSockets = [];
        this.stats = {
            connected: 0,
            disconnected: 0,
            messagesSent: 0,
            messagesReceived: 0,
            errors: 0,
            startTime: null,
            endTime: null
        };
    }
    
    async run() {
        console.log(`🚀 Starting load test:`);
        console.log(`   URL: ${this.url}`);
        console.log(`   Connections: ${this.connections}`);
        console.log(`   Messages/sec: ${this.messagesPerSecond}`);
        console.log(`   Duration: ${this.duration}ms`);
        console.log('');
        
        this.stats.startTime = Date.now();
        
        // Create connections
        await this.createConnections();
        
        // Start sending messages
        this.startMessageSending();
        
        // Run for specified duration
        await new Promise(resolve => setTimeout(resolve, this.duration));
        
        // Clean up
        await this.cleanup();
        
        this.stats.endTime = Date.now();
        this.printResults();
    }
    
    async createConnections() {
        console.log('📡 Creating connections...');
        
        const promises = [];
        for (let i = 0; i < this.connections; i++) {
            promises.push(this.createConnection(i));
            
            // Add small delay to avoid overwhelming the server
            if (i % 10 === 0) {
                await new Promise(resolve => setTimeout(resolve, 100));
            }
        }
        
        await Promise.all(promises);
        console.log(`✅ Created ${this.connectedSockets.length} connections`);
    }
    
    createConnection(index) {
        return new Promise((resolve, reject) => {
            const socket = new WebSocket(this.url);
            
            const timeout = setTimeout(() => {
                socket.terminate();
                this.stats.errors++;
                resolve();
            }, 5000);
            
            socket.on('open', () => {
                clearTimeout(timeout);
                this.stats.connected++;
                this.connectedSockets.push(socket);
                resolve();
            });
            
            socket.on('message', (data) => {
                this.stats.messagesReceived++;
            });
            
            socket.on('close', () => {
                this.stats.disconnected++;
            });
            
            socket.on('error', (error) => {
                clearTimeout(timeout);
                this.stats.errors++;
                resolve();
            });
        });
    }
    
    startMessageSending() {
        console.log('📨 Starting message transmission...');
        
        const messageInterval = 1000 / this.messagesPerSecond;
        
        const sendMessage = () => {
            if (this.connectedSockets.length === 0) return;
            
            const socket = this.connectedSockets[Math.floor(Math.random() * this.connectedSockets.length)];
            
            if (socket.readyState === WebSocket.OPEN) {
                const message = JSON.stringify({
                    type: 'broadcast',
                    content: `Load test message ${this.stats.messagesSent}`,
                    timestamp: Date.now()
                });
                
                socket.send(message);
                this.stats.messagesSent++;
            }
        };
        
        this.messageIntervalId = setInterval(sendMessage, messageInterval);
    }
    
    async cleanup() {
        console.log('🧹 Cleaning up connections...');
        
        if (this.messageIntervalId) {
            clearInterval(this.messageIntervalId);
        }
        
        const closePromises = this.connectedSockets.map(socket => {
            return new Promise(resolve => {
                if (socket.readyState === WebSocket.OPEN) {
                    socket.close();
                }
                setTimeout(resolve, 100);
            });
        });
        
        await Promise.all(closePromises);
    }
    
    printResults() {
        const duration = this.stats.endTime - this.stats.startTime;
        const durationSeconds = duration / 1000;
        
        console.log('\n📊 Load Test Results:');
        console.log('='.repeat(50));
        console.log(`Duration: ${durationSeconds.toFixed(2)} seconds`);
        console.log(`Connections created: ${this.stats.connected}`);
        console.log(`Connections failed: ${this.stats.errors}`);
        console.log(`Messages sent: ${this.stats.messagesSent}`);
        console.log(`Messages received: ${this.stats.messagesReceived}`);
        console.log(`Average send rate: ${(this.stats.messagesSent / durationSeconds).toFixed(2)} msg/sec`);
        console.log(`Average receive rate: ${(this.stats.messagesReceived / durationSeconds).toFixed(2)} msg/sec`);
        console.log(`Success rate: ${((this.stats.connected / this.connections) * 100).toFixed(2)}%`);
    }
}

// Run load test if called directly
if (require.main === module) {
    const args = process.argv.slice(2);
    const options = {};
    
    for (let i = 0; i < args.length; i += 2) {
        const key = args[i].replace('--', '');
        const value = args[i + 1];
        
        switch (key) {
            case 'url':
                options.url = value;
                break;
            case 'connections':
                options.connections = parseInt(value);
                break;
            case 'rate':
                options.messagesPerSecond = parseInt(value);
                break;
            case 'duration':
                options.duration = parseInt(value) * 1000;
                break;
        }
    }
    
    const tester = new LoadTester(options);
    tester.run().catch(console.error);
}

module.exports = LoadTester;
