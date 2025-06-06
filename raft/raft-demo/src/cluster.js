const RaftNode = require('./raft-node');
const EventEmitter = require('events');

class RaftCluster extends EventEmitter {
    constructor(size) {
        super();
        this.nodes = [];
        this.partitions = new Set();
        
        // Create nodes
        for (let i = 0; i < size; i++) {
            const node = new RaftNode(i, []);
            this.nodes.push(node);
            
            // Forward events
            node.on('stateChange', (data) => this.emit('stateChange', data));
            node.on('log', (data) => this.emit('log', data));
            node.on('logEntry', (data) => this.emit('logEntry', data));
            node.on('partition', (data) => this.emit('partition', data));
            node.on('reconnect', (data) => this.emit('reconnect', data));
        }
        
        // Set cluster reference for each node
        this.nodes.forEach(node => {
            node.cluster = this.nodes.filter(n => !this.partitions.has(n.nodeId));
        });
    }
    
    getLeader() {
        return this.nodes.find(node => node.state === 'leader' && !this.partitions.has(node.nodeId));
    }
    
    addEntry(data) {
        const leader = this.getLeader();
        if (leader) {
            return leader.addEntry(data);
        }
        return false;
    }
    
    partitionNode(nodeId) {
        this.partitions.add(nodeId);
        const node = this.nodes[nodeId];
        if (node) {
            node.partition();
            // Update cluster view for all nodes
            this.nodes.forEach(n => {
                n.cluster = this.nodes.filter(node => !this.partitions.has(node.nodeId));
            });
        }
    }
    
    reconnectNode(nodeId) {
        this.partitions.delete(nodeId);
        const node = this.nodes[nodeId];
        if (node) {
            node.reconnect();
            // Update cluster view for all nodes
            this.nodes.forEach(n => {
                n.cluster = this.nodes.filter(node => !this.partitions.has(node.nodeId));
            });
        }
    }
    
    getStatus() {
        return this.nodes.map(node => ({
            ...node.getStatus(),
            isPartitioned: this.partitions.has(node.nodeId)
        }));
    }
    
    stop() {
        this.nodes.forEach(node => {
            node.clearElectionTimer();
            node.clearHeartbeatTimer();
        });
    }
}

module.exports = RaftCluster;
