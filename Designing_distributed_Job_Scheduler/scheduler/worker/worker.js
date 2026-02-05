import Redis from 'ioredis';
import crypto from 'crypto';

export class Worker {
  constructor(workerId, redisUrl) {
    this.workerId = workerId;
    this.redis = new Redis(redisUrl);
    this.isRunning = false;
    this.currentTask = null;
  }

  async start() {
    console.log(`[Worker ${this.workerId}] Starting...`);
    this.isRunning = true;
    this.pollForTasks();
  }

  async pollForTasks() {
    while (this.isRunning) {
      try {
        // Block for 1 second waiting for a task
        const result = await this.redis.brpop('scheduler:pending', 1);
        
        if (result) {
          const [_, taskJson] = result;
          const task = JSON.parse(taskJson);
          await this.executeTask(task);
        }
      } catch (error) {
        console.error(`[Worker ${this.workerId}] Poll error:`, error.message);
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
  }

  async executeTask(task) {
    this.currentTask = task;
    console.log(`[Worker ${this.workerId}] 🔨 Executing task ${task.id}: ${task.name}`);
    
    // Publish task start event
    await this.redis.publish('scheduler:events', JSON.stringify({
      type: 'task-started',
      taskId: task.id,
      workerId: this.workerId,
      timestamp: Date.now()
    }));

    try {
      // Simulate task execution with idempotency check
      const startTime = Date.now();
      
      // Check if this execution token was already processed (idempotency)
      const alreadyProcessed = await this.redis.get(`task:executed:${task.idempotencyToken}`);
      
      if (alreadyProcessed) {
        console.log(`[Worker ${this.workerId}] ⚠️  Task ${task.id} already executed (idempotent)`);
        await this.reportCompletion(task.id, true, 'Already executed (idempotent)');
        return;
      }

      // Execute the actual task
      await this.performWork(task);
      
      // Mark this execution token as processed (TTL 1 hour)
      await this.redis.setex(`task:executed:${task.idempotencyToken}`, 3600, 'true');
      
      const duration = Date.now() - startTime;
      console.log(`[Worker ${this.workerId}] ✅ Completed task ${task.id} in ${duration}ms`);
      
      await this.reportCompletion(task.id, true, `Completed in ${duration}ms`);
    } catch (error) {
      console.error(`[Worker ${this.workerId}] ❌ Task ${task.id} failed:`, error.message);
      await this.reportCompletion(task.id, false, error.message);
    }
    
    this.currentTask = null;
  }

  async performWork(task) {
    // 3-5 seconds so RUNNING stays visible on dashboard
    const workTime = Math.random() * 2000 + 3000; // 3000-5000ms
    
    await new Promise((resolve, reject) => {
      setTimeout(() => {
        // 5% chance of random failure to demonstrate retry logic
        if (Math.random() < 0.05) {
          reject(new Error('Random task failure'));
        } else {
          resolve();
        }
      }, workTime);
    });
  }

  async reportCompletion(taskId, success, result) {
    await this.redis.publish('scheduler:events', JSON.stringify({
      type: 'task-completed',
      taskId,
      workerId: this.workerId,
      success,
      result,
      timestamp: Date.now()
    }));
  }

  stop() {
    this.isRunning = false;
    console.log(`[Worker ${this.workerId}] Stopping...`);
  }
}
