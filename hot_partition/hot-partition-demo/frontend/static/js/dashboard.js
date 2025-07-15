// Dashboard JavaScript for Hot Partition Detection Demo
class HotPartitionDashboard {
    constructor() {
        this.websocket = null;
        this.charts = {};
        this.currentMetrics = {};
        this.entropyHistory = [];
        
        this.init();
    }
    
    init() {
        this.setupWebSocket();
        this.setupCharts();
        this.setupEventListeners();
        this.loadInitialData();
    }
    
    setupWebSocket() {
        const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${wsProtocol}//${window.location.host}/ws`;
        
        this.websocket = new WebSocket(wsUrl);
        
        this.websocket.onopen = () => {
            console.log('WebSocket connected');
        };
        
        this.websocket.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.handleWebSocketMessage(data);
        };
        
        this.websocket.onclose = () => {
            console.log('WebSocket disconnected. Reconnecting...');
            setTimeout(() => this.setupWebSocket(), 5000);
        };
        
        this.websocket.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
    }
    
    setupCharts() {
        // Request Distribution Chart
        const requestCtx = document.getElementById('request-chart').getContext('2d');
        this.charts.request = new Chart(requestCtx, {
            type: 'bar',
            data: {
                labels: ['Partition 0', 'Partition 1', 'Partition 2', 'Partition 3', 'Partition 4'],
                datasets: [{
                    label: 'Requests/sec',
                    data: [0, 0, 0, 0, 0],
                    backgroundColor: [
                        '#4285f4',
                        '#34a853',
                        '#fbbc04',
                        '#ea4335',
                        '#9c27b0'
                    ],
                    borderColor: '#1a73e8',
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false }
                },
                scales: {
                    y: { beginAtZero: true }
                }
            }
        });
        
        // Memory Usage Chart
        const memoryCtx = document.getElementById('memory-chart').getContext('2d');
        this.charts.memory = new Chart(memoryCtx, {
            type: 'doughnut',
            data: {
                labels: ['Partition 0', 'Partition 1', 'Partition 2', 'Partition 3', 'Partition 4'],
                datasets: [{
                    data: [100, 100, 100, 100, 100],
                    backgroundColor: [
                        '#4285f4',
                        '#34a853',
                        '#fbbc04',
                        '#ea4335',
                        '#9c27b0'
                    ]
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { position: 'bottom' }
                }
            }
        });
        
        // Response Times Chart
        const responseCtx = document.getElementById('response-chart').getContext('2d');
        this.charts.response = new Chart(responseCtx, {
            type: 'line',
            data: {
                labels: ['Partition 0', 'Partition 1', 'Partition 2', 'Partition 3', 'Partition 4'],
                datasets: [{
                    label: 'Response Time (ms)',
                    data: [0, 0, 0, 0, 0],
                    borderColor: '#1a73e8',
                    backgroundColor: 'rgba(26, 115, 232, 0.1)',
                    fill: true,
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: { beginAtZero: true }
                }
            }
        });
        
        // Entropy Timeline Chart
        const entropyCtx = document.getElementById('entropy-chart').getContext('2d');
        this.charts.entropy = new Chart(entropyCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Entropy Score',
                    data: [],
                    borderColor: '#34a853',
                    backgroundColor: 'rgba(52, 168, 83, 0.1)',
                    fill: true,
                    tension: 0.4
                }, {
                    label: 'Critical Threshold',
                    data: [],
                    borderColor: '#ea4335',
                    borderDash: [5, 5],
                    fill: false,
                    pointRadius: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: { 
                        beginAtZero: true,
                        max: 1.0
                    }
                }
            }
        });
    }
    
    setupEventListeners() {
        // Intensity slider
        const intensitySlider = document.getElementById('intensity-slider');
        const intensityValue = document.getElementById('intensity-value');
        
        intensitySlider.addEventListener('input', (e) => {
            intensityValue.textContent = `${e.target.value}x`;
        });
    }
    
    async loadInitialData() {
        try {
            const response = await fetch('/api/metrics');
            const data = await response.json();
            this.updateMetrics(data.metrics);
            
            const analysisResponse = await fetch('/api/analysis');
            const analysisData = await analysisResponse.json();
            this.updateAnalysis(analysisData);
        } catch (error) {
            console.error('Error loading initial data:', error);
        }
    }
    
    handleWebSocketMessage(data) {
        if (data.type === 'metrics_update') {
            this.updateMetrics(data.metrics);
            this.updateEntropy(data.entropy_score);
        }
    }
    
    updateMetrics(metrics) {
        this.currentMetrics = metrics;
        
        const partitionIds = Object.keys(metrics).sort();
        const requestCounts = partitionIds.map(id => metrics[id]?.request_count || 0);
        const memoryUsage = partitionIds.map(id => metrics[id]?.memory_usage_mb || 0);
        const responseTimes = partitionIds.map(id => metrics[id]?.avg_response_time_ms || 0);
        
        // Update charts
        this.charts.request.data.datasets[0].data = requestCounts;
        this.charts.request.update('none');
        
        this.charts.memory.data.datasets[0].data = memoryUsage;
        this.charts.memory.update('none');
        
        this.charts.response.data.datasets[0].data = responseTimes;
        this.charts.response.update('none');
        
        // Update partition cards
        this.updatePartitionCards(metrics);
        
        // Update header stats
        const totalRequests = requestCounts.reduce((sum, count) => sum + count, 0);
        const maxRequests = Math.max(...requestCounts);
        const avgRequests = totalRequests / requestCounts.length;
        
        // Determine system status
        let systemStatus = 'Normal';
        let statusClass = 'success';
        
        if (maxRequests > avgRequests * 3) {
            systemStatus = 'Hot Partition Detected';
            statusClass = 'danger';
        } else if (maxRequests > avgRequests * 2) {
            systemStatus = 'Warning';
            statusClass = 'warning';
        }
        
        document.getElementById('system-status').textContent = systemStatus;
        document.getElementById('system-status').className = `stat-value ${statusClass}`;
    }
    
    updateEntropy(entropyScore) {
        document.getElementById('entropy-score').textContent = entropyScore.toFixed(3);
        
        // Update entropy history
        const now = new Date();
        this.entropyHistory.push({
            time: now.toLocaleTimeString(),
            entropy: entropyScore
        });
        
        // Keep last 20 points
        if (this.entropyHistory.length > 20) {
            this.entropyHistory.shift();
        }
        
        // Update entropy chart
        const labels = this.entropyHistory.map(point => point.time);
        const entropies = this.entropyHistory.map(point => point.entropy);
        const thresholds = new Array(entropies.length).fill(0.7);
        
        this.charts.entropy.data.labels = labels;
        this.charts.entropy.data.datasets[0].data = entropies;
        this.charts.entropy.data.datasets[1].data = thresholds;
        this.charts.entropy.update('none');
        
        // Update entropy score color
        const entropyElement = document.getElementById('entropy-score');
        if (entropyScore < 0.5) {
            entropyElement.style.color = '#ea4335';
        } else if (entropyScore < 0.7) {
            entropyElement.style.color = '#fbbc04';
        } else {
            entropyElement.style.color = '#34a853';
        }
    }
    
    updatePartitionCards(metrics) {
        const partitionGrid = document.getElementById('partition-grid');
        partitionGrid.innerHTML = '';
        
        Object.keys(metrics).sort().forEach(partitionId => {
            const metric = metrics[partitionId];
            const card = document.createElement('div');
            card.className = 'partition-card';
            
            // Determine status
            const avgLoad = Object.values(metrics).reduce((sum, m) => sum + m.request_count, 0) / Object.keys(metrics).length;
            
            if (metric.request_count > avgLoad * 4) {
                card.classList.add('critical');
            } else if (metric.request_count > avgLoad * 2.5) {
                card.classList.add('danger');
            } else if (metric.request_count > avgLoad * 1.5) {
                card.classList.add('warning');
            }
            
            card.innerHTML = `
                <div class="partition-name">${partitionId.replace('_', ' ').toUpperCase()}</div>
                <div class="partition-metrics">
                    <div>Requests: ${metric.request_count}</div>
                    <div>Memory: ${metric.memory_usage_mb.toFixed(1)}MB</div>
                    <div>CPU: ${metric.cpu_usage_percent.toFixed(1)}%</div>
                    <div>Response: ${metric.avg_response_time_ms.toFixed(0)}ms</div>
                </div>
            `;
            
            partitionGrid.appendChild(card);
        });
    }
    
    async updateAnalysis(analysisData) {
        // Update alerts
        const alertsContainer = document.getElementById('alerts-container');
        
        if (analysisData.alerts && analysisData.alerts.length > 0) {
            alertsContainer.innerHTML = '';
            
            analysisData.alerts.forEach(alert => {
                const alertElement = document.createElement('div');
                alertElement.className = `alert-item ${alert.severity.toLowerCase()}`;
                
                alertElement.innerHTML = `
                    <div class="alert-header">
                        <div class="alert-title">${alert.partition_id.replace('_', ' ').toUpperCase()}</div>
                        <div class="alert-severity">${alert.severity}</div>
                    </div>
                    <div class="alert-description">${alert.recommended_action}</div>
                    <div style="margin-top: 8px; font-size: 0.8rem; color: #666;">
                        Entropy: ${alert.entropy_score.toFixed(3)} | Load Factor: ${alert.load_factor.toFixed(2)}
                    </div>
                `;
                
                alertsContainer.appendChild(alertElement);
            });
        } else {
            alertsContainer.innerHTML = '<div class="no-alerts">No active alerts</div>';
        }
    }
}

// Global functions for buttons
async function triggerHotspot() {
    const partitionSelect = document.getElementById('hotspot-partition');
    const intensitySlider = document.getElementById('intensity-slider');
    
    const data = {
        partition_id: partitionSelect.value || null,
        intensity: parseFloat(intensitySlider.value)
    };
    
    try {
        const response = await fetch('/api/trigger-hotspot', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        });
        
        if (response.ok) {
            console.log('Hotspot triggered successfully');
        }
    } catch (error) {
        console.error('Error triggering hotspot:', error);
    }
}

async function endHotspot() {
    try {
        const response = await fetch('/api/end-hotspot', {
            method: 'POST'
        });
        
        if (response.ok) {
            console.log('Hotspot ended successfully');
        }
    } catch (error) {
        console.error('Error ending hotspot:', error);
    }
}

// Initialize dashboard when page loads
document.addEventListener('DOMContentLoaded', () => {
    new HotPartitionDashboard();
});
