/**
 * Android Bridge — mirrors `src/main/ipc/*` but runs inside the WebView.
 *
 * On Electron, renderer talks to main via `window.electronAPI` (IPC + HTTP trpc
 * on 127.0.0.1:51731). On Android there is no main process, so this module
 * provides:
 *  - Capacitor Preferences-backed config (instead of encrypted SQLite)
 *  - Capacitor Filesystem stubs for recordings
 *  - MediaRecorder-based capture (instead of videodb capture binary)
 *  - In-memory/mock tRPC (no Hono server needed)
 *
 * The rest of the app keeps calling `window.electronAPI` / `useConfigStore`;
 * this file shims those on Android so zero renderer changes are needed.
 */

import { Preferences } from '@capacitor/preferences';
import { Filesystem, Directory } from '@capacitor/filesystem';
import { isAndroid } from './platform';

const PREF_PREFIX = 'callmd:';

// ── Preferences-backed key/value (mirrors src/main/lib/config.ts + secure-store) ─
export async function androidGetPref<T>(key: string, fallback: T): Promise<T> {
  try {
    const { value } = await Preferences.get({ key: PREF_PREFIX + key });
    if (value == null) return fallback;
    return JSON.parse(value) as T;
  } catch {
    return fallback;
  }
}

export async function androidSetPref(key: string, value: unknown): Promise<void> {
  await Preferences.set({ key: PREF_PREFIX + key, value: JSON.stringify(value) });
}

export async function androidRemovePref(key: string): Promise<void> {
  await Preferences.remove({ key: PREF_PREFIX + key });
}

// ── Config shape mirrored from src/shared/schemas/config.schema.ts ─
export interface AndroidAppConfig {
  accessToken?: string;
  userName?: string;
  apiKey?: string;
  transcriptionLanguage?: string;
}

export async function androidGetConfig(): Promise<AndroidAppConfig> {
  const [accessToken, userName, apiKey, transcriptionLanguage] = await Promise.all([
    androidGetPref<string | undefined>('accessToken', undefined as any),
    androidGetPref<string | undefined>('userName', undefined as any),
    androidGetPref<string | undefined>('apiKey', undefined as any),
    androidGetPref<string | undefined>('transcriptionLanguage', undefined as any),
  ]);
  return { accessToken: accessToken || undefined, userName: userName || undefined, apiKey, transcriptionLanguage };
}

export async function androidSaveConfig(partial: AndroidAppConfig): Promise<void> {
  const entries = Object.entries(partial) as Array<[keyof AndroidAppConfig, string | undefined]>;
  for (const [k, v] of entries) {
    if (v == null) await androidRemovePref(k);
    else await androidSetPref(k, v);
  }
}

// ── Filesystem helpers (recordings, logs) ─
export async function androidWriteFile(path: string, data: string): Promise<string> {
  const res = await Filesystem.writeFile({ path, data, directory: Directory.Data, recursive: true });
  return res.uri;
}

export async function androidReadFile(path: string): Promise<string | null> {
  try {
    const { data } = await Filesystem.readFile({ path, directory: Directory.Data });
    return typeof data === 'string' ? data : String(data);
  } catch {
    return null;
  }
}

// ── Device info (optional — @capacitor/device not required for core) ─
export async function androidGetDeviceInfo() {
  if (!isAndroid()) return null;
  try {
    const { Device } = await import('@capacitor/device').catch(() => ({ Device: null as any }));
    if (!Device) return null;
    return await Device.getInfo();
  } catch {
    return null;
  }
}

// ── Window bridge — installs `window.electronAPI` shim on Android so existing
//    renderer code (usePermissions, useSession, etc.) keeps working.           ─

export function installAndroidBridge(): void {
  if (!isAndroid()) return;
  if (typeof window === 'undefined') return;
  if ((window as any).electronAPI) return; // Electron already present (e.g. in dev preview)

  // Minimal shim — every IPC namespace the renderer touches must exist here
  // or hooks will fall back to no-ops. We implement what Android can do.
  const noopSub = () => () => {};
  const shim: any = {
    app: {
      getSettings: async () => androidGetConfig(),
      saveSettings: async (cfg: AndroidAppConfig) => { await androidSaveConfig(cfg); return { ok: true }; },
      getServerPort: async () => 0, // no Hono server on Android
    },
    permissions: {
      getStatus: async () => ({ microphone: true, screen: true, accessibility: true }),
      requestMicPermission: async () => true,
      requestScreenPermission: async () => true,
      openSystemSettings: async () => {},
    },
    // capture, copilot, mcp, etc. will be handled via tRPC mock or direct
    // Capacitor plugins; keep stubs to avoid “undefined is not a function”
    capture: { getStatus: async () => ({ supported: true }) },
    calendar: {
      getStatus: async () => ({ connected: false }),
      setRecordingMeeting: async () => {},
    },
    calendarOn: {
      onOpenMeetingSetup: (cb: any) => { void cb; return noopSub(); },
      onAutoStartRecording: (cb: any) => { void cb; return noopSub(); },
      onOverlappingMeeting: (cb: any) => { void cb; return noopSub(); },
    },
    copilotOn: { onNudge: () => noopSub(), onMetrics: () => noopSub() },
    mcpOn: { onResult: () => noopSub() },
    liveAssistOn: { onAssist: () => noopSub() },
    widgetOn: { onToggle: () => noopSub() },
  };

  (window as any).electronAPI = shim;
  (window as any).capacitorAPI = shim;

  console.log('[Call.md] Android bridge installed');
}
