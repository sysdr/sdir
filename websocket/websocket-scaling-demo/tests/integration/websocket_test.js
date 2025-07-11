const WebSocket = require('ws');
const assert = require('assert');

class WebSocketIntegrationTest {
    constructor(url = 'ws://localhost:8080') {
        this.url = url;
        this.testResults = [];
    }
    
    async runAllTests() {
        console.log('🧪 Running WebSocket Integration Tests');
        console.log('=====================================\n');
        
        const tests = [
            { name: 'Connection Test', fn: this.testConnection.bind(this) },
            { name: 'Ping/Pong Test', fn: this.testPingPong.bind(this) },
            { name: 'Broadcast Test', fn: this.testBroadcast.bind(this) },
            { name: 'Room Messaging Test', fn: this.testRoomMessaging.bind(this) },
            { name: 'Concurrent Connections Test', fn: this.testConcurrentConnections.bind(this) },
            { name: 'Connection Cleanup Test', fn: this.testConnectionCleanup.bind(this) }
        ];
        
        for (const test of tests) {
            try {
                console.log(`Running: ${test.name}...`);
                await test.fn();
                this.testResults.push({ name: test.name, status: 'PASS' });
                console.log(`✅ ${test.name} PASSED\n`);
            } catch (error) {
                this.testResults.push({ name: test.name, status: 'FAIL', error: error.message });
                console.log(`❌ ${test.name} FAILED: ${error.message}\n`);
            }
        }
        
        this.printSummary();
    }
    
    testConnection() {
        return new Promise((resolve, reject) => {
            const socket = new WebSocket(this.url);
            
            const timeout = setTimeout(() => {
                socket.terminate();
                reject(new Error('Connection timeout'));
            }, 5000);
            
            socket.on('open', () => {
                clearTimeout(timeout);
                socket.close();
            });
            
            socket.on('message', (data) => {
                const message = JSON.parse(data.toString());
                if (message.type === 'welcome') {
                    assert(message.connectionId, 'Should receive connection ID');
                    assert(message.serverInfo, 'Should receive server info');
                    resolve();
                }
            });
            
            socket.on('close', () => {
                resolve();
            });
            
            socket.on('error', (error) => {
                clearTimeout(timeout);
                reject(error);
            });
        });
    }
    
    testPingPong() {
        return new Promise((resolve, reject) => {
            const socket = new WebSocket(this.url);
            
            const timeout = setTimeout(() => {
                socket.terminate();
                reject(new Error('Ping/Pong timeout'));
            }, 5000);
            
            socket.on('open', () => {
                socket.send(JSON.stringify({ type: 'ping', timestamp: Date.now() }));
            });
            
            socket.on('message', (data) => {
                const message = JSON.parse(data.toString());
                if (message.type === 'pong') {
                    clearTimeout(timeout);
                    assert(message.timestamp, 'Should receive timestamp');
                    socket.close();
                    resolve();
                }
            });
            
            socket.on('error', (error) => {
                clearTimeout(timeout);
                reject(error);
            });
        });
    }
    
    testBroadcast() {
        return new Promise((resolve, reject) => {
            const socket1 = new WebSocket(this.url);
            const socket2 = new WebSocket(this.url);
            
            let connectionsReady = 0;
            let messageReceived = false;
            
            const timeout = setTimeout(() => {
                socket1.terminate();
                socket2.terminate();
                reject(new Error('Broadcast test timeout'));
            }, 10000);
            
            const checkReady = () => {
                connectionsReady++;
                if (connectionsReady === 2) {
                    // Both connections ready, send broadcast
                    socket1.send(JSON.stringify({
                        type: 'broadcast',
                        content: 'Test broadcast message'
                    }));
                }
            };
            
            socket1.on('open', checkReady);
            socket2.on('open', checkReady);
            
            socket2.on('message', (data) => {
                const message = JSON.parse(data.toString());
                if (message.type === 'broadcast' && message.message === 'Test broadcast message') {
                    messageReceived = true;
                    clearTimeout(timeout);
                    socket1.close();
                    socket2.close();
                    resolve();
                }
            });
            
            socket1.on('error', reject);
            socket2.on('error', reject);
        });
    }
    
    testRoomMessaging() {
        return new Promise((resolve, reject) => {
            const socket1 = new WebSocket(this.url);
            const socket2 = new WebSocket(this.url);
            
            let connectionsReady = 0;
            let roomJoined = 0;
            
            const timeout = setTimeout(() => {
                socket1.terminate();
                socket2.terminate();
                reject(new Error('Room messaging test timeout'));
            }, 10000);
            
            const checkReady = () => {
                connectionsReady++;
                if (connectionsReady === 2) {
                    // Both connections ready, join room
                    socket1.send(JSON.stringify({ type: 'join_room', room: 'test-room' }));
                    socket2.send(JSON.stringify({ type: 'join_room', room: 'test-room' }));
                }
            };
            
            const checkRoomJoined = () => {
                roomJoined++;
                if (roomJoined === 2) {
                    // Both joined room, send room message
                    socket1.send(JSON.stringify({
                        type: 'room_message',
                        room: 'test-room',
                        content: 'Test room message'
                    }));
                }
            };
            
            socket1.on('open', checkReady);
            socket2.on('open', checkReady);
            
            socket1.on('message', (data) => {
                const message = JSON.parse(data.toString());
                if (message.type === 'room_joined') {
                    checkRoomJoined();
                }
            });
            
            socket2.on('message', (data) => {
                const message = JSON.parse(data.toString());
                if (message.type === 'room_joined') {
                    checkRoomJoined();
                } else if (message.type === 'room_message' && message.content === 'Test room message') {
                    clearTimeout(timeout);
                    socket1.close();
                    socket2.close();
                    resolve();
                }
            });
            
            socket1.on('error', reject);
            socket2.on('error', reject);
        });
    }
    
    async testConcurrentConnections() {
        const connectionCount = 50;
        const connections = [];
        
        try {
            // Create multiple connections simultaneously
            const promises = Array.from({ length: connectionCount }, (_, i) => {
                return new Promise((resolve, reject) => {
                    const socket = new WebSocket(this.url);
                    
                    const timeout = setTimeout(() => {
                        socket.terminate();
                        reject(new Error(`Connection ${i} timeout`));
                    }, 5000);
                    
                    socket.on('open', () => {
                        clearTimeout(timeout);
                        connections.push(socket);
                        resolve();
                    });
                    
                    socket.on('error', reject);
                });
            });
            
            await Promise.all(promises);
            assert.equal(connections.length, connectionCount, `Should create ${connectionCount} connections`);
            
            // Clean up connections
            await Promise.all(connections.map(socket => {
                return new Promise(resolve => {
                    socket.close();
                    setTimeout(resolve, 100);
                });
            }));
            
        } catch (error) {
            // Clean up any remaining connections
            connections.forEach(socket => socket.terminate());
            throw error;
        }
    }
    
    async testConnectionCleanup() {
        // Test that server properly cleans up closed connections
        const socket = new WebSocket(this.url);
        
        await new Promise((resolve, reject) => {
            socket.on('open', resolve);
            socket.on('error', reject);
        });
        
        // Abruptly terminate connection
        socket.terminate();
        
        // Wait a bit for server cleanup
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        // Create new connection to verify server is still healthy
        const newSocket = new WebSocket(this.url);
        
        await new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
                newSocket.terminate();
                reject(new Error('Server cleanup test failed'));
            }, 5000);
            
            newSocket.on('open', () => {
                clearTimeout(timeout);
                newSocket.close();
                resolve();
            });
            
            newSocket.on('error', reject);
        });
    }
    
    printSummary() {
        console.log('📋 Test Summary');
        console.log('===============');
        
        const passed = this.testResults.filter(r => r.status === 'PASS').length;
        const failed = this.testResults.filter(r => r.status === 'FAIL').length;
        
        console.log(`Total tests: ${this.testResults.length}`);
        console.log(`Passed: ${passed}`);
        console.log(`Failed: ${failed}`);
        
        if (failed > 0) {
            console.log('\nFailed tests:');
            this.testResults.filter(r => r.status === 'FAIL').forEach(test => {
                console.log(`  ❌ ${test.name}: ${test.error}`);
            });
        }
        
        console.log(`\nOverall result: ${failed === 0 ? '✅ ALL TESTS PASSED' : '❌ SOME TESTS FAILED'}`);
    }
}

// Run tests if called directly
if (require.main === module) {
    const url = process.argv[2] || 'ws://localhost:8080';
    const tester = new WebSocketIntegrationTest(url);
    
    tester.runAllTests().catch(error => {
        console.error('Test suite error:', error);
        process.exit(1);
    });
}

module.exports = WebSocketIntegrationTest;
