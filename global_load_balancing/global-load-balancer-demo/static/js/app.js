// Global Load Balancing Demo JavaScript
// System Design Interview Roadmap - Issue #99

class GlobalLoadBalancerDemo {
    constructor() {
        this.socket = null;
        this.latencyChart = null;
        this.trafficSimulation = null;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        this.updateInterval = null;
        this.init();
    }

    init() {
        this.setupSocketConnection();
        this.setupEventListeners();
        this.setupLatencyChart();
        this.startPeriodicUpdates();
    }

    setupSocketConnection() {
        try {
            this.socket = io({
                transports: ['websocket', 'polling'],
                timeout: 20000,
                reconnection: true,
                reconnectionAttempts: this.maxReconnectAttempts,
                reconnectionDelay: 1000
            });

            this.socket.on('connect', () => {
                console.log('✅ Connected to Global Load Balancer Demo');
                this.reconnectAttempts = 0;
                this.requestInitialData();
                this.updateConnectionStatus('connected');
            });

            this.socket.on('disconnect', () => {
                console.log('❌ Disconnected from Global Load Balancer Demo');
                this.updateConnectionStatus('disconnected');
            });

            this.socket.on('connect_error', (error) => {
                console.error('🔴 Connection error:', error);
                this.updateConnectionStatus('error');
            });

            this.socket.on('data_centers_update', (data) => {
                console.log('📊 Received data centers update:', data);
                this.updateDataCenters(data);
            });

            this.socket.on('stats_update', (data) => {
                console.log('📈 Received stats update:', data);
                this.updateGlobalStats(data);
                this.updateLatencyChart(data);
            });

            this.socket.on('request_processed', (data) => {
                console.log('🔄 Request processed:', data);
                this.addRoutingLogEntry(data);
            });

        } catch (error) {
            console.error('❌ Failed to setup socket connection:', error);
            this.updateConnectionStatus('error');
        }
    }

    updateConnectionStatus(status) {
        const statusElement = document.getElementById('connection-status');
        if (!statusElement) {
            // Create status element if it doesn't exist
            const header = document.querySelector('.header-content');
            const statusDiv = document.createElement('div');
            statusDiv.id = 'connection-status';
            statusDiv.className = 'connection-status';
            header.appendChild(statusDiv);
        }

        const element = document.getElementById('connection-status');
        element.className = `connection-status ${status}`;
        
        switch(status) {
            case 'connected':
                element.innerHTML = '🟢 Connected';
                break;
            case 'disconnected':
                element.innerHTML = '🟡 Disconnected';
                break;
            case 'error':
                element.innerHTML = '🔴 Connection Error';
                break;
        }
    }

    setupEventListeners() {
        const sendRequestBtn = document.getElementById('send-request');
        const simulateTrafficBtn = document.getElementById('simulate-traffic');
        const strategySelect = document.getElementById('strategy');

        if (sendRequestBtn) {
            sendRequestBtn.addEventListener('click', () => {
                this.sendRequest();
            });
        }

        if (simulateTrafficBtn) {
            simulateTrafficBtn.addEventListener('click', () => {
                this.toggleTrafficSimulation();
            });
        }

        if (strategySelect) {
            strategySelect.addEventListener('change', (e) => {
                this.updateStrategy(e.target.value);
            });
        }
    }

    setupLatencyChart() {
        const canvas = document.getElementById('latencyChart');
        if (!canvas) {
            console.error('❌ Latency chart canvas not found');
            return;
        }

        const ctx = canvas.getContext('2d');
        this.latencyChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Average Latency (ms)',
                    data: [],
                    borderColor: '#1a73e8',
                    backgroundColor: 'rgba(26, 115, 232, 0.1)',
                    borderWidth: 2,
                    fill: true,
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: {
                    duration: 300
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Latency (ms)'
                        }
                    },
                    x: {
                        title: {
                            display: true,
                            text: 'Time'
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: true,
                        position: 'top'
                    }
                }
            }
        });
    }

    startPeriodicUpdates() {
        // Fallback: If WebSocket fails, use polling
        this.updateInterval = setInterval(() => {
            this.fetchLatestData();
        }, 3000); // Poll every 3 seconds as fallback
    }

    fetchLatestData() {
        // Fetch data centers
        fetch('/api/data-centers')
            .then(response => response.json())
            .then(data => {
                this.updateDataCenters(data);
            })
            .catch(error => {
                console.error('❌ Error fetching data centers:', error);
            });

        // Fetch stats
        fetch('/api/stats')
            .then(response => response.json())
            .then(data => {
                this.updateGlobalStats(data);
                this.updateLatencyChart(data);
            })
            .catch(error => {
                console.error('❌ Error fetching stats:', error);
            });
    }

    requestInitialData() {
        if (this.socket && this.socket.connected) {
            this.socket.emit('get_initial_data');
        } else {
            console.log('📡 Socket not connected, using HTTP fallback');
            this.fetchLatestData();
        }
    }

    sendRequest() {
        const userLocation = document.getElementById('user-location')?.value || 'new_york';
        const strategy = document.getElementById('strategy')?.value || 'latency';

        // Update strategy first
        fetch('/api/config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ strategy: strategy })
        })
        .catch(error => {
            console.error('❌ Error updating strategy:', error);
        });

        // Send request
        fetch('/api/request', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ user_location: userLocation })
        })
        .then(response => response.json())
        .then(data => {
            console.log('✅ Request processed:', data);
            this.addRoutingLogEntry(data);
        })
        .catch(error => {
            console.error('❌ Error sending request:', error);
        });
    }

    toggleTrafficSimulation() {
        const button = document.getElementById('simulate-traffic');
        
        if (this.trafficSimulation) {
            clearInterval(this.trafficSimulation);
            this.trafficSimulation = null;
            button.textContent = 'Simulate Traffic';
            button.classList.remove('btn-primary');
            button.classList.add('btn-secondary');
            console.log('⏹️ Traffic simulation stopped');
        } else {
            button.textContent = 'Stop Simulation';
            button.classList.remove('btn-secondary');
            button.classList.add('btn-primary');
            
            this.trafficSimulation = setInterval(() => {
                // Random user locations
                const locations = ['new_york', 'london', 'tokyo', 'sydney', 'sao_paulo'];
                const randomLocation = locations[Math.floor(Math.random() * locations.length)];
                
                // Update user location select
                const locationSelect = document.getElementById('user-location');
                if (locationSelect) {
                    locationSelect.value = randomLocation;
                }
                
                // Send request
                this.sendRequest();
            }, 1000); // Send request every second
            
            console.log('▶️ Traffic simulation started');
        }
    }

    updateStrategy(strategy) {
        fetch('/api/config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ strategy: strategy })
        })
        .then(response => response.json())
        .then(data => {
            console.log('✅ Strategy updated:', strategy);
        })
        .catch(error => {
            console.error('❌ Error updating strategy:', error);
        });
    }

    updateDataCenters(dataCenters) {
        const container = document.getElementById('data-centers');
        if (!container) {
            console.error('❌ Data centers container not found');
            return;
        }

        container.innerHTML = '';

        Object.entries(dataCenters).forEach(([dcId, dcInfo]) => {
            const dcElement = document.createElement('div');
            dcElement.className = `dc-item ${dcInfo.health}`;
            
            const utilizationPercent = Math.round((dcInfo.current_load / dcInfo.capacity) * 100);
            
            dcElement.innerHTML = `
                <div class="dc-health ${dcInfo.health}"></div>
                <div class="dc-name">${dcInfo.name}</div>
                <div class="dc-stats">
                    <span>Load: ${dcInfo.current_load}/${dcInfo.capacity}</span>
                    <span>Utilization: ${utilizationPercent}%</span>
                </div>
                <div class="dc-stats">
                    <span>Base Latency: ${dcInfo.latency_base}ms</span>
                    <span>Status: ${dcInfo.health}</span>
                </div>
            `;
            
            // Add click handler for manual health toggle
            dcElement.addEventListener('click', () => {
                this.toggleDataCenterHealth(dcId, dcInfo.health);
            });
            
            container.appendChild(dcElement);
        });
    }

    toggleDataCenterHealth(dcId, currentHealth) {
        const newHealth = currentHealth === 'healthy' ? 'unhealthy' : 'healthy';
        
        fetch('/api/config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                dc_health: {
                    dc_id: dcId,
                    status: newHealth
                }
            })
        })
        .then(response => response.json())
        .then(data => {
            console.log(`✅ Data center ${dcId} health toggled to ${newHealth}`);
        })
        .catch(error => {
            console.error('❌ Error toggling data center health:', error);
        });
    }

    updateGlobalStats(stats) {
        const elements = {
            'total-requests': stats.total_requests,
            'failed-requests': stats.failed_requests,
            'success-rate': stats.total_requests > 0 ? 
                `${Math.round((stats.successful_requests / stats.total_requests) * 100)}%` : '0%',
            'avg-latency': `${Math.round(stats.average_latency)}ms`
        };

        Object.entries(elements).forEach(([id, value]) => {
            const element = document.getElementById(id);
            if (element) {
                element.textContent = value;
            }
        });
    }

    updateLatencyChart(stats) {
        if (!this.latencyChart) {
            console.error('❌ Latency chart not initialized');
            return;
        }

        const now = new Date().toLocaleTimeString();
        
        // Add new data point
        this.latencyChart.data.labels.push(now);
        this.latencyChart.data.datasets[0].data.push(Math.round(stats.average_latency));
        
        // Keep only last 20 data points
        if (this.latencyChart.data.labels.length > 20) {
            this.latencyChart.data.labels.shift();
            this.latencyChart.data.datasets[0].data.shift();
        }
        
        this.latencyChart.update('none');
    }

    addRoutingLogEntry(decision) {
        const logContainer = document.getElementById('routing-log');
        if (!logContainer) {
            console.error('❌ Routing log container not found');
            return;
        }

        const logEntry = document.createElement('div');
        logEntry.className = `log-entry ${decision.success ? 'success' : 'error'}`;
        
        const timestamp = new Date(decision.timestamp).toLocaleTimeString();
        
        logEntry.innerHTML = `
            <div class="log-timestamp">${timestamp}</div>
            <div class="log-details">
                📍 ${decision.user_location} → 🏢 ${decision.selected_dc} 
                (${decision.latency}ms, ${decision.strategy})
                ${decision.success ? '✅' : '❌'}
            </div>
        `;
        
        logContainer.insertBefore(logEntry, logContainer.firstChild);
        
        // Keep only last 50 entries
        while (logContainer.children.length > 50) {
            logContainer.removeChild(logContainer.lastChild);
        }
    }

    // Utility method to format numbers
    formatNumber(num) {
        return new Intl.NumberFormat().format(num);
    }

    // Utility method to format bytes
    formatBytes(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    // Cleanup method
    destroy() {
        if (this.trafficSimulation) {
            clearInterval(this.trafficSimulation);
        }
        if (this.updateInterval) {
            clearInterval(this.updateInterval);
        }
        if (this.socket) {
            this.socket.disconnect();
        }
    }
}

// Initialize the demo when the page loads
let demo = null;

document.addEventListener('DOMContentLoaded', () => {
    console.log('🚀 Initializing Global Load Balancer Demo...');
    demo = new GlobalLoadBalancerDemo();
});

// Add some visual feedback for button clicks
document.addEventListener('click', (e) => {
    if (e.target.classList.contains('btn-primary') || e.target.classList.contains('btn-secondary')) {
        e.target.style.transform = 'scale(0.95)';
        setTimeout(() => {
            e.target.style.transform = '';
        }, 150);
    }
});

// Add keyboard shortcuts
document.addEventListener('keydown', (e) => {
    if (e.ctrlKey || e.metaKey) {
        switch(e.key) {
            case 'Enter':
                e.preventDefault();
                document.getElementById('send-request')?.click();
                break;
            case ' ':
                e.preventDefault();
                document.getElementById('simulate-traffic')?.click();
                break;
        }
    }
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    if (demo) {
        demo.destroy();
    }
});
