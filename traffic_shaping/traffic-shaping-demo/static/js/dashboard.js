// Global variables
let bulkTestInterval = null;
let bulkTestCount = 0;
let bulkTestTotal = 0;
let requestRateChart = null;
let responseTimeChart = null;
let metricsInterval = null;

// Initialize dashboard
document.addEventListener('DOMContentLoaded', function() {
    initializeCharts();
    startMetricsUpdate();
    updateLimiterStatus();
});

// Initialize charts
function initializeCharts() {
    // Request Rate Chart
    const requestRateCtx = document.getElementById('requestRateChart').getContext('2d');
    requestRateChart = new Chart(requestRateCtx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: 'Token Bucket',
                data: [],
                borderColor: '#1a73e8',
                backgroundColor: 'rgba(26, 115, 232, 0.1)',
                tension: 0.4
            }, {
                label: 'Sliding Window',
                data: [],
                borderColor: '#34a853',
                backgroundColor: 'rgba(52, 168, 83, 0.1)',
                tension: 0.4
            }, {
                label: 'Fixed Window',
                data: [],
                borderColor: '#ea4335',
                backgroundColor: 'rgba(234, 67, 53, 0.1)',
                tension: 0.4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'top'
                }
            },
            scales: {
                x: {
                    display: true,
                    title: {
                        display: true,
                        text: 'Time'
                    }
                },
                y: {
                    display: true,
                    title: {
                        display: true,
                        text: 'Requests/sec'
                    },
                    beginAtZero: true
                }
            }
        }
    });

    // Response Time Chart
    const responseTimeCtx = document.getElementById('responseTimeChart').getContext('2d');
    responseTimeChart = new Chart(responseTimeCtx, {
        type: 'bar',
        data: {
            labels: ['Token Bucket', 'Sliding Window', 'Fixed Window'],
            datasets: [{
                label: 'Avg Response Time (ms)',
                data: [0, 0, 0],
                backgroundColor: ['rgba(26, 115, 232, 0.7)', 'rgba(52, 168, 83, 0.7)', 'rgba(234, 67, 53, 0.7)'],
                borderColor: ['#1a73e8', '#34a853', '#ea4335'],
                borderWidth: 2
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    title: {
                        display: true,
                        text: 'Response Time (ms)'
                    }
                }
            }
        }
    });
}

// Test individual limiter
async function testLimiter(limiterType) {
    const card = document.querySelector(`[data-limiter="${limiterType}"]`);
    card.classList.add('active');
    
    try {
        const response = await fetch(`/api/request/${limiterType}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            }
        });
        
        const result = await response.json();
        
        // Log the request
        logRequest(limiterType, result.allowed, result.processing_time_ms, result.metadata);
        
        // Update status
        updateLimiterStatus();
        
        // Visual feedback
        setTimeout(() => {
            card.classList.remove('active');
        }, 500);
        
    } catch (error) {
        console.error('Request failed:', error);
        logRequest(limiterType, false, 0, { error: error.message });
    }
}

// Reset limiter
async function resetLimiter(limiterType) {
    try {
        await fetch(`/api/reset/${limiterType}`, {
            method: 'POST'
        });
        
        updateLimiterStatus();
        addLog(`Reset ${limiterType} limiter`, 'success');
        
    } catch (error) {
        console.error('Reset failed:', error);
        addLog(`Failed to reset ${limiterType}: ${error.message}`, 'error');
    }
}

// Start bulk test
function startBulkTest() {
    if (bulkTestInterval) {
        stopBulkTest();
        return;
    }
    
    const limiterType = document.getElementById('bulk_limiter').value;
    const count = parseInt(document.getElementById('bulk_count').value);
    const interval = parseInt(document.getElementById('bulk_interval').value);
    
    bulkTestCount = 0;
    bulkTestTotal = count;
    
    document.getElementById('bulk_status').textContent = `Testing ${limiterType}...`;
    
    bulkTestInterval = setInterval(async () => {
        if (bulkTestCount >= bulkTestTotal) {
            stopBulkTest();
            return;
        }
        
        try {
            const response = await fetch(`/api/request/${limiterType}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                }
            });
            
            const result = await response.json();
            logRequest(limiterType, result.allowed, result.processing_time_ms, result.metadata);
            
        } catch (error) {
            logRequest(limiterType, false, 0, { error: error.message });
        }
        
        bulkTestCount++;
        const progress = (bulkTestCount / bulkTestTotal) * 100;
        document.getElementById('bulk_progress').style.width = `${progress}%`;
        document.getElementById('bulk_status').textContent = `${bulkTestCount}/${bulkTestTotal} requests sent`;
        
    }, interval);
}

// Stop bulk test
function stopBulkTest() {
    if (bulkTestInterval) {
        clearInterval(bulkTestInterval);
        bulkTestInterval = null;
    }
    
    document.getElementById('bulk_progress').style.width = '0%';
    document.getElementById('bulk_status').textContent = 'Ready';
}

// Update limiter status
async function updateLimiterStatus() {
    const limiters = ['token_bucket', 'sliding_window', 'fixed_window'];
    
    for (const limiter of limiters) {
        try {
            const response = await fetch(`/api/limiter/${limiter}/status?user_id=default_user`);
            const status = await response.json();
            
            if (limiter === 'token_bucket') {
                document.getElementById('token_bucket_tokens').textContent = 
                    Math.floor(status.status.current_tokens || 0);
            } else if (limiter === 'sliding_window') {
                document.getElementById('sliding_window_current').textContent = 
                    `${status.status.current_requests || 0}`;
            } else if (limiter === 'fixed_window') {
                document.getElementById('fixed_window_current').textContent = 
                    `${status.status.current_requests || 0}`;
            }
            
        } catch (error) {
            console.error(`Failed to get ${limiter} status:`, error);
        }
    }
}

// Start metrics updates
function startMetricsUpdate() {
    metricsInterval = setInterval(async () => {
        try {
            const response = await fetch('/api/metrics');
            const metrics = await response.json();
            
            updateMetricsDisplay(metrics);
            updateCharts(metrics);
            
        } catch (error) {
            console.error('Failed to fetch metrics:', error);
        }
    }, 2000); // Update every 2 seconds
}

// Update metrics display
function updateMetricsDisplay(metrics) {
    const realtime = metrics.realtime_stats || {};
    
    // Calculate total RPS
    let totalRps = 0;
    let totalRequests = 0;
    let totalAllowed = 0;
    let avgResponseTime = 0;
    let responseTimeCount = 0;
    
    Object.values(realtime).forEach(stats => {
        if (stats.requests_per_second) {
            totalRps += stats.requests_per_second;
        }
        totalRequests += stats.total || 0;
        totalAllowed += stats.allowed || 0;
        if (stats.avg_processing_time) {
            avgResponseTime += stats.avg_processing_time;
            responseTimeCount++;
        }
    });
    
    const successRate = totalRequests > 0 ? (totalAllowed / totalRequests * 100) : 100;
    const avgTime = responseTimeCount > 0 ? (avgResponseTime / responseTimeCount) : 0;
    
    document.getElementById('rps_value').textContent = totalRps.toFixed(1);
    document.getElementById('success_rate').textContent = `${successRate.toFixed(1)}%`;
    document.getElementById('avg_response_time').textContent = `${avgTime.toFixed(1)}ms`;
    document.getElementById('total_requests').textContent = totalRequests;
}

// Update charts
function updateCharts(metrics) {
    const realtime = metrics.realtime_stats || {};
    const now = new Date().toLocaleTimeString();
    
    // Update request rate chart
    if (requestRateChart.data.labels.length > 20) {
        requestRateChart.data.labels.shift();
        requestRateChart.data.datasets.forEach(dataset => dataset.data.shift());
    }
    
    requestRateChart.data.labels.push(now);
    
    const limiters = ['token_bucket', 'sliding_window', 'fixed_window'];
    limiters.forEach((limiter, index) => {
        const rps = realtime[limiter]?.requests_per_second || 0;
        requestRateChart.data.datasets[index].data.push(rps);
    });
    
    requestRateChart.update('none');
    
    // Update response time chart
    limiters.forEach((limiter, index) => {
        const avgTime = realtime[limiter]?.avg_processing_time || 0;
        responseTimeChart.data.datasets[0].data[index] = avgTime;
    });
    
    responseTimeChart.update('none');
}

// Log request
function logRequest(limiterType, allowed, processingTime, metadata) {
    const timestamp = new Date().toLocaleTimeString();
    const status = allowed ? 'ALLOWED' : 'BLOCKED';
    const className = allowed ? 'success' : 'error';
    
    let message = `[${timestamp}] ${limiterType.toUpperCase()}: ${status}`;
    if (processingTime) {
        message += ` (${processingTime.toFixed(2)}ms)`;
    }
    
    if (metadata && metadata.retry_after) {
        message += ` - Retry after ${metadata.retry_after}s`;
    }
    
    addLog(message, className);
}

// Add log entry
function addLog(message, className = '') {
    const logsContainer = document.getElementById('logs_container');
    const logEntry = document.createElement('div');
    logEntry.className = `log-entry ${className}`;
    logEntry.textContent = message;
    
    logsContainer.insertBefore(logEntry, logsContainer.firstChild);
    
    // Keep only last 100 logs
    while (logsContainer.children.length > 100) {
        logsContainer.removeChild(logsContainer.lastChild);
    }
}

// Cleanup on page unload
window.addEventListener('beforeunload', function() {
    stopBulkTest();
    if (metricsInterval) {
        clearInterval(metricsInterval);
    }
});
