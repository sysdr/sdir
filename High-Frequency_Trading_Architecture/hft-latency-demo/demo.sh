#!/bin/bash

echo "🚀 HFT Latency Demo"
echo "==================="
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo ""
echo "Available endpoints:"
echo "  - Packet Generator:      http://localhost:3001/health"
echo "  - Traditional Processor: http://localhost:3002/stats"
echo "  - Optimized Processor:   http://localhost:3003/stats"
echo "  - Metrics Collector:     http://localhost:3004/health"
echo ""
echo "Real-time comparison of:"
echo "  🐢 Traditional Network Stack (kernel mode)"
echo "  ⚡ Kernel Bypass / DPDK (user space)"
echo ""
echo "Watch the latency metrics update in real-time!"
echo "Press Ctrl+C to stop watching"
echo ""

while true; do
  clear
  echo "📈 Live Latency Metrics ($(date +%T))"
  echo "======================================"
  echo ""
  
  trad=$(curl -s http://localhost:3002/stats)
  opt=$(curl -s http://localhost:3003/stats)
  
  echo "🐢 TRADITIONAL (Kernel Mode):"
  echo "   Packets: $(echo $trad | grep -o '"packetsProcessed":[0-9]*' | cut -d':' -f2)"
  echo "   Avg:     $(echo $trad | grep -o '"avgLatency":"[0-9.]*"' | cut -d'"' -f4)μs"
  echo "   P99:     $(echo $trad | grep -o '"p99":"[0-9.]*"' | cut -d'"' -f4)μs"
  echo ""
  echo "⚡ OPTIMIZED (Kernel Bypass):"
  echo "   Packets: $(echo $opt | grep -o '"packetsProcessed":[0-9]*' | cut -d':' -f2)"
  echo "   Avg:     $(echo $opt | grep -o '"avgLatency":"[0-9.]*"' | cut -d'"' -f4)μs"
  echo "   P99:     $(echo $opt | grep -o '"p99":"[0-9.]*"' | cut -d'"' -f4)μs"
  echo ""
  echo "Press Ctrl+C to stop"
  
  sleep 2
done
