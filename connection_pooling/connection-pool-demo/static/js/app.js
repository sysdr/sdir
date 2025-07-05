// Connection Pool Demo JavaScript Application
class ConnectionPoolDashboard {
    constructor() {
        this.socket = null;
        this.responseTimeChart = null;
        this.utilizationChart = null;
        this.metricsHistory = [];
        this.maxHistoryLength = 50;
        
        this.init();
    }
    
    init() {
        this.connectWebSocket();
        this.setupEventListeners();
        this.initializeCharts();
        this.loadInitialConfig();
    }
    
    connectWebSocket() {
        this.socket = io();
        
        this.socket.on('connect', () => {
            this.updateConnectionStatus('connected', 'Connected');
            this.showToast('Connected to Connection Pool Demo', 'success');
        });
        
        this.socket.on('disconnect', () => {
            this.updateConnectionStatus('disconnected', 'Disconnected');
            this.showToast('Disconnected from server', 'error');
        });
        
        this.socket.on('metrics_update', (metrics) => {
            this.updateMetrics(metrics);
        });
        
        this.socket.on('scenario_update', (data) => {
            this.showToast(`Scenario: ${data.scenario} - ${data.status}`, 'success');
        });
    }
    
    updateConnectionStatus(status, text) {
        const statusDot = document.getElementById('connection-status');
        const statusText = document.getElementById('status-text');
        
        statusDot.className = `status-dot status-${status}`;
        statusText.textContent = text;
    }
    
    setupEventListeners() {
        // Configuration update
        document.getElementById('update-config').addEventListener('click', () => {
            this.updateConfiguration();
        });
        
        // Scenario buttons
        document.querySelectorAll('.btn-scenario').forEach(button => {
            button.addEventListener('click', (e) => {
                const scenario = e.target.dataset.scenario;
                this.runScenario(scenario);
            });
        });
        
        // Toast close button
        document.getElementById('toast-close').addEventListener('click', () => {
            this.hideToast();
        });
        
        // Auto-hide toast after 5 seconds
        setInterval(() => {
            const toast = document.getElementById('toast');
            if (toast.classList.contains('show')) {
                setTimeout(() => this.hideToast(), 5000);
            }
        }, 1000);
    }
    
    async loadInitialConfig() {
        try {
            const response = await fetch('/api/config');
            const config = await response.json();
            
            document.getElementById('max-pool-size').value = config.max_pool_size;
            document.getElementById('min-pool-size').value = config.min_pool_size;
            document.getElementById('pool-timeout').value = config.pool_timeout;
        } catch (error) {
            console.error('Failed to load initial config:', error);
        }
    }
    
    async updateConfiguration() {
        const config = {
            max_pool_size: parseInt(document.getElementById('max-pool-size').value),
            min_pool_size: parseInt(document.getElementById('min-pool-size').value),
            pool_timeout: parseInt(document.getElementById('pool-timeout').value)
        };
        
        try {
            const response = await fetch('/api/config', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(config)
            });
            
            const result = await response.json();
            
            if (result.status === 'updated') {
                this.showToast('Configuration updated successfully', 'success');
            } else {
                this.showToast('Failed to update configuration', 'error');
            }
        } catch (error) {
            console.error('Configuration update failed:', error);
            this.showToast('Configuration update failed', 'error');
        }
    }
    
    async runScenario(scenarioName) {
        const button = document.querySelector(`[data-scenario="${scenarioName}"]`);
        const originalText = button.textContent;
        
        button.disabled = true;
        button.textContent = 'Running...';
        
        try {
            const response = await fetch(`/api/scenarios/${scenarioName}`, {
                method: 'POST'
            });
            
            const result = await response.json();
            
            if (result.status === 'running') {
                this.showToast(`Started scenario: ${scenarioName}`, 'success');
            } else {
                this.showToast(`Failed to run scenario: ${result.error}`, 'error');
            }
        } catch (error) {
            console.error('Scenario execution failed:', error);
            this.showToast('Scenario execution failed', 'error');
        } finally {
            setTimeout(() => {
                button.disabled = false;
                button.textContent = originalText;
            }, 3000);
        }
    }
    
    updateMetrics(metrics) {
        // Add to history
        this.metricsHistory.push({
            timestamp: new Date(),
            ...metrics
        });
        
        if (this.metricsHistory.length > this.maxHistoryLength) {
            this.metricsHistory.shift();
        }
        
        // Update metric cards
        document.getElementById('pool-utilization').textContent = 
            `${Math.round(metrics.pool_utilization_percent)}%`;
        document.getElementById('queue-depth').textContent = metrics.queue_size;
        document.getElementById('response-time').textContent = 
            `${Math.round(metrics.avg_response_time_ms)}ms`;
        document.getElementById('error-rate').textContent = 
            `${Math.round(metrics.error_rate_percent)}%`;
        
        // Update progress bars
        this.updateProgressBar('utilization-bar', metrics.pool_utilization_percent);
        this.updateProgressBar('queue-bar', Math.min(metrics.queue_size * 10, 100));
        this.updateProgressBar('response-bar', Math.min(metrics.avg_response_time_ms / 10, 100));
        this.updateProgressBar('error-bar', metrics.error_rate_percent);
        
        // Update connection visualization
        this.updateConnectionVisualization(metrics);
        
        // Update charts
        this.updateCharts();
    }
    
    updateProgressBar(elementId, percentage) {
        const bar = document.getElementById(elementId);
        bar.style.width = `${Math.max(0, Math.min(100, percentage))}%`;
        
        // Color coding based on thresholds
        if (percentage > 80) {
            bar.style.backgroundColor = 'var(--error-red)';
        } else if (percentage > 60) {
            bar.style.backgroundColor = 'var(--warning-orange)';
        } else {
            bar.style.backgroundColor = 'var(--success-green)';
        }
    }
    
    updateConnectionVisualization(metrics) {
        const grid = document.getElementById('connections-grid');
        const queueContainer = document.getElementById('queue-container');
        
        // Update connection counts
        document.getElementById('available-count').textContent = metrics.available;
        document.getElementById('in-use-count').textContent = metrics.checked_out;
        document.getElementById('total-count').textContent = metrics.pool_size;
        
        // Clear existing connections
        grid.innerHTML = '';
        
        // Add connection visualizations
        for (let i = 0; i < metrics.pool_size; i++) {
            const connection = document.createElement('div');
            connection.className = 'connection';
            
            if (i < metrics.checked_out) {
                connection.classList.add('in-use');
                connection.textContent = 'U';
                connection.title = 'Connection in use';
            } else {
                connection.classList.add('available');
                connection.textContent = 'A';
                connection.title = 'Available connection';
            }
            
            grid.appendChild(connection);
        }
        
        // Update queue visualization
        queueContainer.innerHTML = '';
        
        for (let i = 0; i < Math.min(metrics.queue_size, 20); i++) {
            const queueItem = document.createElement('div');
            queueItem.className = 'queue-item';
            queueItem.textContent = 'Q';
            queueItem.title = 'Queued request';
            queueContainer.appendChild(queueItem);
        }
        
        if (metrics.queue_size > 20) {
            const overflow = document.createElement('div');
            overflow.className = 'queue-item';
            overflow.textContent = `+${metrics.queue_size - 20}`;
            overflow.title = `${metrics.queue_size - 20} more queued requests`;
            queueContainer.appendChild(overflow);
        }
    }
    
    initializeCharts() {
        // Response Time Chart
        const responseTimeCtx = document.getElementById('response-time-chart').getContext('2d');
        this.responseTimeChart = new Chart(responseTimeCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Response Time (ms)',
                    data: [],
                    borderColor: '#1a73e8',
                    backgroundColor: 'rgba(26, 115, 232, 0.1)',
                    tension: 0.4,
                    fill: true
                }]
            },
            options: {
                responsive: true,
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
                    },
                    x: {
                        title: {
                            display: true,
                            text: 'Time'
                        }
                    }
                }
            }
        });
        
        // Utilization Chart
        const utilizationCtx = document.getElementById('utilization-chart').getContext('2d');
        this.utilizationChart = new Chart(utilizationCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Pool Utilization (%)',
                    data: [],
                    borderColor: '#34a853',
                    backgroundColor: 'rgba(52, 168, 83, 0.1)',
                    tension: 0.4,
                    fill: true
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        display: false
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 100,
                        title: {
                            display: true,
                            text: 'Utilization (%)'
                        }
                    },
                    x: {
                        title: {
                            display: true,
                            text: 'Time'
                        }
                    }
                }
            }
        });
    }
    
    updateCharts() {
        if (this.metricsHistory.length === 0) return;
        
        const labels = this.metricsHistory.map(m => 
            m.timestamp.toLocaleTimeString()
        );
        
        const responseTimeData = this.metricsHistory.map(m => 
            m.avg_response_time_ms || 0
        );
        
        const utilizationData = this.metricsHistory.map(m => 
            m.pool_utilization_percent || 0
        );
        
        // Update response time chart
        this.responseTimeChart.data.labels = labels;
        this.responseTimeChart.data.datasets[0].data = responseTimeData;
        this.responseTimeChart.update('none');
        
        // Update utilization chart
        this.utilizationChart.data.labels = labels;
        this.utilizationChart.data.datasets[0].data = utilizationData;
        this.utilizationChart.update('none');
    }
    
    showToast(message, type = 'info') {
        const toast = document.getElementById('toast');
        const messageElement = document.getElementById('toast-message');
        
        messageElement.textContent = message;
        toast.className = `toast ${type} show`;
        
        // Auto-hide after 5 seconds
        setTimeout(() => {
            this.hideToast();
        }, 5000);
    }
    
    hideToast() {
        const toast = document.getElementById('toast');
        toast.classList.remove('show');
    }
}

// Initialize the dashboard when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new ConnectionPoolDashboard();
});
