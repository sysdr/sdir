#!/bin/bash
sleep 10
DC="docker-compose"
command -v docker-compose >/dev/null 2>&1 || DC="docker compose"
$DC exec -T kafka kafka-topics --create --topic words-topic --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 2>/dev/null || true
