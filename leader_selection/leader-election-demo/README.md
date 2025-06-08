# 🏛️ Leader Election Algorithm Demonstration

This demonstration implements a simplified Raft consensus algorithm to showcase leader election behavior in distributed systems.

## 🚀 Quick Start

### Method 1: Using Python (Local Development)
```bash
# Install dependencies
pip install -r requirements.txt

# Start 5-node cluster
python cluster.py

# Or specify custom number of nodes (minimum 3)
python cluster.py 7
```

### Method 2: Using Docker
```bash
# Build and run cluster
docker-compose up --build

# Or run individual nodes for testing
docker-compose --profile individual up
```

## 🌐 Accessing the Demonstration

Once started, you can access:

- **Node Dashboards**: http://localhost:8001, http://localhost:8002, etc.
- **Each dashboard shows**:
  - Current node state (Follower/Candidate/Leader)
  - Current term and leader information
  - Real-time statistics
  - Ability to simulate failures

## 🧪 Testing Scenarios

### Automated Tests
```bash
# Run comprehensive test suite
python test_scenarios.py
```

### Manual Testing
1. **Leader Election**: Watch initial leader emerge
2. **Leader Failure**: Click "Simulate Failure" on leader node
3. **Network Partitions**: Simulate failures on multiple nodes
4. **Recovery**: Watch cluster heal after failures

## 📊 Key Observations

### What to Watch For:

1. **Election Process**:
   - Randomized timeouts prevent election storms
   - Candidates request votes from all peers
   - Majority votes required for leadership

2. **Heartbeat Mechanism**:
   - Leaders send periodic heartbeats (100ms)
   - Followers reset election timeouts on heartbeat
   - Failed heartbeats trigger new elections

3. **Term Management**:
   - Terms increase with each election
   - Higher terms always win
   - Prevents split-brain scenarios

4. **Fault Tolerance**:
   - System continues with majority nodes
   - Automatic recovery after failures
   - Consistent state across cluster

## 🔧 Configuration

Key parameters (in `node.py`):
- `heartbeat_interval`: 100ms (how often leader sends heartbeats)
- `election_timeout`: 150-300ms randomized (when to start election)
- Ports: 8001-8005 (can be customized)

## 📈 Monitoring

Each node provides:
- Real-time state transitions
- Election statistics
- Network communication metrics
- Performance counters

## 🐛 Troubleshooting

**No leader elected**: Check if majority of nodes are running
**Frequent elections**: Network issues or timeout configuration
**Split brain**: Impossible due to majority vote requirement

## 🏗️ Architecture

The implementation includes:
- **Raft state machine**: Follower → Candidate → Leader
- **RPC communication**: Vote requests and heartbeats
- **Fault injection**: Simulate real-world failures
- **Web interface**: Real-time monitoring
- **Docker support**: Easy deployment

## 📚 Learning Outcomes

After running this demonstration, you'll understand:
- How distributed consensus works
- Why randomization prevents election storms
- How term numbers provide ordering
- Why majority votes prevent split-brain
- How systems heal after network partitions

## 🔗 Production Considerations

This demo simplifies several aspects for clarity:
- No persistent storage (logs reset on restart)
- No log replication (focus on leader election)
- Simplified network failure simulation
- No Byzantine fault tolerance

For production use, consider mature implementations like:
- HashiCorp Raft
- etcd Raft
- Consul Consensus

---

🎓 **Educational Note**: This implementation prioritizes clarity over performance. Real production systems include optimizations like batching, pipelining, and advanced failure detection.
