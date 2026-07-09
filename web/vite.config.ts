import vue from '@vitejs/plugin-vue'
import { ui, defineTheme } from '@sil/ui/vite'
import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'

export default defineConfig({
  plugins: [
    vue(),
    ui({
      theme: defineTheme({
        colors: {
          dark: '#0f1117',
          light: '#f8f9fb',
          primary: '#155e75',
          secondary: '#3e9b5f',
          'accent-light': '#f8f9fb',
          'accent-dark': '#111827',
        },
        fonts: {
          body: '"Inter", -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif',
        },
        variables: {
          '--border-radius': '0.5rem',
        },
      }),
    }),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  css: {
    preprocessorOptions: {
      scss: {
        additionalData: `@use "@/styles/_mixins" as *;`,
      },
    },
  },
  server: {
    host: '0.0.0.0',
    port: 4000,
  },
  preview: {
    host: '0.0.0.0',
    port: 4000,
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})