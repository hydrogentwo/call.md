import { createTRPCReact } from '@trpc/react-query';
import { httpBatchLink } from '@trpc/client';
import type { AppRouter } from '../../main/server/trpc/router';

export const trpc = createTRPCReact<AppRouter>();

const DEFAULT_API_PORT = 51731;
let cachedPort: number | null = null;

function isAndroidBridge(): boolean {
  try {
    const cap: any = (typeof window !== 'undefined' ? (window as any).Capacitor : null);
    if (cap?.isNativePlatform?.() && cap.getPlatform() === 'android') return true;
  } catch {}
  return false;
}

async function getApiPort(): Promise<number> {
  if (isAndroidBridge()) {
    cachedPort = 0;
    return 0;
  }
  if (cachedPort !== null) return cachedPort;

  try {
    const api: any = (window as any).electronAPI;
    if (api?.app?.getServerPort) {
      cachedPort = await api.app.getServerPort();
      return cachedPort as number;
    }
  } catch {
    // Fallback to default
  }
  return DEFAULT_API_PORT;
}

export function createTrpcClient(getAccessToken: () => string | null, port?: number) {
  const apiPort = port ?? cachedPort ?? DEFAULT_API_PORT;

  // Android: no localhost server — if a remote URL is configured, proxy there;
  // otherwise the app uses the in-memory Android mock (Preferences + IndexedDB).
  // The httpBatchLink will 404 fast on 0, but queries are guarded in hooks
  // to use android storage instead. Keep link for forward compat with remote.
  const effectivePort = isAndroidBridge() ? 0 : apiPort;
  const remote = typeof import.meta !== 'undefined' ? (import.meta as any).env?.VITE_ANDROID_API_URL as string | undefined : undefined;
  const baseUrl = remote
    ? `${remote.replace(/\/$/, '')}/api/trpc`
    : `http://localhost:${effectivePort}/api/trpc`;

  // On Android without remote, use a custom fetch that never hits the network
  // for the known mock namespaces — saves battery on the device.
  const androidFetch: typeof fetch | undefined = isAndroidBridge() && !remote
    ? async () =>
        // Minimal tRPC-shaped 404 that react-query treats as “not found, use local”:
        new Response(JSON.stringify({ error: { message: 'Android local mode — use on-device store' } }), {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        })
    : undefined;

  return trpc.createClient({
    links: [
      httpBatchLink({
        url: baseUrl,
        // @ts-ignore — httpBatchLink supports custom fetch in recent @trpc/client
        fetch: androidFetch as any,
        headers() {
          const token = getAccessToken();
          return token
            ? {
                'x-access-token': token,
              }
            : {};
        },
      }),
    ],
  });
}

export { getApiPort };
