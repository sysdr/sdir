# Split-Brain Prevention Demo

This demonstration shows how distributed systems prevent split-brain scenarios using consensus algorithms and quorum-based decision making.

## Quick Start

```bash
./run_demo.sh
```

Then open http://localhost:8000 in your browser.

## What You'll Learn

- How split-brain scenarios occur in distributed systems
- Raft consensus algorithm in action
- Quorum-based split-brain prevention
- Network partition effects on consensus
- Real-time visualization of distributed system behavior

## Demo Scenarios

1. **Simple Split**: 3-2 partition where majority group remains active
2. **Minority Partition**: 2-3 partition where minority loses quorum
3. **Even Split**: 2-2 partition where no group has majority

## Architecture

The demo implements a simplified Raft-like consensus algorithm with:
- Leader election with randomized timeouts
- Heartbeat mechanism for failure detection
- Quorum-based decision making
- Network partition simulation
- Real-time web interface with WebSocket updates

## Files Structure

- `src/node.py`: Distributed node implementation
- `src/server.py`: Web server and API
- `templates/dashboard.html`: Interactive web interface
- `test_demo.py`: Automated test suite
- `docker-compose.yml`: Container orchestration

## Testing

```bash
# Run automated tests
python test_demo.py

# Manual testing via web interface
# 1. Create cluster
# 2. Simulate partitions
# 3. Observe consensus behavior
# 4. Heal partitions
```

## Key Insights Demonstrated

- **Term Numbers**: Prevent stale leaders from causing split-brain
- **Majority Voting**: Ensures only one leader can be elected
- **Randomized Timeouts**: Reduces election conflicts
- **Quorum Requirements**: Minority partitions cannot elect leaders
- **Graceful Degradation**: Isolated nodes become read-only

This demo provides hands-on experience with the concepts covered in the Split-Brain Prevention article.
