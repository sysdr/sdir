const axios = require('axios');

describe('Redundancy Patterns', () => {
    const BASE_URL = 'http://localhost:3000';
    
    beforeAll(async () => {
        // Wait for services to be ready
        await new Promise(resolve => setTimeout(resolve, 5000));
    });

    test('Load balancer distributes requests', async () => {
        const responses = [];
        
        for (let i = 0; i < 4; i++) {
            const response = await axios.get(`${BASE_URL}/api/data`);
            responses.push(response.data.serviceId);
        }
        
        // Should hit different services
        const uniqueServices = new Set(responses);
        expect(uniqueServices.size).toBeGreaterThan(1);
    });

    test('Failover works when service fails', async () => {
        // Fail a service
        await axios.post(`${BASE_URL}/api/services/3001/fail`);
        
        // Wait for health check
        await new Promise(resolve => setTimeout(resolve, 3000));
        
        // Make request - should still work
        const response = await axios.get(`${BASE_URL}/api/data`);
        expect(response.status).toBe(200);
        expect(response.data.serviceId).not.toBe('service-1');
        
        // Recover service
        await axios.post(`${BASE_URL}/api/services/3001/recover`);
    });

    test('System status reflects service health', async () => {
        const response = await axios.get(`${BASE_URL}/api/status`);
        expect(response.data.healthyCount).toBeGreaterThan(0);
        expect(response.data.totalCount).toBe(4);
        expect(response.data.services).toHaveLength(4);
    });

    test('Geographic redundancy spans multiple regions', async () => {
        const response = await axios.get(`${BASE_URL}/api/status`);
        const regions = new Set(response.data.services.map(s => s.region));
        expect(regions.size).toBeGreaterThan(1);
    });
});
