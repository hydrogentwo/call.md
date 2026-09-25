import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.videodb.callmd',
  appName: 'Call.md',
  webDir: 'dist/renderer',
  server: {
    // In dev, Capacitor will load from Vite dev server
    // In prod, it loads from webDir
    androidScheme: 'https',
  },
  android: {
    // Allow mixed content if we need to hit http:// localhost during dev
    allowMixedContent: true,
    // Use the bundled WebView
    webContentsDebuggingEnabled: true,
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 1500,
      backgroundColor: '#000000',
      showSpinner: false,
    },
    StatusBar: {
      style: 'DARK',
      backgroundColor: '#000000',
    },
    // Preferences and Filesystem are used for config / recordings on Android
    // instead of Electron's app.getPath('userData') + better-sqlite3
  },
};

export default config;
