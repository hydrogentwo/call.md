import React, { useState, useEffect } from 'react';
import ReactDOM from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { trpc, createTrpcClient, getApiPort } from './api/trpc';
import { useConfigStore } from './stores/config.store';
import { App } from './App';
import './styles/globals.css';
import { isAndroid } from './lib/platform';
import { installAndroidBridge } from './lib/android-bridge';

// On Android (Capacitor WebView) there is no Electron main — install the shim
// before React mounts so hooks like usePermissions / useConfigStore see it.
installAndroidBridge();

// Capacitor StatusBar / SplashScreen — no-ops on desktop, nice on Android
async function initCapacitorPlugins(): Promise<void> {
  if (!isAndroid()) return;
  try {
    const { StatusBar, Style } = await import('@capacitor/status-bar');
    await StatusBar.setOverlaysWebView({ overlay: true });
    await StatusBar.setStyle({ style: Style.Dark });
    const { SplashScreen } = await import('@capacitor/splash-screen');
    await SplashScreen.hide();
    const { App: CapApp } = await import('@capacitor/app');
    CapApp.addListener('backButton', ({ canGoBack }) => {
      if (!canGoBack) CapApp.exitApp();
      else window.history.back();
    });
  } catch {
    // plugins not installed yet (web dev) — ignore
  }
}
void initCapacitorPlugins();

function TrpcProvider({ children, port }: { children: React.ReactNode; port: number }) {
  const configStore = useConfigStore();

  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 5000,
            refetchOnWindowFocus: false,
          },
        },
      })
  );

  const [trpcClient] = useState(() =>
    createTrpcClient(() => useConfigStore.getState().accessToken, port)
  );

  return (
    <trpc.Provider client={trpcClient} queryClient={queryClient}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </trpc.Provider>
  );
}

function Root() {
  const [port, setPort] = useState<number | null>(null);

  useEffect(() => {
    getApiPort().then(setPort);
  }, []);

  if (port === null) {
    return (
      <div className="flex h-screen items-center justify-center bg-background">
        <p className="text-muted-foreground">Connecting...</p>
      </div>
    );
  }

  return (
    <TrpcProvider port={port}>
      <App />
    </TrpcProvider>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root')!);

root.render(
  <React.StrictMode>
    <Root />
  </React.StrictMode>
);
