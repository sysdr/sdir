const express = require('express');
const app = express();

app.use(express.json());

const nodeId = process.env.NODE_ID || 'edge-unknown';
const region = process.env.REGION || 'unknown';

// Simulated Wasm execution
class WasmRuntime {
  constructor() {
    this.modules = new Map();
    this.executions = 0;
  }

  loadModule(name, code) {
    this.modules.set(name, {
      code,
      size: code.length,
      loadedAt: Date.now()
    });
  }

  async execute(moduleName, input) {
    this.executions++;
    const startTime = Date.now();
    
    // Simulate Wasm execution (ultra-fast)
    await new Promise(resolve => setTimeout(resolve, Math.random() * 5 + 1));
    
    const executionTime = Date.now() - startTime;
    
    return {
      nodeId,
      region,
      moduleName,
      executionTime,
      result: `Processed: ${JSON.stringify(input)}`,
      wasmOverhead: executionTime < 10 ? 'microseconds' : 'milliseconds'
    };
  }

  getStats() {
    return {
      totalModules: this.modules.size,
      totalExecutions: this.executions,
      modules: Array.from(this.modules.entries()).map(([name, mod]) => ({
        name,
        size: mod.size,
        sizeKB: (mod.size / 1024).toFixed(2)
      }))
    };
  }
}

const runtime = new WasmRuntime();

// Load sample Wasm modules
runtime.loadModule('data-processor', 'wasm-binary-code-simulation-12kb');
runtime.loadModule('auth-validator', 'wasm-binary-code-simulation-8kb');
runtime.loadModule('image-resizer', 'wasm-binary-code-simulation-45kb');

app.post('/execute', async (req, res) => {
  const { module, input } = req.body;
  const result = await runtime.execute(module, input);
  res.json(result);
});

app.get('/stats', (req, res) => {
  res.json({
    nodeId,
    region,
    runtime: runtime.getStats(),
    uptime: process.uptime()
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', nodeId, region });
});

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => {
  console.log(`⚡ Edge Node ${nodeId} running on port ${PORT}`);
});
