const express = require('express');
const cors = require('cors');
const compression = require('compression');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 4000;

// Middleware
app.use(cors());
app.use(compression());
app.use(express.json());

// Quality levels with corresponding bitrates (kbps)
const QUALITIES = {
  '240p': { bitrate: 400, width: 426, height: 240 },
  '360p': { bitrate: 800, width: 640, height: 360 },
  '480p': { bitrate: 1400, width: 854, height: 480 },
  '720p': { bitrate: 2800, width: 1280, height: 720 },
  '1080p': { bitrate: 5000, width: 1920, height: 1080 }
};

// Network throttling state (simulated)
let networkThrottle = {
  enabled: false,
  bandwidth: Infinity // bytes per second
};

// Streaming metrics
const metrics = {
  totalSegmentsServed: 0,
  segmentsByQuality: {},
  activeConnections: 0,
  averageLatency: 0
};

// Initialize metrics
Object.keys(QUALITIES).forEach(q => metrics.segmentsByQuality[q] = 0);

// DASH Manifest endpoint
app.get('/manifest.mpd', (req, res) => {
  const manifest = generateDashManifest();
  res.set('Content-Type', 'application/dash+xml');
  res.send(manifest);
});

// HLS Master Playlist endpoint
app.get('/playlist.m3u8', (req, res) => {
  const playlist = generateHlsMasterPlaylist();
  res.set('Content-Type', 'application/vnd.apple.mpegurl');
  res.send(playlist);
});

// HLS Variant Playlist endpoint
app.get('/playlist_:quality.m3u8', (req, res) => {
  const { quality } = req.params;
  if (!QUALITIES[quality]) {
    return res.status(404).send('Quality not found');
  }
  const playlist = generateHlsVariantPlaylist(quality);
  res.set('Content-Type', 'application/vnd.apple.mpegurl');
  res.send(playlist);
});

// Segment serving endpoint with network throttling
app.get('/segments/:quality/segment_:index.m4s', async (req, res) => {
  const { quality, index } = req.params;
  // Try multiple possible paths for segments
  const segmentPaths = [
    path.join(__dirname, '..', 'segments', quality, `segment_${index}.m4s`),
    path.join(process.cwd(), 'segments', quality, `segment_${index}.m4s`),
    path.join('/app', 'segments', quality, `segment_${index}.m4s`)
  ];
  let segmentPath = segmentPaths.find(p => fs.existsSync(p));
  
  if (!segmentPath) {
    return res.status(404).send('Segment not found');
  }

  metrics.activeConnections++;
  const startTime = Date.now();

  try {
    const segmentData = fs.readFileSync(segmentPath);
    
    // Apply network throttling if enabled
    if (networkThrottle.enabled && networkThrottle.bandwidth < Infinity) {
      const delay = (segmentData.length / networkThrottle.bandwidth) * 1000;
      await new Promise(resolve => setTimeout(resolve, delay));
    }

    metrics.totalSegmentsServed++;
    metrics.segmentsByQuality[quality]++;
    
    const latency = Date.now() - startTime;
    metrics.averageLatency = (metrics.averageLatency * 0.8) + (latency * 0.2);

    res.set('Content-Type', 'video/mp4');
    res.set('Accept-Ranges', 'bytes');
    res.send(segmentData);
  } finally {
    metrics.activeConnections--;
  }
});

// Network control endpoint
app.post('/network/throttle', (req, res) => {
  const { enabled, bandwidthKbps } = req.body;
  networkThrottle.enabled = enabled;
  networkThrottle.bandwidth = enabled ? (bandwidthKbps * 1024 / 8) : Infinity;
  res.json({ 
    status: 'ok', 
    throttle: networkThrottle,
    message: enabled ? `Network throttled to ${bandwidthKbps} kbps` : 'Network throttling disabled'
  });
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
  res.json({
    ...metrics,
    timestamp: Date.now(),
    networkThrottle
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', uptime: process.uptime() });
});

function generateDashManifest() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT200S" minBufferTime="PT10S">
  <Period>
    ${Object.entries(QUALITIES).map(([quality, info]) => `
    <AdaptationSet mimeType="video/mp4" segmentAlignment="true" startWithSAP="1">
      <Representation id="${quality}" bandwidth="${info.bitrate * 1000}" width="${info.width}" height="${info.height}">
        <SegmentTemplate media="segments/${quality}/segment_$Number$.m4s" initialization="segments/${quality}/init.mp4" startNumber="0" duration="10"/>
      </Representation>
    </AdaptationSet>`).join('')}
  </Period>
</MPD>`;
}

function generateHlsMasterPlaylist() {
  return `#EXTM3U
#EXT-X-VERSION:3
${Object.entries(QUALITIES).map(([quality, info]) => 
  `#EXT-X-STREAM-INF:BANDWIDTH=${info.bitrate * 1000},RESOLUTION=${info.width}x${info.height}\nplaylist_${quality}.m3u8`
).join('\n')}`;
}

function generateHlsVariantPlaylist(quality) {
  return `#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:0
${Array.from({length: 20}, (_, i) => `#EXTINF:10.0,\nsegments/${quality}/segment_${i}.m4s`).join('\n')}
#EXT-X-ENDLIST`;
}

app.listen(PORT, () => {
  console.log(`✅ ABR Streaming Server running on http://localhost:${PORT}`);
  console.log(`📊 Metrics: http://localhost:${PORT}/metrics`);
  console.log(`🎬 DASH Manifest: http://localhost:${PORT}/manifest.mpd`);
  console.log(`🍎 HLS Playlist: http://localhost:${PORT}/playlist.m3u8`);
});
