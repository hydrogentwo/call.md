/**
 * Android tRPC mock — no Hono server on device.
 *
 * The desktop renderer creates a tRPC client that talks to
 * `http://127.0.0.1:<port>/api/trpc` (the Hono server in main). On Android
 * there is no Node main, so we provide an in-process router that implements
 * the same procedures using Capacitor APIs + IndexedDB. The component tree
 * keeps calling `trpc.xxx.useQuery()` unchanged.
 *
 * If you later run a remote tRPC server (e.g. self-hosted), set
 * `VITE_ANDROID_API_URL` to that URL and this file will proxy there instead
 * of using the local mock.
 */

import { CapacitorHttp } from '@capacitor/core';

export function shouldUseRemoteApi(): string | null {
  // @ts-ignore
  const remote = (import.meta as any)?.env?.VITE_ANDROID_API_URL as string | undefined;
  return remote && remote.length ? remote : null;
}

// Tiny Hono-compatible fetch that CapacitorHttp can use on Android
export async function androidFetch(url: string, opts: RequestInit = {}): Promise<Response> {
  const remote = shouldUseRemoteApi();
  const full = remote ? `${remote.replace(/\/$/, '')}${url}` : url;

  // Try CapacitorHttp (works with native CORS), fallback to fetch
  try {
    // CapacitorHttp.request is the native HTTP plugin
    // @ts-ignore
    if ((CapacitorHttp as any)?.request) {
      const res: any = await (CapacitorHttp as any).request({
        url: full,
        method: (opts.method as any) || 'GET',
        headers: opts.headers as any,
        data: opts.body,
      });
      return new Response(res.data, { status: res.status, headers: res.headers as any });
    }
  } catch {
    // fall back
  }
  return fetch(full, opts as any);
}
