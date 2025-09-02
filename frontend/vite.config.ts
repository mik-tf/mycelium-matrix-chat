import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/_matrix': {
        target: 'http://localhost:8080',
        changeOrigin: true,
        rewrite: (path) => path, // Don't rewrite, let the gateway handle it
      },
      '/api/mycelium': {
        target: 'http://localhost:8989',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api\/mycelium/, ''),
        configure: (proxy, options) => {
          proxy.on('error', (err, req, res) => {
            console.log('proxy error', err);
          });
          proxy.on('proxyReq', (proxyReq, req, res) => {
            console.log('Sending Request to Mycelium:', req.method, req.url);
          });
          proxy.on('proxyRes', (proxyRes, req, res) => {
            console.log('Received Response from Mycelium:', proxyRes.statusCode, req.url);
          });
        },
      },
    },
  },
})
