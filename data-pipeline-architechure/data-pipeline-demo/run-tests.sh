#!/bin/bash
echo "🧪 Running pipeline tests..."
cd tests
npm init -y
npm install kafkajs redis pg
node test-pipeline.js
