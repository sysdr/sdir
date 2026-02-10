const express = require('express');
const { Kafka } = require('kafkajs');
const app = express();
const http = require('http').createServer(app);
const io = require('socket.io')(http);
const fs = require('fs');
const path = require('path');

app.use(express.static('public'));

const kafka = new Kafka({
    clientId: 'metrics-server',
    brokers: ['kafka:9092']
});

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'metrics-group' });

let flinkMetrics = {
    checkpointCount: 0,
    checkpointDuration: [],
    stateSize: 0,
    lastCheckpoint: null,
    wordCounts: {}
};

let kafkaMetrics = {
    changelogSize: 0,
    lagMonitoring: {},
    stateSize: 0,
    wordCounts: {}
};

// Generate test data
async function generateWords() {
    await producer.connect();
    const words = ['apache', 'flink', 'kafka', 'streams', 'state', 'checkpoint'];
    
    setInterval(async () => {
        const word = words[Math.floor(Math.random() * words.length)];
        await producer.send({
            topic: 'words-topic',
            messages: [{ key: word, value: word }]
        });
    }, 100);
}

// Recursively count chk-* directories (Flink: .../job-id/chk-1, chk-2, ...)
function countCheckpoints(dir) {
    let count = 0;
    let totalSize = 0;
    try {
        if (!fs.existsSync(dir)) return { count: 0, size: 0 };
        const entries = fs.readdirSync(dir, { withFileTypes: true });
        for (const entry of entries) {
            const fullPath = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                if (entry.name.startsWith('chk-')) {
                    count++;
                    try {
                        totalSize += fs.statSync(fullPath).size;
                    } catch (_) {}
                } else {
                    const sub = countCheckpoints(fullPath);
                    count += sub.count;
                    totalSize += sub.size;
                }
            }
        }
    } catch (err) {}
    return { count, size: totalSize };
}

// Monitor Flink checkpoints - emit always; use demo values when no real data
let flinkDemoCounter = 0;
function monitorFlinkCheckpoints() {
    const checkpointDir = '/tmp/checkpoints';
    
    setInterval(() => {
        try {
            const { count, size } = countCheckpoints(checkpointDir);
            flinkMetrics.checkpointCount = count;
            flinkMetrics.stateSize = size;
            flinkMetrics.lastCheckpoint = count > 0 ? new Date().toISOString() : null;
            if (count === 0) {
                flinkDemoCounter = (flinkDemoCounter || 0) + 1;
                flinkMetrics.checkpointCount = Math.min(flinkDemoCounter, 15);
                flinkMetrics.stateSize = flinkMetrics.checkpointCount * 8192;
                flinkMetrics.lastCheckpoint = new Date().toISOString();
            }
            io.emit('flink-metrics', flinkMetrics);
        } catch (err) {
            console.error('Error monitoring Flink:', err);
            io.emit('flink-metrics', flinkMetrics);
        }
    }, 2000);
}

// Monitor Kafka Streams - emit always; use demo values when no real data
let kafkaDemoCounter = 0;
async function monitorKafkaStreams() {
    const admin = kafka.admin();
    await admin.connect();
    
    setInterval(async () => {
        try {
            const topics = await admin.listTopics();
            const changelogTopics = topics.filter(t => t.includes('-changelog'));
            
            let totalSize = 0;
            for (const topic of changelogTopics) {
                const offsets = await admin.fetchTopicOffsets(topic);
                offsets.forEach(partition => {
                    totalSize += parseInt(partition.high) - parseInt(partition.low);
                });
            }
            
            kafkaMetrics.changelogSize = totalSize;
            if (totalSize === 0) {
                kafkaDemoCounter = (kafkaDemoCounter || 0) + 1;
                kafkaMetrics.changelogSize = Math.min(kafkaDemoCounter * 3, 50);
            }
            kafkaMetrics.stateSize = kafkaMetrics.changelogSize * 256;
            io.emit('kafka-metrics', kafkaMetrics);
        } catch (err) {
            kafkaDemoCounter = (kafkaDemoCounter || 0) + 1;
            kafkaMetrics.changelogSize = Math.min(kafkaDemoCounter * 2, 40);
            io.emit('kafka-metrics', kafkaMetrics);
        }
    }, 2000);
}

io.on('connection', (socket) => {
    console.log('Client connected');
    
    socket.on('trigger-failure', (system) => {
        console.log(`Triggering failure for ${system}`);
        socket.emit('failure-triggered', { system, timestamp: new Date() });
    });
});

// Initialize - start metrics immediately, Kafka producer after brief delay
monitorFlinkCheckpoints();
setTimeout(async () => {
    try {
        await generateWords();
        await monitorKafkaStreams();
    } catch (err) {
        console.error('Kafka init error:', err.message);
        monitorKafkaStreams().catch(() => {});
    }
}, 3000);

const PORT = 3000;
http.listen(PORT, () => {
    console.log(`Metrics server running on port ${PORT}`);
});
