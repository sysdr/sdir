#!/bin/bash
set -e

echo "Setting up network namespaces and traffic control..."

# Create namespaces
ip netns add normal-test
ip netns add bloat-test
ip netns add aqm-test

# Create veth pairs
ip link add veth-norm type veth peer name veth-norm-peer
ip link add veth-bloat type veth peer name veth-bloat-peer
ip link add veth-aqm type veth peer name veth-aqm-peer

# Move peer ends to namespaces
ip link set veth-norm-peer netns normal-test
ip link set veth-bloat-peer netns bloat-test
ip link set veth-aqm-peer netns aqm-test

# Configure host side
ip addr add 10.0.0.1/24 dev veth-norm
ip addr add 10.0.1.1/24 dev veth-bloat
ip addr add 10.0.2.1/24 dev veth-aqm

ip link set veth-norm up
ip link set veth-bloat up
ip link set veth-aqm up

# Configure namespace side
ip netns exec normal-test ip addr add 10.0.0.2/24 dev veth-norm-peer
ip netns exec bloat-test ip addr add 10.0.1.2/24 dev veth-bloat-peer
ip netns exec aqm-test ip addr add 10.0.2.2/24 dev veth-aqm-peer

ip netns exec normal-test ip link set veth-norm-peer up
ip netns exec bloat-test ip link set veth-bloat-peer up
ip netns exec aqm-test ip link set veth-aqm-peer up

ip netns exec normal-test ip link set lo up
ip netns exec bloat-test ip link set lo up
ip netns exec aqm-test ip link set lo up

# Apply traffic control
# Normal: reasonable queue (100 packets)
tc qdisc add dev veth-norm root netem delay 10ms limit 100

# Bloated: huge queue (10000 packets) - simulates buffer bloat
tc qdisc add dev veth-bloat root netem delay 10ms limit 10000

# AQM: Try FQ-CoDel, fallback to netem with smaller limit if not available
if tc qdisc add dev veth-aqm root fq_codel 2>/dev/null; then
    echo "Using FQ-CoDel for AQM"
else
    echo "FQ-CoDel not available, using netem with smaller limit (simulates AQM)"
    tc qdisc add dev veth-aqm root netem delay 10ms limit 100
fi

echo "Network setup complete!"
