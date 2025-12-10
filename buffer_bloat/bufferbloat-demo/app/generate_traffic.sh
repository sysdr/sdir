#!/bin/bash

echo "Generating traffic to simulate load..."

# Generate continuous traffic in each namespace
while true; do
    # Send bulk data to fill queues
    ip netns exec normal-test ping -f -s 1400 -c 100 10.0.0.1 > /dev/null 2>&1 &
    ip netns exec bloat-test ping -f -s 1400 -c 100 10.0.1.1 > /dev/null 2>&1 &
    ip netns exec aqm-test ping -f -s 1400 -c 100 10.0.2.1 > /dev/null 2>&1 &
    sleep 2
done
