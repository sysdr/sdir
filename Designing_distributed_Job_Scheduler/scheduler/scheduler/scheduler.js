import Redis from 'ioredis';
import { EventEmitter } from 'events';
import crypto from 'crypto';

const TIMING_WHEEL_SLOTS = 60; // 60 seconds
const SLOT_DURATION_MS = 1000; // 1 second per slot
const LEASE_TIMEOUT_MS = 30000; // 30 seconds
const LEADER_TTL_MS = 5000; // Leader lease 5 seconds

export class DistributedScheduler extends EventEmitter {
  constructor(nodeId, redisUrl) {
    super();
    this.nodeId = nodeId;
    this.redis = new Redis(redisUrl);
    this.isLeader = false;
    this.timingWheel = new Array(TIMING_WHEEL_SLOTS).fill(null).map(() => []);
    this.currentSlot = 0;
    this.tasks = new Map(); // taskId -> task metadata
    this.runningTasks = new Map(); // taskId -> lease info
  }

  async start() {
    console.log(`[${this.nodeId}] Starting scheduler...`);
    
    // Start leader election
    this.startLeaderElection();
    
    // Start timing wheel ticker
    this.startTimingWheel();
    
    // Start lease monitoring
    this.startLeaseMonitoring();
    
    // Load existing tasks from Redis
    await this.loadTasks();
  }

  async startLeaderElection() {
    const tryBecomeLeader = async () => {
      try {
        // Try to set leader key with NX (only if not exists) and PX (expiration)
        const result = await this.redis.set(
          'scheduler:leader',
          this.nodeId,
          'PX',
          LEADER_TTL_MS,
          'NX'
        );

        if (result === 'OK') {
          if (!this.isLeader) {
            console.log(`[${this.nodeId}] 🎯 Became LEADER`);
            this.isLeader = true;
            this.emit('leader-elected', this.nodeId);
          }
          
          // Extend leadership
          setTimeout(async () => {
            if (this.isLeader) {
              await this.redis.set('scheduler:leader', this.nodeId, 'PX', LEADER_TTL_MS);
            }
          }, LEADER_TTL_MS / 2);
        } else {
          // Check if we lost leadership
          const currentLeader = await this.redis.get('scheduler:leader');
          if (this.isLeader && currentLeader !== this.nodeId) {
            console.log(`[${this.nodeId}] ❌ Lost leadership to ${currentLeader}`);
            this.isLeader = false;
            this.emit('leader-lost', currentLeader);
          }
        }
      } catch (error) {
        console.error(`[${this.nodeId}] Leader election error:`, error.message);
      }
    };

    // Try to become leader immediately and then every 2 seconds
    tryBecomeLeader();
    setInterval(tryBecomeLeader, 2000);
  }

  startTimingWheel() {
    setInterval(() => {
      if (!this.isLeader) return;

      const now = Date.now();
      this.currentSlot = Math.floor((now / SLOT_DURATION_MS) % TIMING_WHEEL_SLOTS);
      
      // Process tasks in current slot
      const tasksToExecute = this.timingWheel[this.currentSlot];
      this.timingWheel[this.currentSlot] = []; // Clear slot

      for (const taskId of tasksToExecute) {
        this.moveTaskToPending(taskId);
      }

      // Advance tasks from backing store to timing wheel
      this.advanceBackingStore(now);
    }, SLOT_DURATION_MS);
  }

  async moveTaskToPending(taskId) {
    const task = this.tasks.get(taskId);
    if (!task) return;

    console.log(`[${this.nodeId}] Moving task ${taskId} to PENDING`);
    task.state = 'PENDING';
    task.pendingAt = Date.now();
    
    await this.redis.lpush('scheduler:pending', JSON.stringify(task));
    await this.redis.hset('scheduler:tasks', taskId, JSON.stringify(task));
    
    this.emit('task-pending', task);
  }

  async advanceBackingStore(now) {
    // Move tasks from backing store to timing wheel if execution time is near
    const windowEnd = now + (TIMING_WHEEL_SLOTS * SLOT_DURATION_MS);
    
    for (const [taskId, task] of this.tasks.entries()) {
      if (task.state === 'SCHEDULED' && task.executeAt <= windowEnd) {
        const slotIndex = Math.floor((task.executeAt / SLOT_DURATION_MS) % TIMING_WHEEL_SLOTS);
        this.timingWheel[slotIndex].push(taskId);
        console.log(`[${this.nodeId}] Advanced task ${taskId} to slot ${slotIndex}`);
      }
    }
  }

  startLeaseMonitoring() {
    setInterval(() => {
      const now = Date.now();
      
      for (const [taskId, lease] of this.runningTasks.entries()) {
        if (now - lease.startTime > LEASE_TIMEOUT_MS) {
          console.log(`[${this.nodeId}] ⏰ Lease timeout for task ${taskId}, reassigning...`);
          this.handleLeaseTimeout(taskId);
        }
      }
    }, 5000);
  }

  async handleLeaseTimeout(taskId) {
    const task = this.tasks.get(taskId);
    if (!task) return;

    this.runningTasks.delete(taskId);
    task.state = 'PENDING';
    task.retryCount = (task.retryCount || 0) + 1;
    
    if (task.retryCount > 3) {
      task.state = 'FAILED';
      console.log(`[${this.nodeId}] ❌ Task ${taskId} failed after 3 retries`);
      this.emit('task-failed', task);
    } else {
      await this.redis.lpush('scheduler:pending', JSON.stringify(task));
      console.log(`[${this.nodeId}] 🔄 Retry ${task.retryCount} for task ${taskId}`);
    }
    
    await this.redis.hset('scheduler:tasks', taskId, JSON.stringify(task));
    this.emit('task-reassigned', task);
  }

  async scheduleTask(task) {
    const taskId = crypto.randomUUID();
    const executeAt = Date.now() + (task.delayMs || 0);
    
    const scheduledTask = {
      id: taskId,
      name: task.name,
      payload: task.payload,
      executeAt,
      state: 'SCHEDULED',
      createdAt: Date.now(),
      recurring: task.recurring || false,
      intervalMs: task.intervalMs || 0,
      idempotencyToken: crypto.randomUUID(),
      retryCount: 0
    };

    this.tasks.set(taskId, scheduledTask);
    await this.redis.hset('scheduler:tasks', taskId, JSON.stringify(scheduledTask));
    
    console.log(`[${this.nodeId}] ✅ Scheduled task ${taskId} for ${new Date(executeAt).toISOString()}`);
    this.emit('task-scheduled', scheduledTask);
    
    return taskId;
  }

  async loadTasks() {
    const tasksData = await this.redis.hgetall('scheduler:tasks');
    
    for (const [taskId, taskJson] of Object.entries(tasksData)) {
      const task = JSON.parse(taskJson);
      this.tasks.set(taskId, task);
      
      if (task.state === 'SCHEDULED') {
        const now = Date.now();
        const windowEnd = now + (TIMING_WHEEL_SLOTS * SLOT_DURATION_MS);
        
        if (task.executeAt <= windowEnd) {
          const slotIndex = Math.floor((task.executeAt / SLOT_DURATION_MS) % TIMING_WHEEL_SLOTS);
          this.timingWheel[slotIndex].push(taskId);
        }
      }
    }
    
    console.log(`[${this.nodeId}] Loaded ${this.tasks.size} tasks from storage`);
  }

  async markTaskRunning(taskId, workerId) {
    const task = this.tasks.get(taskId);
    if (!task) return null;

    task.state = 'RUNNING';
    task.workerId = workerId;
    const lease = {
      taskId,
      workerId,
      startTime: Date.now()
    };
    
    this.runningTasks.set(taskId, lease);
    await this.redis.hset('scheduler:tasks', taskId, JSON.stringify(task));
    
    this.emit('task-running', task);
    return lease;
  }

  async markTaskCompleted(taskId, success, result) {
    const task = this.tasks.get(taskId);
    if (!task) return;

    this.runningTasks.delete(taskId);
    
    if (success) {
      if (task.recurring) {
        // Reschedule recurring task
        task.executeAt = Date.now() + task.intervalMs;
        task.state = 'SCHEDULED';
        task.lastRun = Date.now();
        task.runCount = (task.runCount || 0) + 1;
        task.idempotencyToken = crypto.randomUUID();
        
        console.log(`[${this.nodeId}] 🔄 Rescheduled recurring task ${taskId}`);
        this.emit('task-rescheduled', task);
      } else {
        task.state = 'COMPLETED';
        task.completedAt = Date.now();
        console.log(`[${this.nodeId}] ✅ Task ${taskId} completed`);
        this.emit('task-completed', task);
      }
    } else {
      task.state = 'FAILED';
      task.error = result;
      console.log(`[${this.nodeId}] ❌ Task ${taskId} failed: ${result}`);
      this.emit('task-failed', task);
    }
    
    await this.redis.hset('scheduler:tasks', taskId, JSON.stringify(task));
  }

  getStats() {
    const stats = {
      nodeId: this.nodeId,
      isLeader: this.isLeader,
      totalTasks: this.tasks.size,
      runningTasks: this.runningTasks.size,
      currentSlot: this.currentSlot,
      tasksByState: {}
    };

    for (const task of this.tasks.values()) {
      stats.tasksByState[task.state] = (stats.tasksByState[task.state] || 0) + 1;
    }

    return stats;
  }
}
