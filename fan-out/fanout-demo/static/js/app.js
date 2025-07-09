class FanOutDemo {
    constructor() {
        this.socket = io();
        this.metricsChart = null;
        this.init();
    }

    init() {
        this.setupSocketListeners();
        this.setupEventListeners();
        this.loadUsers();
        this.startMetricsUpdates();
        this.initChart();
    }

    setupSocketListeners() {
        this.socket.on('connect', () => {
            console.log('Connected to server');
        });

        this.socket.on('disconnect', () => {
            console.log('Disconnected from server');
        });

        this.socket.on('error', (error) => {
            console.error('Socket error:', error);
        });

        this.socket.on('fanout_update', (data) => {
            console.log('Received fanout_update:', data);
            this.addActivityItem(data);
        });

        // Test if socket is connected
        setTimeout(() => {
            console.log('Socket connected:', this.socket.connected);
            console.log('Socket id:', this.socket.id);
        }, 1000);
    }

    setupEventListeners() {
        document.getElementById('postButton').addEventListener('click', () => {
            this.postMessage();
        });

        document.getElementById('messageContent').addEventListener('keypress', (e) => {
            if (e.key === 'Enter' && e.ctrlKey) {
                this.postMessage();
            }
        });
    }

    async loadUsers() {
        try {
            const response = await fetch('/api/users');
            const users = await response.json();
            this.populateUserSelect(users);
        } catch (error) {
            console.error('Error loading users:', error);
        }
    }

    populateUserSelect(users) {
        const select = document.getElementById('userSelect');
        select.innerHTML = '<option value="">Select a user...</option>';
        
        users.forEach(user => {
            const option = document.createElement('option');
            option.value = user.id;
            option.textContent = `${user.id} (${user.follower_count} followers - ${user.tier})`;
            select.appendChild(option);
        });
    }

    async postMessage() {
        const userId = document.getElementById('userSelect').value;
        const content = document.getElementById('messageContent').value.trim();

        if (!userId || !content) {
            alert('Please select a user and enter a message');
            return;
        }

        try {
            const response = await fetch('/api/post_message', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    user_id: userId,
                    content: content
                })
            });

            if (response.ok) {
                document.getElementById('messageContent').value = '';
                this.showNotification('Message posted successfully!', 'success');
            }
        } catch (error) {
            console.error('Error posting message:', error);
            this.showNotification('Error posting message', 'error');
        }
    }

    addActivityItem(data) {
        console.log('Adding activity item:', data);
        const feed = document.getElementById('activityFeed');
        if (!feed) {
            console.error('Activity feed element not found');
            return;
        }
        
        const placeholder = feed.querySelector('.placeholder');
        if (placeholder) {
            console.log('Removing placeholder');
            placeholder.remove();
        }

        const item = document.createElement('div');
        item.className = 'activity-item';
        
        const strategy = data.message.fanout_strategy === 'write' ? 'Fan-Out on Write' : 'Fan-Out on Read';
        const strategyClass = data.message.fanout_strategy === 'write' ? 'write' : 'read';
        
        item.innerHTML = `
            <div class="activity-strategy ${strategyClass}">${strategy}</div>
            <div class="activity-content">${data.message.content}</div>
            <div class="activity-meta">
                <span>User: ${data.message.user_id}</span>
                <span>Tier: ${data.user_tier}</span>
                <span>Time: ${new Date(data.timestamp).toLocaleTimeString()}</span>
                ${data.result.processing_time ? `<span>Processed in: ${(data.result.processing_time * 1000).toFixed(2)}ms</span>` : ''}
            </div>
        `;

        feed.insertBefore(item, feed.firstChild);
        console.log('Activity item added successfully');

        // Keep only last 10 items
        const items = feed.querySelectorAll('.activity-item');
        if (items.length > 10) {
            items[items.length - 1].remove();
        }
    }

    async startMetricsUpdates() {
        setInterval(async () => {
            await this.updateStats();
        }, 2000);
        
        // Initial update
        await this.updateStats();
    }

    async updateStats() {
        try {
            const response = await fetch('/api/stats');
            const stats = await response.json();
            
            document.getElementById('totalUsers').textContent = stats.total_users;
            document.getElementById('queueSize').textContent = stats.queue_size;
            document.getElementById('cpuUsage').textContent = `${stats.cpu_usage.toFixed(1)}%`;
            
            document.getElementById('celebrityCount').textContent = stats.users_by_tier.celebrity || 0;
            document.getElementById('regularCount').textContent = stats.users_by_tier.regular || 0;
            document.getElementById('inactiveCount').textContent = stats.users_by_tier.inactive || 0;
            
        } catch (error) {
            console.error('Error updating stats:', error);
        }
    }

    initChart() {
        const ctx = document.getElementById('metricsChart').getContext('2d');
        this.metricsChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Fan-Out Operations/sec',
                    data: [],
                    borderColor: '#1976d2',
                    backgroundColor: 'rgba(25, 118, 210, 0.1)',
                    tension: 0.4
                }, {
                    label: 'Average Processing Time (ms)',
                    data: [],
                    borderColor: '#ff9800',
                    backgroundColor: 'rgba(255, 152, 0, 0.1)',
                    tension: 0.4,
                    yAxisID: 'y1'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        type: 'linear',
                        display: true,
                        position: 'left',
                    },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        grid: {
                            drawOnChartArea: false,
                        },
                    }
                },
                plugins: {
                    legend: {
                        position: 'top',
                    }
                }
            }
        });

        // Simulate some metric updates
        setInterval(() => {
            this.updateChart();
        }, 3000);
    }

    updateChart() {
        const now = new Date().toLocaleTimeString();
        const operations = Math.floor(Math.random() * 100) + 50;
        const processingTime = Math.random() * 50 + 10;

        this.metricsChart.data.labels.push(now);
        this.metricsChart.data.datasets[0].data.push(operations);
        this.metricsChart.data.datasets[1].data.push(processingTime);

        // Keep only last 10 data points
        if (this.metricsChart.data.labels.length > 10) {
            this.metricsChart.data.labels.shift();
            this.metricsChart.data.datasets[0].data.shift();
            this.metricsChart.data.datasets[1].data.shift();
        }

        this.metricsChart.update('none');
    }

    showNotification(message, type) {
        // Simple notification system
        const notification = document.createElement('div');
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 12px 24px;
            border-radius: 8px;
            color: white;
            font-weight: 500;
            z-index: 1000;
            background: ${type === 'success' ? '#4caf50' : '#f44336'};
            animation: slideInRight 0.3s ease-out;
        `;
        notification.textContent = message;
        
        document.body.appendChild(notification);
        
        setTimeout(() => {
            notification.remove();
        }, 3000);
    }
}

// Initialize the demo when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new FanOutDemo();
});
