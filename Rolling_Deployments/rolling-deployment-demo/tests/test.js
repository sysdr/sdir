const axios = require('axios');

async function runTests() {
    console.log('🧪 Running Rolling Deployment Tests...');
    
    const baseUrl = 'http://localhost:8080';
    let testsPassed = 0;
    let totalTests = 0;
    
    async function test(name, testFn) {
        totalTests++;
        try {
            await testFn();
            console.log(`✅ ${name}`);
            testsPassed++;
        } catch (error) {
            console.log(`❌ ${name}: ${error.message}`);
        }
    }
    
    // Wait for services to be ready
    console.log('Waiting for services to be ready...');
    await new Promise(resolve => setTimeout(resolve, 10000));
    
    await test('Load balancer responds', async () => {
        const response = await axios.get(`${baseUrl}/api/data`);
        if (response.status !== 200) throw new Error('Load balancer not responding');
    });
    
    await test('Health status available', async () => {
        const response = await axios.get(`${baseUrl}/admin/status`);
        if (!response.data.instances || response.data.instances.length === 0) {
            throw new Error('No instances found');
        }
    });
    
    await test('Multiple requests load balance', async () => {
        const responses = [];
        for (let i = 0; i < 6; i++) {
            const response = await axios.get(`${baseUrl}/api/data`);
            responses.push(response.data.message);
        }
        
        const uniqueInstances = new Set(responses);
        if (uniqueInstances.size < 2) {
            throw new Error('Load balancing not working properly');
        }
    });
    
    await test('Rolling deployment simulation', async () => {
        const response = await axios.post(`${baseUrl}/admin/deploy`, {
            version: 'v2.0-test',
            strategy: 'rolling'
        });
        
        if (response.status !== 200) {
            throw new Error('Deployment failed to start');
        }
        
        // Wait for deployment to complete
        await new Promise(resolve => setTimeout(resolve, 20000));
        
        const status = await axios.get(`${baseUrl}/admin/status`);
        const allUpdated = status.data.instances.every(i => i.version === 'v2.0-test');
        
        if (!allUpdated) {
            throw new Error('Not all instances updated to new version');
        }
    });
    
    console.log(`\n📊 Test Results: ${testsPassed}/${totalTests} tests passed`);
    
    if (testsPassed === totalTests) {
        console.log('🎉 All tests passed!');
        process.exit(0);
    } else {
        console.log('❌ Some tests failed');
        process.exit(1);
    }
}

runTests().catch(error => {
    console.error('Test runner error:', error);
    process.exit(1);
});
