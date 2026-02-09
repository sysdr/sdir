const express = require('express');
const fs = require('fs');
const path = require('path');
const app = express();

let viewerSessions = [];
let deliveryStats = {
    totalSegmentsServed: 0,
    bytesTransferred: 0,
    activeViewers: 0,
    qualitySwitches: 0,
    cacheHits: 0,
    cacheMisses: 0
};

// Simple in-memory cache for segments
const segmentCache = new Map();
const CACHE_TTL = 30000; // 30 seconds

// Enable CORS
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
    next();
});

// Serve master playlist
app.get('/live/master.m3u8', (req, res) => {
    const viewerId = req.query.viewer || 'anonymous';
    
    if (!viewerSessions.find(v => v.id === viewerId)) {
        viewerSessions.push({
            id: viewerId,
            currentQuality: '1080p',
            joinedAt: new Date(),
            segmentsReceived: 0,
            qualitySwitches: 0
        });
        deliveryStats.activeViewers = viewerSessions.length;
    }
    
    const masterPlaylist = `#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,NAME="1080p"
/live/1080p/playlist.m3u8?viewer=${viewerId}
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,NAME="720p"
/live/720p/playlist.m3u8?viewer=${viewerId}
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=854x480,NAME="480p"
/live/480p/playlist.m3u8?viewer=${viewerId}
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,NAME="360p"
/live/360p/playlist.m3u8?viewer=${viewerId}
`;
    
    res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
    res.send(masterPlaylist);
});

// Serve quality-specific playlists
app.get('/live/:quality/playlist.m3u8', (req, res) => {
    const quality = req.params.quality;
    const viewerId = req.query.viewer || 'anonymous';
    const playlistPath = `/output/${quality}/playlist.m3u8`;
    
    // Track quality switches
    const viewer = viewerSessions.find(v => v.id === viewerId);
    if (viewer && viewer.currentQuality !== quality) {
        viewer.currentQuality = quality;
        viewer.qualitySwitches++;
        deliveryStats.qualitySwitches++;
    }
    
    try {
        if (fs.existsSync(playlistPath)) {
            let content = fs.readFileSync(playlistPath, 'utf8');
            // Append viewer ID to segment URLs so viewer stats are tracked
            if (viewerId && viewerId !== 'anonymous') {
                content = content.replace(/^(segment_\d+\.ts)$/gm, `$1?viewer=${encodeURIComponent(viewerId)}`);
            }
            res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
            res.setHeader('Cache-Control', 'no-cache');
            res.send(content);
        } else {
            res.status(404).send('Playlist not found');
        }
    } catch (err) {
        res.status(500).send('Error reading playlist');
    }
});

// Serve video segments with caching
app.get('/live/:quality/:segment', (req, res) => {
    const quality = req.params.quality;
    const segment = req.params.segment;
    const segmentPath = `/output/${quality}/${segment}`;
    const cacheKey = `${quality}/${segment}`;
    
    // Check cache
    const cached = segmentCache.get(cacheKey);
    if (cached && (Date.now() - cached.timestamp < CACHE_TTL)) {
        deliveryStats.cacheHits++;
        deliveryStats.totalSegmentsServed++;
        deliveryStats.bytesTransferred += cached.data.length;
        
        res.setHeader('Content-Type', 'video/MP2T');
        res.setHeader('X-Cache', 'HIT');
        return res.send(cached.data);
    }
    
    deliveryStats.cacheMisses++;
    
    try {
        if (fs.existsSync(segmentPath)) {
            const data = fs.readFileSync(segmentPath);
            
            // Cache segment
            segmentCache.set(cacheKey, {
                data: data,
                timestamp: Date.now()
            });
            
            deliveryStats.totalSegmentsServed++;
            deliveryStats.bytesTransferred += data.length;
            
            // Update viewer stats
            const viewerId = req.query.viewer;
            const viewer = viewerSessions.find(v => v.id === viewerId);
            if (viewer) {
                viewer.segmentsReceived++;
            }
            
            res.setHeader('Content-Type', 'video/MP2T');
            res.setHeader('X-Cache', 'MISS');
            res.send(data);
        } else {
            res.status(404).send('Segment not found');
        }
    } catch (err) {
        res.status(500).send('Error reading segment');
    }
});

// Stats endpoint
app.get('/api/stats', (req, res) => {
    res.json({
        delivery: deliveryStats,
        viewers: viewerSessions,
        cache: {
            size: segmentCache.size,
            ttl: CACHE_TTL
        }
    });
});

// Cleanup old cache entries
setInterval(() => {
    const now = Date.now();
    for (const [key, value] of segmentCache.entries()) {
        if (now - value.timestamp > CACHE_TTL) {
            segmentCache.delete(key);
        }
    }
}, 10000);

// Cleanup disconnected viewers
setInterval(() => {
    const now = Date.now();
    viewerSessions = viewerSessions.filter(v => {
        const idle = now - v.joinedAt > 300000; // 5 min timeout
        return !idle;
    });
    deliveryStats.activeViewers = viewerSessions.length;
}, 30000);

app.listen(3002, () => {
    console.log('HLS delivery server running on port 3002');
});
