import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 5173,
    proxy: { '/api': 'http://backend:3001', '/ws': { target: 'ws://backend:3001', ws: true } },
    hmr: {
      clientPort: 4210,
      host: 'localhost',
      protocol: 'ws'
    }
  }
});
