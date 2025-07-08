// Async Processing Demo - JavaScript Application
class AsyncProcessingApp {
    constructor() {
        this.tasks = new Map();
        this.refreshInterval = null;
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.startAutoRefresh();
        this.refreshData();
    }

    setupEventListeners() {
        // Form submissions
        document.getElementById('imageForm').addEventListener('submit', (e) => this.handleImageSubmit(e));
        document.getElementById('emailForm').addEventListener('submit', (e) => this.handleEmailSubmit(e));
        document.getElementById('reportForm').addEventListener('submit', (e) => this.handleReportSubmit(e));
        document.getElementById('computationForm').addEventListener('submit', (e) => this.handleComputationSubmit(e));

        // Control buttons
        document.getElementById('refreshTasks').addEventListener('click', () => this.refreshData());
        document.getElementById('clearCompleted').addEventListener('click', () => this.clearCompletedTasks());
    }

    async handleImageSubmit(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        
        try {
            this.showNotification('Uploading image for processing...', 'info');
            const response = await fetch('/api/tasks/image-processing', {
                method: 'POST',
                body: formData
            });
            
            const result = await response.json();
            if (response.ok) {
                this.showNotification(`Image processing task created: ${result.task_id}`, 'success');
                this.refreshData();
                e.target.reset();
            } else {
                throw new Error(result.detail || 'Failed to create task');
            }
        } catch (error) {
            this.showNotification(`Error: ${error.message}`, 'error');
        }
    }

    async handleEmailSubmit(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        
        try {
            this.showNotification('Creating email task...', 'info');
            const response = await fetch('/api/tasks/email', {
                method: 'POST',
                body: formData
            });
            
            const result = await response.json();
            if (response.ok) {
                this.showNotification(`Email task created: ${result.task_id}`, 'success');
                this.refreshData();
                e.target.reset();
            } else {
                throw new Error(result.detail || 'Failed to create task');
            }
        } catch (error) {
            this.showNotification(`Error: ${error.message}`, 'error');
        }
    }

    async handleReportSubmit(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        
        try {
            this.showNotification('Creating report generation task...', 'info');
            const response = await fetch('/api/tasks/report', {
                method: 'POST',
                body: formData
            });
            
            const result = await response.json();
            if (response.ok) {
                this.showNotification(`Report task created: ${result.task_id}`, 'success');
                this.refreshData();
                e.target.reset();
            } else {
                throw new Error(result.detail || 'Failed to create task');
            }
        } catch (error) {
            this.showNotification(`Error: ${error.message}`, 'error');
        }
    }

    async handleComputationSubmit(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        
        try {
            this.showNotification('Creating computation task...', 'info');
            const response = await fetch('/api/tasks/computation', {
                method: 'POST',
                body: formData
            });
            
            const result = await response.json();
            if (response.ok) {
                this.showNotification(`Computation task created: ${result.task_id}`, 'success');
                this.refreshData();
                e.target.reset();
            } else {
                throw new Error(result.detail || 'Failed to create task');
            }
        } catch (error) {
            this.showNotification(`Error: ${error.message}`, 'error');
        }
    }

    async refreshData() {
        try {
            await Promise.all([
                this.updateQueueStats(),
                this.updateTasksList(),
                this.updateMetrics()
            ]);
        } catch (error) {
            console.error('Error refreshing data:', error);
        }
    }

    async updateQueueStats() {
        try {
            const response = await fetch('/api/queue-stats');
            const stats = await response.json();
            
            document.getElementById('queueDepth').textContent = stats.reserved_tasks || 0;
            document.getElementById('workerCount').textContent = stats.workers_online || 0;
            document.getElementById('activeTasks').textContent = stats.active_tasks || 0;
        } catch (error) {
            console.error('Error updating queue stats:', error);
        }
    }

    async updateTasksList() {
        try {
            const response = await fetch('/api/tasks');
            const tasks = await response.json();
            
            const tasksList = document.getElementById('tasksList');
            tasksList.innerHTML = '';
            
            if (tasks.length === 0) {
                tasksList.innerHTML = '<div class="no-tasks">No tasks found. Create a task to get started!</div>';
                return;
            }
            
            tasks.forEach(task => {
                const taskElement = this.createTaskElement(task);
                tasksList.appendChild(taskElement);
            });
        } catch (error) {
            console.error('Error updating tasks list:', error);
        }
    }

    createTaskElement(task) {
        const div = document.createElement('div');
        div.className = 'task-item';
        
        const createdAt = new Date(task.created_at).toLocaleString();
        const updatedAt = task.updated_at ? new Date(task.updated_at).toLocaleString() : 'Not updated';
        
        let resultInfo = '';
        if (task.result) {
            if (task.task_type === 'image_processing') {
                resultInfo = `Processed: ${task.result.operation} (${task.result.processing_time?.toFixed(2)}s)`;
            } else if (task.task_type === 'email') {
                resultInfo = `Sent to: ${task.result.recipient}`;
            } else if (task.task_type === 'report') {
                resultInfo = `Generated: ${task.result.record_count} records (${task.result.file_size})`;
            } else if (task.task_type === 'computation') {
                resultInfo = `Completed: ${task.result.iterations} iterations (${task.result.elapsed_time?.toFixed(2)}s)`;
            }
        }
        
        let errorInfo = '';
        if (task.error) {
            errorInfo = `<div class="task-error">Error: ${task.error}</div>`;
        }
        
        div.innerHTML = `
            <div class="task-info">
                <div class="task-title">
                    <i class="fas ${this.getTaskIcon(task.task_type)}"></i>
                    ${this.getTaskTitle(task.task_type)} - ${task.id.substring(0, 8)}
                </div>
                <div class="task-meta">
                    Created: ${createdAt}
                    ${task.updated_at ? `| Updated: ${updatedAt}` : ''}
                </div>
                ${resultInfo ? `<div class="task-result">${resultInfo}</div>` : ''}
                ${errorInfo}
            </div>
            <div class="task-status status-${task.status}">
                ${task.status}
            </div>
        `;
        
        return div;
    }

    getTaskIcon(taskType) {
        const icons = {
            'image_processing': 'fa-image',
            'email': 'fa-envelope',
            'report': 'fa-chart-bar',
            'computation': 'fa-calculator'
        };
        return icons[taskType] || 'fa-cog';
    }

    getTaskTitle(taskType) {
        const titles = {
            'image_processing': 'Image Processing',
            'email': 'Email Task',
            'report': 'Report Generation',
            'computation': 'Computation'
        };
        return titles[taskType] || 'Unknown Task';
    }

    async updateMetrics() {
        try {
            const response = await fetch('/api/metrics');
            const metrics = await response.json();
            
            this.updateStatusChart(metrics.task_status_counts || {});
            this.updateTypeChart(metrics.task_type_counts || {});
            this.updatePerformanceMetrics(metrics.queue_stats || {});
        } catch (error) {
            console.error('Error updating metrics:', error);
        }
    }

    updateStatusChart(statusCounts) {
        const chartContainer = document.getElementById('statusChart');
        chartContainer.innerHTML = '';
        
        const total = Object.values(statusCounts).reduce((sum, count) => sum + count, 0);
        
        if (total === 0) {
            chartContainer.innerHTML = '<div class="no-data">No task data available</div>';
            return;
        }
        
        const colors = {
            'pending': '#fbbc04',
            'processing': '#4285f4',
            'completed': '#34a853',
            'failed': '#ea4335',
            'retrying': '#174ea6'
        };
        
        Object.entries(statusCounts).forEach(([status, count]) => {
            const percentage = ((count / total) * 100).toFixed(1);
            const bar = document.createElement('div');
            bar.style.cssText = `
                display: flex;
                justify-content: space-between;
                align-items: center;
                padding: 0.5rem;
                margin: 0.25rem 0;
                background: ${colors[status] || '#5f6368'}20;
                border-left: 4px solid ${colors[status] || '#5f6368'};
                border-radius: 4px;
                font-size: 0.875rem;
            `;
            bar.innerHTML = `
                <span style="text-transform: capitalize;">${status}</span>
                <span style="font-weight: 500;">${count} (${percentage}%)</span>
            `;
            chartContainer.appendChild(bar);
        });
    }

    updateTypeChart(typeCounts) {
        const chartContainer = document.getElementById('typeChart');
        chartContainer.innerHTML = '';
        
        const total = Object.values(typeCounts).reduce((sum, count) => sum + count, 0);
        
        if (total === 0) {
            chartContainer.innerHTML = '<div class="no-data">No task data available</div>';
            return;
        }
        
        const colors = ['#1a73e8', '#34a853', '#fbbc04', '#ea4335'];
        
        Object.entries(typeCounts).forEach(([type, count], index) => {
            const percentage = ((count / total) * 100).toFixed(1);
            const bar = document.createElement('div');
            bar.style.cssText = `
                display: flex;
                justify-content: space-between;
                align-items: center;
                padding: 0.5rem;
                margin: 0.25rem 0;
                background: ${colors[index % colors.length]}20;
                border-left: 4px solid ${colors[index % colors.length]};
                border-radius: 4px;
                font-size: 0.875rem;
            `;
            bar.innerHTML = `
                <span style="text-transform: capitalize;">${type.replace('_', ' ')}</span>
                <span style="font-weight: 500;">${count} (${percentage}%)</span>
            `;
            chartContainer.appendChild(bar);
        });
    }

    updatePerformanceMetrics(queueStats) {
        const container = document.getElementById('performanceMetrics');
        container.innerHTML = '';
        
        const metrics = [
            { label: 'Active Tasks', value: queueStats.active_tasks || 0 },
            { label: 'Reserved Tasks', value: queueStats.reserved_tasks || 0 },
            { label: 'Workers Online', value: queueStats.workers_online || 0 },
            { label: 'Last Updated', value: queueStats.timestamp ? new Date(queueStats.timestamp).toLocaleTimeString() : 'Never' }
        ];
        
        metrics.forEach(metric => {
            const row = document.createElement('div');
            row.className = 'metric-row';
            row.innerHTML = `
                <span class="metric-label">${metric.label}</span>
                <span class="metric-value">${metric.value}</span>
            `;
            container.appendChild(row);
        });
    }

    async clearCompletedTasks() {
        // This would typically call an API endpoint to clear completed tasks
        this.showNotification('Cleared completed tasks (demo)', 'success');
        this.refreshData();
    }

    showNotification(message, type = 'info') {
        const notifications = document.getElementById('notifications');
        const notification = document.createElement('div');
        notification.className = `notification ${type}`;
        notification.textContent = message;
        
        notifications.appendChild(notification);
        
        // Auto-remove after 5 seconds
        setTimeout(() => {
            if (notification.parentNode) {
                notification.parentNode.removeChild(notification);
            }
        }, 5000);
    }

    startAutoRefresh() {
        // Refresh data every 5 seconds
        this.refreshInterval = setInterval(() => {
            this.refreshData();
        }, 5000);
    }

    stopAutoRefresh() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
            this.refreshInterval = null;
        }
    }
}

// Initialize the application when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new AsyncProcessingApp();
});
