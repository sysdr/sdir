# Paxos Consensus Algorithm Demonstration

This interactive demonstration shows how the Paxos consensus algorithm works in practice, including failure scenarios and recovery patterns.

## What This Demo Shows

1. **Two-Phase Protocol**: Prepare/Promise and Accept/Accepted phases
2. **Safety Guarantees**: How Paxos prevents conflicting decisions
3. **Failure Handling**: Node crashes and network partitions
4. **Persistent State**: Critical importance of durable storage
5. **Competing Proposers**: How higher proposal numbers resolve conflicts

## Files Created

- `paxos_simulator.py` - Core Paxos implementation with detailed logging
- `web/index.html` - Interactive web interface for visualization
- `logs/` - Detailed execution logs for each scenario
- `state/` - Persistent acceptor state (demonstrates durability)

## Key Insights Demonstrated

### 1. Proposal Number Strategy
- Each proposer uses unique ID ranges (0-999, 1000-1999, 2000-2999)
- Prevents conflicts and ensures global ordering
- Shows why proposal numbers must be monotonically increasing

### 2. Safety Through Persistence
- Acceptors save state before responding (critical for safety)
- Recovery reloads state from disk
- Demonstrates why write-ahead logging is essential

### 3. Majority Quorums
- Requires majority for both prepare and accept phases
- Shows how this prevents split-brain scenarios
- Demonstrates why N >= 2F+1 nodes needed for F failures

### 4. Value Convergence
- Once a value is accepted by majority, it becomes "chosen"
- Subsequent proposals must use the highest-numbered accepted value
- Shows how Paxos prevents conflicting decisions

## Expected Output

The simulation will show:
- Detailed message flows between proposers and acceptors
- State transitions and persistence operations
- Consensus achievement or failure reasons
- Impact of node failures on consensus

## Production Insights

This implementation demonstrates several production-critical patterns:
- Persistent state management
- Timeout and retry mechanisms
- Unique proposal ID generation
- Majority quorum calculations
- Graceful degradation under failures
