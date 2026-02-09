const ffmpeg = require('fluent-ffmpeg');
const express = require('express');
const app = express();

// Enable CORS for dashboard
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
    next();
});

let transcodingActive = false;
let retryScheduled = false;
let stats = {
    startTime: null,
    segmentsGenerated: { '1080p': 0, '720p': 0, '480p': 0, '360p': 0 },
    currentBitrates: { '1080p': 0, '720p': 0, '480p': 0, '360p': 0 },
    errors: 0
};

// Health endpoint
app.get('/health', (req, res) => {
    res.json({ 
        status: 'ok', 
        transcoding: transcodingActive,
        stats 
    });
});

app.get('/stats', (req, res) => {
    res.json(stats);
});

// Start transcoding when ingest stream is available
function startTranscoding() {
    if (transcodingActive) return;
    
    console.log('Starting multi-bitrate transcoding...');
    transcodingActive = true;
    stats.startTime = new Date();
    
    const profiles = [
        { name: '1080p', resolution: '1920x1080', bitrate: '5000k', bufsize: '10000k' },
        { name: '720p', resolution: '1280x720', bitrate: '3000k', bufsize: '6000k' },
        { name: '480p', resolution: '854x480', bitrate: '1500k', bufsize: '3000k' },
        { name: '360p', resolution: '640x360', bitrate: '800k', bufsize: '1600k' }
    ];
    
    profiles.forEach(profile => {
        const command = ffmpeg('rtmp://ingest:1935/stream/stream')
            .inputOptions([
                '-rtmp_live', 'live',
                '-fflags', 'nobuffer',
                '-flags', 'low_delay',
                '-analyzeduration', '1000000',
                '-probesize', '1000000'
            ])
            .videoCodec('libx264')
            .videoBitrate(profile.bitrate)
            .size(profile.resolution)
            .outputOptions([
                `-maxrate ${profile.bitrate}`,
                `-bufsize ${profile.bufsize}`,
                '-preset veryfast',
                '-tune zerolatency',
                '-g 60',
                '-sc_threshold 0',
                '-f hls',
                '-hls_time 4',
                '-hls_list_size 5',
                '-hls_flags delete_segments+append_list',
                `-hls_segment_filename /output/${profile.name}/segment_%03d.ts`
            ])
            .audioCodec('aac')
            .audioBitrate('128k')
            .output(`/output/${profile.name}/playlist.m3u8`)
            .on('start', (cmd) => {
                console.log(`[${profile.name}] Transcoding started`);
            })
            .on('progress', (progress) => {
                stats.currentBitrates[profile.name] = progress.currentKbps || 0;
            })
            .on('error', (err) => {
                console.error(`[${profile.name}] Error:`, err.message);
                stats.errors++;
                transcodingActive = false;
                // Retry after 10 seconds (stream may not be ready yet)
                if (!retryScheduled) {
                    retryScheduled = true;
                    setTimeout(() => {
                        retryScheduled = false;
                        if (!transcodingActive) {
                            console.log('Retrying transcoding after stream error...');
                            startTranscoding();
                        }
                    }, 10000);
                }
            })
            .on('end', () => {
                console.log(`[${profile.name}] Transcoding ended`);
            });
        
        // Monitor segment creation
        const fs = require('fs');
        const segmentMonitor = setInterval(() => {
            try {
                const files = fs.readdirSync(`/output/${profile.name}`);
                const segments = files.filter(f => f.endsWith('.ts'));
                stats.segmentsGenerated[profile.name] = segments.length;
            } catch (e) {
                // Directory not ready yet
            }
        }, 1000);
        
        command.run();
    });
}

// Auto-start transcoding after delay; retries on error (stream may start later)
setTimeout(() => {
    console.log('Attempting to start transcoding...');
    startTranscoding();
}, 5000);

app.listen(3001, () => {
    console.log('Transcoder API running on port 3001');
});
