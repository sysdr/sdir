#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Stop duplicate ffmpeg stream if running
docker stop ffmpeg-stream 2>/dev/null || true

echo "🚀 Starting Live Streaming services..."
docker compose up -d

echo ""
echo "⏳ Waiting for services (15s)..."
sleep 15

echo ""
echo "🎬 Starting test video stream..."
docker run -d --rm --name ffmpeg-stream --network streaming-demo_streaming-net \
  jrottenberg/ffmpeg:4.4-alpine \
  -re -f lavfi -i testsrc=duration=3600:size=1920x1080:rate=30 \
  -f lavfi -i sine=frequency=1000:duration=3600 \
  -vf "drawtext=text='%{pts\:hms}':x=(w-text_w)/2:y=h-60:fontsize=48:fontcolor=white:box=1:boxcolor=black@0.5" \
  -c:v libx264 -preset ultrafast -tune zerolatency -b:v 5000k -maxrate 5000k -bufsize 10000k \
  -c:a aac -b:a 128k -f flv rtmp://ingest:1935/stream/stream

echo ""
echo "✅ Demo started! Transcoder will connect (retries every 10s if stream not ready)."
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🎥 HLS Stream: http://localhost:3002/live/master.m3u8"
echo "🧪 Run tests: $SCRIPT_DIR/test.sh"
echo ""
