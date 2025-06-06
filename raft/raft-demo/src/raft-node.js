const EventEmitter = require('events');
const chalk = require('chalk').default || require('chalk');

class RaftNode extends EventEmitter {
    constructor(nodeId, cluster) {
        super();
        this.nodeId = nodeId;
        this.cluster = cluster;
        this.state = 'follower';
        this.currentTerm = 0;
        this.votedFor = null;
        this.logEntries = [];  // Renamed to avoid conflict with log method
        this.commitIndex = 0;
        this.lastApplied = 0;
        
        // Leader state
        this.nextIndex = {};
        this.matchIndex = {};
        
        // Timing
        this.electionTimeout = this.randomElectionTimeout();
        this.heartbeatInterval = 50; // 50ms heartbeat
        this.lastHeartbeat = Date.now();
        
        // Timers
        this.electionTimer = null;
        this.heartbeatTimer = null;
        
        this.startElectionTimer();
        this.logMessage(`Node ${this.nodeId} initialized as follower`);
    }
    
    randomElectionTimeout() {
        return 150 + Math.random() * 150; // 150-300ms
    }
    
    logMessage(message, level = 'info') {
        const timestamp = new Date().toISOString().substr(11, 12);
        let coloredMessage;
        switch (level) {
            case 'info':
                coloredMessage = chalk.blue(message);
                break;
            case 'warn':
                coloredMessage = chalk.yellow(message);
                break;
            case 'error':
                coloredMessage = chalk.red(message);
                break;
            case 'success':
                coloredMessage = chalk.green(message);
                break;
            default:
                coloredMessage = message;
        }
        console.log(`${timestamp} [Node-${this.nodeId}] ${coloredMessage}`);
        this.emit('log', { nodeId: this.nodeId, message, level, timestamp });
    }
    
    startElectionTimer() {
        this.clearElectionTimer();
        this.electionTimer = setTimeout(() => {
            this.startElection();
        }, this.electionTimeout);
    }
    
    clearElectionTimer() {
        if (this.electionTimer) {
            clearTimeout(this.electionTimer);
            this.electionTimer = null;
        }
    }
    
    startHeartbeatTimer() {
        this.clearHeartbeatTimer();
        this.heartbeatTimer = setInterval(() => {
            this.sendHeartbeats();
        }, this.heartbeatInterval);
    }
    
    clearHeartbeatTimer() {
        if (this.heartbeatTimer) {
            clearInterval(this.heartbeatTimer);
            this.heartbeatTimer = null;
        }
    }
    
    startElection() {
        this.state = 'candidate';
        this.currentTerm++;
        this.votedFor = this.nodeId;
        this.lastHeartbeat = Date.now();
        
        this.logMessage(`Starting election for term ${this.currentTerm}`, 'warn');
        this.emit('stateChange', { nodeId: this.nodeId, state: this.state, term: this.currentTerm });
        
        let votesReceived = 1; // Vote for self
        let votesNeeded = Math.floor(this.cluster.length / 2) + 1;
        
        // Request votes from other nodes
        this.cluster.forEach(node => {
            if (node.nodeId !== this.nodeId) {
                const response = node.requestVote(this.currentTerm, this.nodeId, this.logEntries.length - 1, 
                    this.logEntries.length > 0 ? this.logEntries[this.logEntries.length - 1].term : 0);
                
                if (response.voteGranted) {
                    votesReceived++;
                    this.logMessage(`Received vote from Node ${node.nodeId}`);
                }
            }
        });
        
        if (votesReceived >= votesNeeded) {
            this.becomeLeader();
        } else {
            this.becomeFollower();
            this.logMessage(`Election failed, got ${votesReceived}/${votesNeeded} votes`);
        }
    }
    
    becomeLeader() {
        this.state = 'leader';
        this.logMessage(`Became leader for term ${this.currentTerm}`, 'success');
        this.emit('stateChange', { nodeId: this.nodeId, state: this.state, term: this.currentTerm });
        
        // Initialize leader state
        this.cluster.forEach(node => {
            if (node.nodeId !== this.nodeId) {
                this.nextIndex[node.nodeId] = this.logEntries.length;
                this.matchIndex[node.nodeId] = 0;
            }
        });
        
        this.clearElectionTimer();
        this.startHeartbeatTimer();
        this.sendHeartbeats();
    }
    
    becomeFollower() {
        this.state = 'follower';
        this.clearHeartbeatTimer();
        this.startElectionTimer();
        this.emit('stateChange', { nodeId: this.nodeId, state: this.state, term: this.currentTerm });
    }
    
    requestVote(term, candidateId, lastLogIndex, lastLogTerm) {
        if (term < this.currentTerm) {
            return { term: this.currentTerm, voteGranted: false };
        }
        
        if (term > this.currentTerm) {
            this.currentTerm = term;
            this.votedFor = null;
            this.becomeFollower();
        }
        
        const logUpToDate = (lastLogTerm > (this.logEntries.length > 0 ? this.logEntries[this.logEntries.length - 1].term : 0)) ||
                           (lastLogTerm === (this.logEntries.length > 0 ? this.logEntries[this.logEntries.length - 1].term : 0) && 
                            lastLogIndex >= this.logEntries.length - 1);
        
        if ((this.votedFor === null || this.votedFor === candidateId) && logUpToDate) {
            this.votedFor = candidateId;
            this.lastHeartbeat = Date.now();
            this.startElectionTimer();
            this.logMessage(`Granted vote to Node ${candidateId} for term ${term}`);
            return { term: this.currentTerm, voteGranted: true };
        }
        
        return { term: this.currentTerm, voteGranted: false };
    }
    
    sendHeartbeats() {
        if (this.state !== 'leader') return;
        
        this.cluster.forEach(node => {
            if (node.nodeId !== this.nodeId) {
                node.receiveAppendEntries(this.currentTerm, this.nodeId, 
                    this.logEntries.length - 1, 
                    this.logEntries.length > 0 ? this.logEntries[this.logEntries.length - 1].term : 0,
                    [], this.commitIndex);
            }
        });
    }
    
    receiveAppendEntries(term, leaderId, prevLogIndex, prevLogTerm, entries, leaderCommit) {
        if (term < this.currentTerm) {
            return { term: this.currentTerm, success: false };
        }
        
        if (term > this.currentTerm) {
            this.currentTerm = term;
            this.votedFor = null;
        }
        
        this.lastHeartbeat = Date.now();
        this.becomeFollower();
        
        // Log consistency check would go here in full implementation
        // For demo purposes, we'll accept all entries
        
        return { term: this.currentTerm, success: true };
    }
    
    addEntry(data) {
        if (this.state !== 'leader') {
            return false;
        }
        
        const entry = {
            term: this.currentTerm,
            index: this.logEntries.length,
            data: data,
            timestamp: Date.now()
        };
        
        this.logEntries.push(entry);
        this.logMessage(`Added entry: ${data}`, 'success');
        this.emit('logEntry', { nodeId: this.nodeId, entry });
        
        return true;
    }
    
    getStatus() {
        return {
            nodeId: this.nodeId,
            state: this.state,
            term: this.currentTerm,
            logLength: this.logEntries.length,
            isAlive: true
        };
    }
    
    partition() {
        this.clearElectionTimer();
        this.clearHeartbeatTimer();
        this.logMessage(`Node partitioned from cluster`, 'error');
        this.emit('partition', { nodeId: this.nodeId });
    }
    
    reconnect() {
        this.becomeFollower();
        this.logMessage(`Node reconnected to cluster`, 'success');
        this.emit('reconnect', { nodeId: this.nodeId });
    }
}

module.exports = RaftNode;
