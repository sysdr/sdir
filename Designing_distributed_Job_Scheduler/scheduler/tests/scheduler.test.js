import { DistributedScheduler } from '../scheduler/scheduler.js';
import Redis from 'ioredis';

const REDIS_URL = process.env.REDIS_URL || 'redis://redis:6379';

async function runTests() {
  console.log('=== Running Scheduler Tests ===\n');
  
  const redis = new Redis(REDIS_URL);
  await redis.flushall(); // Clean state
  
  let passed = 0;
  let failed = 0;
  
  // Test 1: Leader Election
  console.log('Test 1: Leader Election');
  try {
    const scheduler1 = new DistributedScheduler('test-node-1', REDIS_URL);
    const scheduler2 = new DistributedScheduler('test-node-2', REDIS_URL);
    
    await scheduler1.start();
    await scheduler2.start();
    
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    const leaderCount = (scheduler1.isLeader ? 1 : 0) + (scheduler2.isLeader ? 1 : 0);
    
    if (leaderCount === 1) {
      console.log('✅ PASS: Exactly one leader elected\n');
      passed++;
    } else {
      console.log(`❌ FAIL: Expected 1 leader, got ${leaderCount}\n`);
      failed++;
    }
  } catch (error) {
    console.log('❌ FAIL:', error.message, '\n');
    failed++;
  }
  
  // Test 2: Task Scheduling
  console.log('Test 2: Task Scheduling');
  try {
    await redis.flushall();
    const scheduler = new DistributedScheduler('test-scheduler', REDIS_URL);
    await scheduler.start();
    
    const taskId = await scheduler.scheduleTask({
      name: 'Test Task',
      payload: { test: true },
      delayMs: 5000
    });
    
    const task = scheduler.tasks.get(taskId);
    
    if (task && task.state === 'SCHEDULED') {
      console.log('✅ PASS: Task scheduled successfully\n');
      passed++;
    } else {
      console.log('❌ FAIL: Task not in SCHEDULED state\n');
      failed++;
    }
  } catch (error) {
    console.log('❌ FAIL:', error.message, '\n');
    failed++;
  }
  
  // Test 3: Idempotency Token Generation
  console.log('Test 3: Idempotency Token');
  try {
    await redis.flushall();
    const scheduler = new DistributedScheduler('test-scheduler', REDIS_URL);
    await scheduler.start();
    
    const taskId = await scheduler.scheduleTask({
      name: 'Idempotency Test',
      payload: { test: true }
    });
    
    const task = scheduler.tasks.get(taskId);
    
    if (task.idempotencyToken && task.idempotencyToken.length > 0) {
      console.log('✅ PASS: Idempotency token generated\n');
      passed++;
    } else {
      console.log('❌ FAIL: No idempotency token\n');
      failed++;
    }
  } catch (error) {
    console.log('❌ FAIL:', error.message, '\n');
    failed++;
  }
  
  // Test 4: Recurring Task
  console.log('Test 4: Recurring Task');
  try {
    await redis.flushall();
    const scheduler = new DistributedScheduler('test-scheduler', REDIS_URL);
    await scheduler.start();
    
    const taskId = await scheduler.scheduleTask({
      name: 'Recurring Test',
      payload: { test: true },
      recurring: true,
      intervalMs: 10000
    });
    
    const task = scheduler.tasks.get(taskId);
    
    if (task.recurring && task.intervalMs === 10000) {
      console.log('✅ PASS: Recurring task configured correctly\n');
      passed++;
    } else {
      console.log('❌ FAIL: Recurring task not configured\n');
      failed++;
    }
  } catch (error) {
    console.log('❌ FAIL:', error.message, '\n');
    failed++;
  }
  
  // Test 5: Task State Persistence
  console.log('Test 5: Task State Persistence');
  try {
    await redis.flushall();
    const scheduler = new DistributedScheduler('test-scheduler', REDIS_URL);
    await scheduler.start();
    
    const taskId = await scheduler.scheduleTask({
      name: 'Persistence Test',
      payload: { test: true }
    });
    
    const storedTask = await redis.hget('scheduler:tasks', taskId);
    const parsed = JSON.parse(storedTask);
    
    if (parsed && parsed.id === taskId) {
      console.log('✅ PASS: Task persisted to Redis\n');
      passed++;
    } else {
      console.log('❌ FAIL: Task not persisted\n');
      failed++;
    }
  } catch (error) {
    console.log('❌ FAIL:', error.message, '\n');
    failed++;
  }
  
  console.log('=== Test Summary ===');
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  console.log(`Total: ${passed + failed}`);
  
  await redis.quit();
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(console.error);
