const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

class DegradationTester {
    constructor() {
        this.testResults = [];
    }

    async runTest(name, testFn) {
        console.log(`\n🧪 Running test: ${name}`);
        try {
            const startTime = Date.now();
            const result = await testFn();
            const duration = Date.now() - startTime;
            
            this.testResults.push({
                name,
                status: 'PASSED',
                duration,
                result
            });
            
            console.log(`✅ ${name} - PASSED (${duration}ms)`);
        } catch (error) {
            this.testResults.push({
                name,
                status: 'FAILED',
                error: error.message
            });
            
            console.log(`❌ ${name} - FAILED: ${error.message}`);
        }
    }

    async testNormalOperation() {
        // Test normal product listing
        const products = await axios.get(`${BASE_URL}/api/products`);
        if (products.data.source !== 'live') {
            throw new Error('Expected live data source');
        }

        // Test normal checkout
        const checkout = await axios.post(`${BASE_URL}/api/checkout`, {
            productId: 1,
            quantity: 1,
            userId: 'test-user',
            paymentInfo: { amount: 999, cardType: 'credit' }
        });
        
        if (checkout.data.degradationMode) {
            throw new Error('Expected normal operation without degradation');
        }

        return { productCount: products.data.products.length, orderId: checkout.data.orderId };
    }

    async testCircuitBreakerActivation() {
        // Degrade product service to down
        await axios.post(`${BASE_URL}/control/degrade/product/3`);
        
        // Wait for circuit breaker to open (may take a few requests)
        for (let i = 0; i < 5; i++) {
            try {
                await axios.get(`${BASE_URL}/api/products`);
            } catch (error) {
                // Expected to fail
            }
        }

        // Should now get fallback data
        const response = await axios.get(`${BASE_URL}/api/products`);
        if (response.data.source !== 'fallback') {
            throw new Error('Expected fallback data source');
        }

        // Reset service
        await axios.post(`${BASE_URL}/control/degrade/product/0`);
        
        return { fallbackProducts: response.data.products.length };
    }

    async testGracefulCheckoutDegradation() {
        // Degrade payment service
        await axios.post(`${BASE_URL}/control/degrade/payment/2`);
        
        const checkout = await axios.post(`${BASE_URL}/api/checkout`, {
            productId: 1,
            quantity: 1,
            userId: 'test-user',
            paymentInfo: { amount: 999, cardType: 'credit' }
        });

        if (!checkout.data.degradationMode) {
            throw new Error('Expected degradation mode to be active');
        }

        if (checkout.data.fallbacks.length === 0) {
            throw new Error('Expected fallback strategies to be used');
        }

        // Reset service
        await axios.post(`${BASE_URL}/control/degrade/payment/0`);
        
        return { 
            orderId: checkout.data.orderId,
            fallbacks: checkout.data.fallbacks.length
        };
    }

    async testLoadShedding() {
        // Set high system load
        await axios.post(`${BASE_URL}/control/load/90`);
        
        // Make multiple requests
        const requests = [];
        for (let i = 0; i < 10; i++) {
            requests.push(axios.get(`${BASE_URL}/api/products`));
        }
        
        const responses = await Promise.all(requests);
        const cachedResponses = responses.filter(r => 
            r.data.source === 'cached' || r.data.source === 'fallback'
        );
        
        if (cachedResponses.length === 0) {
            throw new Error('Expected some requests to use cached/fallback data under high load');
        }

        // Reset load
        await axios.post(`${BASE_URL}/control/load/0`);
        
        return { 
            totalRequests: responses.length,
            cachedResponses: cachedResponses.length
        };
    }

    async testServiceRecovery() {
        // Degrade service
        await axios.post(`${BASE_URL}/control/degrade/product/3`);
        
        // Wait for degradation
        await new Promise(resolve => setTimeout(resolve, 1000));
        
        // Restore service
        await axios.post(`${BASE_URL}/control/degrade/product/0`);
        
        // Wait for recovery
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        // Test should now work normally
        const response = await axios.get(`${BASE_URL}/api/products`);
        if (response.data.source !== 'live') {
            throw new Error('Service did not recover to live data');
        }
        
        return { recovered: true };
    }

    async runAllTests() {
        console.log('🚀 Starting Graceful Degradation Tests\n');
        
        await this.runTest('Normal Operation', () => this.testNormalOperation());
        await this.runTest('Circuit Breaker Activation', () => this.testCircuitBreakerActivation());
        await this.runTest('Graceful Checkout Degradation', () => this.testGracefulCheckoutDegradation());
        await this.runTest('Load Shedding', () => this.testLoadShedding());
        await this.runTest('Service Recovery', () => this.testServiceRecovery());
        
        console.log('\n📊 Test Summary:');
        console.log('================');
        
        const passed = this.testResults.filter(t => t.status === 'PASSED').length;
        const failed = this.testResults.filter(t => t.status === 'FAILED').length;
        
        console.log(`Total Tests: ${this.testResults.length}`);
        console.log(`Passed: ${passed}`);
        console.log(`Failed: ${failed}`);
        
        if (failed === 0) {
            console.log('\n🎉 All tests passed! Graceful degradation is working correctly.');
        } else {
            console.log('\n⚠️  Some tests failed. Check the output above for details.');
            process.exit(1);
        }
    }
}

// Wait for services to be ready
async function waitForServices() {
    console.log('⏳ Waiting for services to be ready...');
    
    for (let i = 0; i < 30; i++) {
        try {
            await axios.get(`${BASE_URL}/health`, { timeout: 2000 });
            console.log('✅ Services are ready!');
            return;
        } catch (error) {
            await new Promise(resolve => setTimeout(resolve, 1000));
        }
    }
    
    throw new Error('Services did not become ready in time');
}

// Run tests
if (require.main === module) {
    (async () => {
        try {
            await waitForServices();
            const tester = new DegradationTester();
            await tester.runAllTests();
        } catch (error) {
            console.error('Test suite failed:', error.message);
            process.exit(1);
        }
    })();
}

module.exports = DegradationTester;
