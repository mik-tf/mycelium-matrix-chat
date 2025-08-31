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
    },
  },
})
