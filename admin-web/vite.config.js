import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  base: './',
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://192.227.212.20:18900',
        changeOrigin: true,
      },
      '/admin': {
        target: 'http://192.227.212.20:18900',
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: '../server/app/static/admin-web',
    emptyOutDir: true,
  },
})
