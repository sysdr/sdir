const axios = require('axios');

const BASE_URL = 'http://localhost:3001/api';

async function testRunbookAPI() {
  console.log('🧪 Testing Runbook Management System...\n');

  try {
    // Test 1: Get all runbooks
    console.log('1. Testing GET /runbooks');
    const runbooksResponse = await axios.get(`${BASE_URL}/runbooks`);
    console.log(`✅ Found ${runbooksResponse.data.length} runbooks`);

    if (runbooksResponse.data.length > 0) {
      const firstRunbook = runbooksResponse.data[0];
      
      // Test 2: Get specific runbook
      console.log(`\n2. Testing GET /runbooks/${firstRunbook.id}`);
      const singleRunbookResponse = await axios.get(`${BASE_URL}/runbooks/${firstRunbook.id}`);
      console.log(`✅ Retrieved runbook: ${singleRunbookResponse.data.title}`);

      // Test 3: Create execution
      console.log('\n3. Testing POST /executions');
      const executionResponse = await axios.post(`${BASE_URL}/executions`, {
        runbook_id: firstRunbook.id,
        executed_by: 'Test User'
      });
      console.log(`✅ Created execution: ${executionResponse.data.id}`);

      // Test 4: Update execution
      console.log('\n4. Testing PUT /executions');
      await axios.put(`${BASE_URL}/executions/${executionResponse.data.id}`, {
        status: 'completed',
        current_step: 3,
        execution_log: 'Test execution completed successfully'
      });
      console.log('✅ Updated execution status');

      // Test 5: Get executions for runbook
      console.log('\n5. Testing GET /runbooks/:id/executions');
      const executionsResponse = await axios.get(`${BASE_URL}/runbooks/${firstRunbook.id}/executions`);
      console.log(`✅ Found ${executionsResponse.data.length} executions for runbook`);
    }

    // Test 6: Get analytics
    console.log('\n6. Testing GET /analytics');
    const analyticsResponse = await axios.get(`${BASE_URL}/analytics`);
    console.log('✅ Retrieved analytics data');
    console.log(`   - Total Runbooks: ${analyticsResponse.data.totalRunbooks[0]?.count || 0}`);
    console.log(`   - Total Executions: ${analyticsResponse.data.totalExecutions[0]?.count || 0}`);

    // Test 7: Get templates
    console.log('\n7. Testing GET /templates');
    const templatesResponse = await axios.get(`${BASE_URL}/templates`);
    console.log(`✅ Found ${templatesResponse.data.length} templates`);

    console.log('\n🎉 All tests passed successfully!');

  } catch (error) {
    console.error('❌ Test failed:', error.response?.data || error.message);
    process.exit(1);
  }
}

// Wait for server to be ready
setTimeout(testRunbookAPI, 3000);
