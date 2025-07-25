class CostOptimizationDashboard {
    constructor() {
        this.socket = null;
        this.charts = {};
        this.metricsHistory = [];
        this.maxHistoryLength = 50;
        
        this.initializeCharts();
        this.connectWebSocket();
        this.loadInitialData();
        
        // Update recommendations and savings every 10 seconds
        setInterval(() => {
            this.updateRecommendations();
            this.updateSavings();
        }, 10000);
    }
    
    initializeCharts() {
        const chartOptions = {
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
                    grid: {
                        color: 'rgba(0,0,0,0.1)'
                    }
                },
                x: {
                    display: false
                }
            },
            elements: {
                point: {
                    radius: 0
                },
                line: {
                    tension: 0.4
                }
            }
        };
        
        // Cost chart
        this.charts.cost = new Chart(document.getElementById('cost-chart'), {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    data: [],
                    borderColor: '#FF6B6B',
                    backgroundColor: 'rgba(255, 107, 107, 0.1)',
                    fill: true
                }]
            },
            options: chartOptions
        });
        
        // CPU chart
        this.charts.cpu = new Chart(document.getElementById('cpu-chart'), {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    data: [],
                    borderColor: '#4ECDC4',
                    backgroundColor: 'rgba(78, 205, 196, 0.1)',
                    fill: true
                }]
            },
            options: {
                ...chartOptions,
                scales: {
                    ...chartOptions.scales,
                    y: {
                        ...chartOptions.scales.y,
                        max: 100
                    }
                }
            }
        });
        
        // Memory chart
        this.charts.memory = new Chart(document.getElementById('memory-chart'), {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    data: [],
                    borderColor: '#45B7D1',
                    backgroundColor: 'rgba(69, 183, 209, 0.1)',
                    fill: true
                }]
            },
            options: {
                ...chartOptions,
                scales: {
                    ...chartOptions.scales,
                    y: {
                        ...chartOptions.scales.y,
                        max: 100
                    }
                }
            }
        });
        
        // Network chart
        this.charts.network = new Chart(document.getElementById('network-chart'), {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    data: [],
                    borderColor: '#96CEB4',
                    backgroundColor: 'rgba(150, 206, 180, 0.1)',
                    fill: true
                }]
            },
            options: chartOptions
        });
    }
    
    connectWebSocket() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws/metrics`;
        
        this.socket = new WebSocket(wsUrl);
        
        this.socket.onopen = () => {
            console.log('WebSocket connected');
            this.updateConnectionStatus(true);
        };
        
        this.socket.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.updateMetrics(data);
        };
        
        this.socket.onclose = () => {
            console.log('WebSocket disconnected');
            this.updateConnectionStatus(false);
            // Attempt to reconnect after 5 seconds
            setTimeout(() => this.connectWebSocket(), 5000);
        };
        
        this.socket.onerror = (error) => {
            console.error('WebSocket error:', error);
            this.updateConnectionStatus(false);
        };
    }
    
    updateConnectionStatus(connected) {
        const statusElement = document.getElementById('connection-status');
        if (connected) {
            statusElement.textContent = '● Connected';
            statusElement.className = 'status-connected';
        } else {
            statusElement.textContent = '● Disconnected';
            statusElement.className = 'status-disconnected';
        }
    }
    
    updateMetrics(data) {
        // Update metric values
        document.getElementById('current-cost').textContent = `$${data.estimated_cost.toFixed(3)}/hr`;
        document.getElementById('cpu-usage').textContent = `${data.cpu_usage.toFixed(1)}%`;
        document.getElementById('memory-usage').textContent = `${data.memory_usage.toFixed(1)}%`;
        document.getElementById('network-io').textContent = `${data.network_io.toFixed(1)} MB/s`;
        
        // Update last update time
        document.getElementById('last-update').textContent = `Last update: ${new Date().toLocaleTimeString()}`;
        
        // Add to history
        this.metricsHistory.push(data);
        if (this.metricsHistory.length > this.maxHistoryLength) {
            this.metricsHistory.shift();
        }
        
        // Update charts
        this.updateCharts();
    }
    
    updateCharts() {
        const labels = this.metricsHistory.map((_, index) => index);
        
        // Update cost chart
        this.charts.cost.data.labels = labels;
        this.charts.cost.data.datasets[0].data = this.metricsHistory.map(m => m.estimated_cost);
        this.charts.cost.update('none');
        
        // Update CPU chart
        this.charts.cpu.data.labels = labels;
        this.charts.cpu.data.datasets[0].data = this.metricsHistory.map(m => m.cpu_usage);
        this.charts.cpu.update('none');
        
        // Update memory chart
        this.charts.memory.data.labels = labels;
        this.charts.memory.data.datasets[0].data = this.metricsHistory.map(m => m.memory_usage);
        this.charts.memory.update('none');
        
        // Update network chart
        this.charts.network.data.labels = labels;
        this.charts.network.data.datasets[0].data = this.metricsHistory.map(m => m.network_io);
        this.charts.network.update('none');
    }
    
    async updateRecommendations() {
        try {
            const response = await fetch('/api/recommendations');
            const recommendations = await response.json();
            
            const listElement = document.getElementById('recommendations-list');
            
            if (recommendations.length === 0) {
                listElement.innerHTML = '<div class="loading">No recommendations at this time</div>';
                return;
            }
            
            listElement.innerHTML = recommendations.map(rec => `
                <div class="recommendation-item">
                    <div class="recommendation-type">${rec.type.replace('_', ' ')}</div>
                    <div class="recommendation-description">${rec.description}</div>
                    <div class="recommendation-meta">
                        <span>Potential Savings: ${rec.potential_savings > 0 ? '+' : ''}${rec.potential_savings.toFixed(1)}%</span>
                        <span>Effort: ${rec.implementation_effort}</span>
                    </div>
                </div>
            `).join('');
            
        } catch (error) {
            console.error('Error updating recommendations:', error);
        }
    }
    
    async updateSavings() {
        try {
            const response = await fetch('/api/savings');
            const savings = await response.json();
            
            document.getElementById('monthly-cost').textContent = `$${savings.current_monthly_cost.toFixed(2)}`;
            document.getElementById('projected-savings').textContent = `$${savings.projected_savings.toFixed(2)}`;
            document.getElementById('savings-percentage').textContent = `${savings.savings_percentage.toFixed(1)}%`;
            
        } catch (error) {
            console.error('Error updating savings:', error);
        }
    }
    
    async loadInitialData() {
        try {
            // Load initial metrics history
            const historyResponse = await fetch('/api/history');
            const history = await historyResponse.json();
            this.metricsHistory = history;
            this.updateCharts();
            
            // Load initial recommendations and savings
            await this.updateRecommendations();
            await this.updateSavings();
            
        } catch (error) {
            console.error('Error loading initial data:', error);
        }
    }
}

// Initialize dashboard when page loads
document.addEventListener('DOMContentLoaded', () => {
    new CostOptimizationDashboard();
});
