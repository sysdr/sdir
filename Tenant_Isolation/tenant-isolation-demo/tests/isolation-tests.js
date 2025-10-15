const axios = require('axios');

const API_BASE = 'http://localhost:3001';
const TENANTS = {
  'acme': 'acme-key-123',
  'startup': 'startup-key-456',
  'enterprise': 'enterprise-key-789'
};

async function testDataIsolation() {
  console.log('🔒 Testing Data Isolation...');
  
  try {
    // Create tasks for different tenants
    const acmeTask = await axios.post(`${API_BASE}/api/tasks`, {
      title: 'ACME Secret Task',
      description: 'Confidential ACME business'
    }, {
      headers: { 'X-API-Key': TENANTS.acme }
    });

    const startupTask = await axios.post(`${API_BASE}/api/tasks`, {
      title: 'Startup Innovation',
      description: 'Top secret startup idea'
    }, {
      headers: { 'X-API-Key': TENANTS.startup }
    });

    // Verify ACME can't see Startup tasks
    const acmeTasks = await axios.get(`${API_BASE}/api/tasks`, {
      headers: { 'X-API-Key': TENANTS.acme }
    });

    const startupTasks = await axios.get(`${API_BASE}/api/tasks`, {
      headers: { 'X-API-Key': TENANTS.startup }
    });

    // Check isolation
    const acmeCanSeeStartup = acmeTasks.data.some(task => task.title === 'Startup Innovation');
    const startupCanSeeAcme = startupTasks.data.some(task => task.title === 'ACME Secret Task');

    if (!acmeCanSeeStartup && !startupCanSeeAcme) {
      console.log('✅ Data Isolation: PASSED - Tenants cannot see each other\'s data');
      return true;
    } else {
      console.log('❌ Data Isolation: FAILED - Cross-tenant data leak detected');
      return false;
    }
  } catch (error) {
    console.log('❌ Data Isolation: ERROR -', error.message);
    return false;
  }
}

async function testRateLimiting() {
  console.log('⚡ Testing Rate Limiting...');
  
  try {
    // Test startup tenant with lower rate limit
    const requests = [];
    for (let i = 0; i < 55; i++) {
      requests.push(
        axios.get(`${API_BASE}/api/metrics`, {
          headers: { 'X-API-Key': TENANTS.startup }
        }).catch(err => err.response)
      );
    }

    const responses = await Promise.all(requests);
    const rateLimited = responses.some(res => res && res.status === 429);

    if (rateLimited) {
      console.log('✅ Rate Limiting: PASSED - Tenant hit rate limit as expected');
      return true;
    } else {
      console.log('❌ Rate Limiting: FAILED - Rate limit not enforced');
      return false;
    }
  } catch (error) {
    console.log('❌ Rate Limiting: ERROR -', error.message);
    return false;
  }
}

async function testResourceIsolation() {
  console.log('🏗️ Testing Resource Isolation...');
  
  try {
    // Test that each tenant gets isolated metrics
    const acmeMetrics = await axios.get(`${API_BASE}/api/metrics`, {
      headers: { 'X-API-Key': TENANTS.acme }
    });

    const startupMetrics = await axios.get(`${API_BASE}/api/metrics`, {
      headers: { 'X-API-Key': TENANTS.startup }
    });

    // Verify tenants have different metrics
    const differentTenantIds = acmeMetrics.data.tenant_id !== startupMetrics.data.tenant_id;
    const differentRateLimits = acmeMetrics.data.rate_limit !== startupMetrics.data.rate_limit;

    if (differentTenantIds && differentRateLimits) {
      console.log('✅ Resource Isolation: PASSED - Tenants have isolated resource metrics');
      return true;
    } else {
      console.log('❌ Resource Isolation: FAILED - Resource metrics not properly isolated');
      return false;
    }
  } catch (error) {
    console.log('❌ Resource Isolation: ERROR -', error.message);
    return false;
  }
}

async function testSecurityIsolation() {
  console.log('🔐 Testing Security Isolation...');
  
  try {
    // Test invalid API key
    try {
      await axios.get(`${API_BASE}/api/tasks`, {
        headers: { 'X-API-Key': 'invalid-key' }
      });
      console.log('❌ Security Isolation: FAILED - Invalid API key accepted');
      return false;
    } catch (error) {
      if (error.response && error.response.status === 401) {
        console.log('✅ Security Isolation: PASSED - Invalid API key rejected');
        return true;
      } else {
        console.log('❌ Security Isolation: FAILED - Unexpected error');
        return false;
      }
    }
  } catch (error) {
    console.log('❌ Security Isolation: ERROR -', error.message);
    return false;
  }
}

async function runAllTests() {
  console.log('🧪 Running Tenant Isolation Tests...\n');
  
  // Wait for services to be ready
  console.log('⏳ Waiting for services to be ready...');
  await new Promise(resolve => setTimeout(resolve, 5000));
  
  const results = await Promise.all([
    testDataIsolation(),
    testRateLimiting(),
    testResourceIsolation(),
    testSecurityIsolation()
  ]);

  const passed = results.filter(r => r).length;
  const total = results.length;

  console.log(`\n📊 Test Results: ${passed}/${total} tests passed`);
  
  if (passed === total) {
    console.log('🎉 All isolation tests passed! Tenant isolation is working correctly.');
    process.exit(0);
  } else {
    console.log('🚨 Some tests failed. Please check the isolation implementation.');
    process.exit(1);
  }
}

module.exports = { runAllTests };

if (require.main === module) {
  runAllTests();
}
