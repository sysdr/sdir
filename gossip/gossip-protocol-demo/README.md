# Gossip Protocol Demonstration

This project demonstrates a complete implementation of gossip protocols with SWIM-based failure detection.

## Features

- **Multi-node gossip network** with configurable parameters
- **SWIM failure detection** with indirect ping mechanism  
- **Real-time web interface** for each node
- **Vector clock synchronization** for causality tracking
- **Rumor mongering with excitement cooling** to prevent gossip storms
- **Anti-entropy synchronization** for eventual consistency
- **Network topology visualization** and live statistics

## Quick Start

### Option 1: Run Locally

```bash
# Install dependencies
pip install -r requirements.txt

# Start the gossip network (5 nodes)
python start_network.py

# In another terminal, run tests
python test_gossip.py
```

### Option 2: Run with Docker

```bash
# Build and run
docker-compose up --build

# In another terminal, run tests
docker exec gossip-demo python test_gossip.py
```

## Web Interface

Each node runs a web interface:

- Node 1: http://localhost:9001
- Node 2: http://localhost:9002  
- Node 3: http://localhost:9003
- Node 4: http://localhost:9004
- Node 5: http://localhost:9005

## Demonstration Steps

1. **Start the network**: `python start_network.py`

2. **Open web interfaces**: Visit the URLs above in your browser

3. **Add data**: Use any node's web interface to add key-value pairs

4. **Watch propagation**: Observe how data spreads across all nodes via gossip

5. **Monitor statistics**: See message counts, gossip rounds, and network topology

6. **Test failure detection**: Stop a node and watch others detect the failure

7. **Verify consistency**: Check that all alive nodes have the same data

## Key Concepts Demonstrated

### Gossip Propagation
- Exponential information spread with O(log N) convergence
- Rumor mongering with excitement-based cooling
- Configurable fanout and gossip intervals

### SWIM Failure Detection  
- Direct ping with timeout
- Indirect ping through witnesses
- Suspicion and failure states

### Anti-Entropy Synchronization
- Vector clock-based ordering
- Delta synchronization to minimize bandwidth
- Conflict resolution for concurrent updates

### Performance Characteristics
- Message complexity: O(N log N) per gossip round
- Convergence time: O(log N) rounds
- Fault tolerance: Up to N/2 node failures

## Configuration Parameters

Edit `gossip_node.py` to adjust:

```python
self.gossip_interval = 2.0      # Gossip frequency (seconds)
self.fanout = 3                 # Nodes to gossip with per round  
self.max_excitement = 10        # Initial rumor excitement
self.ping_timeout = 1.0         # SWIM ping timeout
self.ping_interval = 5.0        # SWIM ping frequency
```

## Architecture

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Node 1    │◄──►│   Node 2    │◄──►│   Node 3    │
│  Port 9001  │    │  Port 9002  │    │  Port 9003  │
└─────────────┘    └─────────────┘    └─────────────┘
       ▲                  ▲                  ▲
       │                  │                  │
       ▼                  ▼                  ▼
┌─────────────┐    ┌─────────────┐
│   Node 4    │◄──►│   Node 5    │
│  Port 9004  │    │  Port 9005  │  
└─────────────┘    └─────────────┘
```

Each node:
- Maintains local data store
- Runs gossip protocol loop
- Performs SWIM failure detection
- Serves web interface
- Provides REST API

## Testing

The test suite verifies:

- ✅ Data propagation across all nodes
- ✅ Convergence within expected time
- ✅ Message delivery statistics  
- ✅ Network connectivity monitoring
- ✅ Vector clock synchronization

## Production Considerations

This demo shows the core concepts. For production use, consider:

- **Security**: Add authentication and message encryption
- **Persistence**: Store data to disk with WAL
- **Monitoring**: Integrate with metrics systems (Prometheus, etc.)
- **Configuration**: Use external config files
- **Clustering**: Support dynamic membership changes
- **Performance**: Optimize message serialization and networking

## References

- [SWIM Paper](https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf)
- [Gossip Protocols Survey](https://zoo.cs.yale.edu/classes/cs426/2013/bib/demers87epidemic.pdf)
- [Amazon DynamoDB](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf)
- [Apache Cassandra Gossip](https://cassandra.apache.org/doc/latest/architecture/gossip.html)
