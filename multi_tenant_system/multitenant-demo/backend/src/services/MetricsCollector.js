class MetricsCollector {
    constructor() {
        this.metrics = {
            requests_per_tenant: new Map(),
            users_created_per_tenant: new Map(),
            orders_created_per_tenant: new Map(),
            response_times: new Map()
        };
    }

    recordUserCreated(tenantId) {
        const current = this.metrics.users_created_per_tenant.get(tenantId) || 0;
        this.metrics.users_created_per_tenant.set(tenantId, current + 1);
    }

    recordOrderCreated(tenantId) {
        const current = this.metrics.orders_created_per_tenant.get(tenantId) || 0;
        this.metrics.orders_created_per_tenant.set(tenantId, current + 1);
    }

    recordRequest(tenantId, responseTime) {
        const current = this.metrics.requests_per_tenant.get(tenantId) || 0;
        this.metrics.requests_per_tenant.set(tenantId, current + 1);
        
        if (!this.metrics.response_times.has(tenantId)) {
            this.metrics.response_times.set(tenantId, []);
        }
        this.metrics.response_times.get(tenantId).push(responseTime);
    }

    async getAllMetrics() {
        return {
            requests_per_tenant: Object.fromEntries(this.metrics.requests_per_tenant),
            users_created_per_tenant: Object.fromEntries(this.metrics.users_created_per_tenant),
            orders_created_per_tenant: Object.fromEntries(this.metrics.orders_created_per_tenant),
            avg_response_times: this.calculateAverageResponseTimes()
        };
    }

    calculateAverageResponseTimes() {
        const averages = {};
        for (const [tenantId, times] of this.metrics.response_times.entries()) {
            if (times.length > 0) {
                averages[tenantId] = times.reduce((a, b) => a + b, 0) / times.length;
            }
        }
        return averages;
    }
}

module.exports = { MetricsCollector };
