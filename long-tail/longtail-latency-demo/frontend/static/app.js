// Long-tail Latency Observatory Frontend
class LatencyObservatory {
    constructor() {
        this.ws = null;
        this.latencyChart = null;
        this.requestChart = null;
        this.loadTestInterval = null;
        this.metrics = {
            timestamps: [],
            p50: [],
            p95: [],
            p99: [],
            requestRate: [],
            errorRate: []
        };
        
        this.init();
    }
    
    init() {
        this.setupWebSocket();
        this.setupCharts();
        this.setupSliderUpdates();
        this.loadConfig();
    }
    
    setupWebSocket() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws`;
        
        this.ws = new WebSocket(wsUrl);
        
        this.ws.onopen = () => {
            console.log('WebSocket connected');
        };
        
        this.ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.updateMetrics(data);
        };
        
        this.ws.onclose = () => {
            console.log('WebSocket disconnected, reconnecting...');
            setTimeout(() => this.setupWebSocket(), 5000);
        };
        
        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
    }
    
    setupCharts() {
        // Latency percentiles chart
        const latencyCtx = document.getElementById('latencyChart').getContext('2d');
        this.latencyChart = new Chart(latencyCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'P50',
                        data: [],
                        borderColor: '#34a853',
                        backgroundColor: 'rgba(52, 168, 83, 0.1)',
                        tension: 0.4,
                        fill: false
                    },
                    {
                        label: 'P95',
                        data: [],
                        borderColor: '#fbbc04',
                        backgroundColor: 'rgba(251, 188, 4, 0.1)',
                        tension: 0.4,
                        fill: false
                    },
                    {
                        label: 'P99',
                        data: [],
                        borderColor: '#ea4335',
                        backgroundColor: 'rgba(234, 67, 53, 0.1)',
                        tension: 0.4,
                        fill: false
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                height: 280,
                scales: {
                    x: {
                        type: 'time',
                        time: {
                            displayFormats: {
                                second: 'HH:mm:ss'
                            }
                        },
                        title: {
                            display: true,
                            text: 'Time'
                        }
                    },
                    y: {
                        title: {
                            display: true,
                            text: 'Latency (ms)'
                        },
                        beginAtZero: true
                    }
                },
                plugins: {
                    legend: {
                        position: 'top'
                    }
                }
            }
        });
        
        // Request rate chart
        const requestCtx = document.getElementById('requestChart').getContext('2d');
        this.requestChart = new Chart(requestCtx, {
            type: 'bar',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'Requests/min',
                        data: [],
                        backgroundColor: '#1a73e8'
                    },
                    {
                        label: 'Errors/min',
                        data: [],
                        backgroundColor: '#ea4335'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                height: 280,
                scales: {
                    x: {
                        title: {
                            display: true,
                            text: 'Time'
                        }
                    },
                    y: {
                        title: {
                            display: true,
                            text: 'Count'
                        },
                        beginAtZero: true
                    }
                }
            }
        });
    }
    
    updateMetrics(data) {
        const now = new Date();
        const recentStats = data.recent_stats;
        const percentiles = recentStats.percentiles;
        
        // Update metric cards
        document.getElementById('p50-metric').textContent = `${Math.round(percentiles.p50)}ms`;
        document.getElementById('p95-metric').textContent = `${Math.round(percentiles.p95)}ms`;
        document.getElementById('p99-metric').textContent = `${Math.round(percentiles.p99)}ms`;
        document.getElementById('total-requests').textContent = data.total_requests;
        
        const errorRate = data.total_requests > 0 ? 
            ((data.error_count / data.total_requests) * 100).toFixed(1) : 0;
        document.getElementById('error-rate').textContent = `${errorRate}% errors`;
        
        // Update charts
        this.updateLatencyChart(now, percentiles);
        this.updateRequestChart(now, recentStats.count, data.error_count);
        
        // Add visual feedback for metric updates
        this.animateMetricUpdate('p50-metric');
        this.animateMetricUpdate('p95-metric');
        this.animateMetricUpdate('p99-metric');
    }
    
    updateLatencyChart(timestamp, percentiles) {
        const maxPoints = 30; // Reduced to prevent infinite growth
        
        // Add new data point
        this.latencyChart.data.labels.push(timestamp);
        this.latencyChart.data.datasets[0].data.push(percentiles.p50);
        this.latencyChart.data.datasets[1].data.push(percentiles.p95);
        this.latencyChart.data.datasets[2].data.push(percentiles.p99);
        
        // Remove old data points
        if (this.latencyChart.data.labels.length > maxPoints) {
            this.latencyChart.data.labels.shift();
            this.latencyChart.data.datasets.forEach(dataset => dataset.data.shift());
        }
        
        this.latencyChart.update('none');
    }
    
    updateRequestChart(timestamp, requestCount, errorCount) {
        const maxPoints = 15; // Reduced to prevent infinite growth
        const timeLabel = timestamp.toLocaleTimeString();
        
        this.requestChart.data.labels.push(timeLabel);
        this.requestChart.data.datasets[0].data.push(requestCount);
        this.requestChart.data.datasets[1].data.push(errorCount);
        
        if (this.requestChart.data.labels.length > maxPoints) {
            this.requestChart.data.labels.shift();
            this.requestChart.data.datasets.forEach(dataset => dataset.data.shift());
        }
        
        this.requestChart.update('none');
    }
    
    animateMetricUpdate(elementId) {
        const element = document.getElementById(elementId);
        element.classList.add('updated');
        setTimeout(() => element.classList.remove('updated'), 500);
    }
    
    setupSliderUpdates() {
        // Setup real-time slider value updates
        const sliders = [
            { id: 'gc-duration', valueId: 'gc-duration-value', suffix: 'ms' },
            { id: 'db-duration', valueId: 'db-duration-value', suffix: 'ms' },
            { id: 'cache-penalty', valueId: 'cache-penalty-value', suffix: 'ms' },
            { id: 'jitter-max', valueId: 'jitter-max-value', suffix: 'ms' }
        ];
        
        sliders.forEach(slider => {
            const element = document.getElementById(slider.id);
            const valueElement = document.getElementById(slider.valueId);
            
            element.addEventListener('input', () => {
                valueElement.textContent = element.value + slider.suffix;
            });
        });
    }
    
    async loadConfig() {
        try {
            const response = await fetch('/api/config');
            const config = await response.json();
            this.applyConfigToUI(config);
        } catch (error) {
            console.error('Failed to load config:', error);
        }
    }
    
    applyConfigToUI(config) {
        // Apply checkbox states
        document.getElementById('gc-pause').checked = config.gc_pause_enabled;
        document.getElementById('db-lock').checked = config.db_lock_enabled;
        document.getElementById('cache-miss').checked = config.cache_miss_enabled;
        document.getElementById('network-jitter').checked = config.network_jitter_enabled;
        
        document.getElementById('load-shedding').checked = config.load_shedding_enabled;
        document.getElementById('request-hedging').checked = config.request_hedging_enabled;
        document.getElementById('circuit-breaker').checked = config.circuit_breaker_enabled;
        document.getElementById('adaptive-timeouts').checked = config.adaptive_timeouts_enabled;
        
        // Apply slider values
        document.getElementById('gc-duration').value = config.gc_pause_duration;
        document.getElementById('db-duration').value = config.db_lock_duration;
        document.getElementById('cache-penalty').value = config.cache_miss_penalty;
        document.getElementById('jitter-max').value = config.network_jitter_max;
        
        // Update value displays
        document.getElementById('gc-duration-value').textContent = config.gc_pause_duration + 'ms';
        document.getElementById('db-duration-value').textContent = config.db_lock_duration + 'ms';
        document.getElementById('cache-penalty-value').textContent = config.cache_miss_penalty + 'ms';
        document.getElementById('jitter-max-value').textContent = config.network_jitter_max + 'ms';
    }
}

// Configuration management
async function updateConfig() {
    const config = {
        gc_pause_enabled: document.getElementById('gc-pause').checked,
        gc_pause_probability: 0.01,
        gc_pause_duration: parseFloat(document.getElementById('gc-duration').value),
        
        db_lock_enabled: document.getElementById('db-lock').checked,
        db_lock_probability: 0.005,
        db_lock_duration: parseFloat(document.getElementById('db-duration').value),
        
        cache_miss_enabled: document.getElementById('cache-miss').checked,
        cache_miss_probability: 0.1,
        cache_miss_penalty: parseFloat(document.getElementById('cache-penalty').value),
        
        network_jitter_enabled: document.getElementById('network-jitter').checked,
        network_jitter_max: parseFloat(document.getElementById('jitter-max').value),
        
        thread_pool_exhaustion: false,
        cpu_throttling: false,
        
        load_shedding_enabled: document.getElementById('load-shedding').checked,
        load_shedding_threshold: 0.8,
        
        request_hedging_enabled: document.getElementById('request-hedging').checked,
        hedging_threshold: 100.0,
        
        circuit_breaker_enabled: document.getElementById('circuit-breaker').checked,
        circuit_breaker_failure_threshold: 5,
        
        adaptive_timeouts_enabled: document.getElementById('adaptive-timeouts').checked
    };
    
    try {
        const response = await fetch('/api/config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(config)
        });
        
        if (!response.ok) {
            throw new Error('Failed to update configuration');
        }
        
        console.log('Configuration updated successfully');
    } catch (error) {
        console.error('Failed to update config:', error);
    }
}

// Load testing functions
async function runLoadTest(intensity) {
    stopLoadTest(); // Stop any existing test
    
    const statusElement = document.getElementById('load-test-status');
    statusElement.textContent = `Running ${intensity} load test...`;
    statusElement.style.color = '#1a73e8';
    
    const intervals = {
        light: 1000,    // 1 request per second
        moderate: 500,  // 2 requests per second  
        heavy: 200      // 5 requests per second
    };
    
    const interval = intervals[intensity] || 1000;
    
    window.loadTestInterval = setInterval(async () => {
        try {
            const response = await fetch('/api/simulate');
            const result = await response.json();
            
            // Update status with latest result
            const latency = Math.round(result.response_time_ms);
            statusElement.innerHTML = `
                ${intensity} load test running<br>
                Last request: ${latency}ms
                ${result.latency_sources.length > 0 ? '<br>Sources: ' + result.latency_sources.join(', ') : ''}
            `;
            
        } catch (error) {
            console.error('Load test request failed:', error);
        }
    }, interval);
}

function stopLoadTest() {
    if (window.loadTestInterval) {
        clearInterval(window.loadTestInterval);
        window.loadTestInterval = null;
        
        const statusElement = document.getElementById('load-test-status');
        statusElement.textContent = 'Load test stopped';
        statusElement.style.color = '#5f6368';
    }
}

// Initialize the application
let observatory;
document.addEventListener('DOMContentLoaded', () => {
    observatory = new LatencyObservatory();
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    stopLoadTest();
    if (observatory && observatory.ws) {
        observatory.ws.close();
    }
});
