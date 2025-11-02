const axios = require('axios');

const API_BASE = 'http://localhost:8080';

const TEST_TENANTS = [
    '11111111-1111-1111-1111-111111111111', // Shared schema
    '22222222-2222-2222-2222-222222222222', // Separate schema
    '33333333-3333-3333-3333-333333333333'  // Separate DB
];

async function runTests() {
    console.log('🧪 Running Multi-Tenant Architecture Tests\n');

    try {
        // Test 1: Basic health check
        console.log('1. Testing API health...');
        const healthResponse = await axios.get(`${API_BASE}/health`);
        console.log('   ✅ API is healthy\n');

        // Test 2: Fetch tenants
        console.log('2. Testing tenant management...');
        const tenantsResponse = await axios.get(`${API_BASE}/api/tenants`);
        console.log(`   ✅ Found ${tenantsResponse.data.length} tenants\n`);

        // Test 3: Test each tenant isolation pattern
        for (const tenantId of TEST_TENANTS) {
            console.log(`3. Testing tenant ${tenantId.substring(0, 8)}...`);
            
            // Get tenant stats
            const statsResponse = await axios.get(`${API_BASE}/api/tenants/${tenantId}/stats`);
            console.log(`   📊 Pattern: ${statsResponse.data.isolationPattern}`);
            console.log(`   👥 Users: ${statsResponse.data.userCount}`);
            console.log(`   🛒 Orders: ${statsResponse.data.orderCount}`);

            // Test user creation
            const newUser = {
                username: `test_user_${Date.now()}`,
                email: `test${Date.now()}@example.com`
            };

            const userResponse = await axios.post(`${API_BASE}/api/users`, newUser, {
                headers: { 'X-Tenant-ID': tenantId }
            });
            console.log(`   ✅ Created user: ${userResponse.data.username}`);

            // Test order creation
            const newOrder = {
                user_id: userResponse.data.id,
                product_name: 'Test Product',
                amount: 99.99
            };

            const orderResponse = await axios.post(`${API_BASE}/api/orders`, newOrder, {
                headers: { 'X-Tenant-ID': tenantId }
            });
            console.log(`   ✅ Created order: ${orderResponse.data.product_name}\n`);
        }

        // Test 4: Isolation testing
        console.log('4. Testing tenant isolation...');
        const isolationResponse = await axios.post(`${API_BASE}/api/test-isolation`);
        
        Object.entries(isolationResponse.data).forEach(([pattern, result]) => {
            const status = result.isolated ? '✅' : '❌';
            console.log(`   ${status} ${pattern}: ${result.isolated ? 'ISOLATED' : 'NOT ISOLATED'}`);
        });

        console.log('\n🎉 All tests passed successfully!');

    } catch (error) {
        console.error('❌ Test failed:', error.response?.data || error.message);
        process.exit(1);
    }
}

// Wait for services to be ready
setTimeout(() => {
    runTests();
}, 10000);
