# Live Streaming Demo - Run Instructions

## Summary of Fixes Applied

1. **RTMP Port Fix**: Transcoder now pulls from `ingest:1935` (stream available when publisher connects) instead of non-existent `ingest:1936`
2. **Transcoder Retry Logic**: Added retry every 10 seconds when stream is not yet available
3. **FFmpeg Input Options**: Replaced `-re` with `-rtmp_live live` for proper live RTMP pull
4. **Custom nginx.conf**: Restored config with `application live` (alfg default was overwriting our config)
5. **Test Script**: Fixed container name check from `ingest` to `rtmp-ingest`
6. **Dashboard Input Bitrate**: Added display of 1080p bitrate as input/primary stream metric
7. **start.sh**: New script for proper startup order with full path support

## Run the Demo

### From streaming-demo directory:

```bash
cd /home/systemdrllp5/git/sdir/Live_Streaming/streaming-demo

# Option 1: Use start.sh (recommended - handles order correctly)
bash start.sh

# Option 2: Or with full path
bash /home/systemdrllp5/git/sdir/Live_Streaming/streaming-demo/start.sh
```

### Run Tests (after stream is flowing, ~60 seconds):

```bash
bash /home/systemdrllp5/git/sdir/Live_Streaming/streaming-demo/test.sh
```

### Check for Duplicate Services:

```bash
docker ps | grep -E 'ffmpeg-stream|rtmp-ingest|transcoder|hls-delivery|dashboard'
# Stop duplicate ffmpeg: docker stop ffmpeg-stream
```

### Validate Dashboard

- Open: http://localhost:3000
- Metrics should update (non-zero) when:
  - **Transcoding segments**: Populate when transcoder receives stream
  - **Active Viewers**: Dashboard player registers as viewer
  - **Segments Served / Data Transferred**: When HLS player requests segments
  - **Input Bitrate**: Shows 1080p output bitrate when transcoding active

### Cleanup

```bash
cd /home/systemdrllp5/git/sdir/Live_Streaming/streaming-demo
docker stop ffmpeg-stream 2>/dev/null
bash cleanup.sh
```
