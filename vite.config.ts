import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

const isCapacitorBuild = process.env.CAPACITOR === '1' || process.env.ANDROID === '1';

export default defineConfig({
  plugins: [react()],
  root: 'src/renderer',
  // Capacitor loads from capacitor:// or https:// — needs relative base.
  // For native we ensure `./` so asset URLs resolve inside the APK.
  base: './',
  build: {
    outDir: '../../dist/renderer',
    emptyOutDir: true,
    sourcemap: true,
    // On Android we only need the main entry (widget.html is Electron-only)
    rollupOptions: isCapacitorBuild
      ? {
          input: { main: path.resolve(__dirname, 'src/renderer/index.html') },
        }
      : {
          input: {
            main: path.resolve(__dirname, 'src/renderer/index.html'),
            widget: path.resolve(__dirname, 'src/renderer/widget.html'),
          },
        },
  },
  resolve: {
    alias: {
      '@shared': path.resolve(__dirname, 'src/shared'),
      '@renderer': path.resolve(__dirname, 'src/renderer'),
    },
  },
  server: {
    port: 51730,
    strictPort: false,  // Will find next available port if busy
    // Ensure all HTML files are accessible
    fs: {
      allow: ['..'],
    },
  },
  // Ensure widget.html is accessible in dev mode
  appType: 'mpa',
});
