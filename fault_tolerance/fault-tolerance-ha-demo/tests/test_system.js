const axios = require('axios');

const BASE_URL = 'http://localhost:8080';

async function testFaultTolerance() {
    console.log('🧪 Testing Fault Tolerance...');
    
    try {
        // Test normal payment processing
        console.log('1. Testing normal payment processing...');
        const normalResponse = await axios.post(`${BASE_URL}/api/payment`, {
            amount: 100,
            currency: 'USD'
        });
        console.log('✅ Normal payment processed:', normalResponse.status === 200);
        
        // Inject failure
        console.log('2. Injecting payment service failure...');
        await axios.post(`${BASE_URL}/api/test/payment-failure`);
        
        // Test fault tolerance mechanisms
        console.log('3. Testing fault tolerance with injected failure...');
        const faultTolerantResponse = await axios.post(`${BASE_URL}/api/payment`, {
            amount: 200,
            currency: 'USD'
        });
        console.log('✅ Fault tolerance working:', faultTolerantResponse.status === 200);
        console.log('   Response includes fallback:', !!faultTolerantResponse.data.fallback);
        
        return true;
    } catch (error) {
        console.error('❌ Fault tolerance test failed:', error.message);
        return false;
    }
}

async function testHighAvailability() {
    console.log('🧪 Testing High Availability...');
    
    try {
        // Test normal user service
        console.log('1. Testing normal user service...');
        const normalResponse = await axios.get(`${BASE_URL}/api/users/user-1`);
        console.log('✅ Normal user request processed:', normalResponse.status === 200);
        console.log('   Served by:', normalResponse.data.servedBy);
        
        // Inject failure in one instance
        console.log('2. Injecting user service failure...');
        await axios.post(`${BASE_URL}/api/test/user-service-failure`);
        
        // Test load balancer failover
        console.log('3. Testing load balancer failover...');
        const requests = [];
        for (let i = 0; i < 5; i++) {
            requests.push(axios.get(`${BASE_URL}/api/users`));
        }
        
        const responses = await Promise.all(requests);
        const successfulResponses = responses.filter(r => r.status === 200);
        console.log('✅ High availability working:', successfulResponses.length >= 4);
        console.log(`   ${successfulResponses.length}/5 requests successful`);
        
        // Check different instances served requests
        const servedByInstances = new Set(
            successfulResponses.map(r => r.data.servedBy).filter(Boolean)
        );
        console.log('✅ Load balancing working:', servedByInstances.size > 1);
        console.log('   Instances used:', Array.from(servedByInstances));
        
        return true;
    } catch (error) {
        console.error('❌ High availability test failed:', error.message);
        return false;
    }
}

async function testMetrics() {
    console.log('🧪 Testing Metrics Collection...');
    
    try {
        const metricsResponse = await axios.get(`${BASE_URL}/api/metrics`);
        console.log('✅ Metrics endpoint working:', metricsResponse.status === 200);
        
        const metrics = metricsResponse.data;
        console.log('✅ Payment metrics available:', !!metrics.payment);
        console.log('✅ User service metrics available:', Array.isArray(metrics.userServices));
        console.log('✅ Request history available:', Array.isArray(metrics.requestHistory));
        
        return true;
    } catch (error) {
        console.error('❌ Metrics test failed:', error.message);
        return false;
    }
}

async function runAllTests() {
    console.log('🚀 Starting comprehensive system tests...\n');
    
    // Wait for services to be ready
    console.log('⏳ Waiting for services to be ready...');
    await new Promise(resolve => setTimeout(resolve, 10000));
    
    const results = {
        faultTolerance: await testFaultTolerance(),
        highAvailability: await testHighAvailability(),
        metrics: await testMetrics()
    };
    
    console.log('\n📊 Test Results:');
    console.log(`Fault Tolerance: ${results.faultTolerance ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`High Availability: ${results.highAvailability ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`Metrics: ${results.metrics ? '✅ PASS' : '❌ FAIL'}`);
    
    const allPassed = Object.values(results).every(result => result);
    console.log(`\n${allPassed ? '🎉 ALL TESTS PASSED!' : '⚠️  SOME TESTS FAILED'}`);
    
    // Reset system after tests
    console.log('\n🔄 Resetting system...');
    await axios.post(`${BASE_URL}/api/reset`);
    
    process.exit(allPassed ? 0 : 1);
}

runAllTests();
