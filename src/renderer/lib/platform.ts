/**
 * Platform detection — Electron vs Android (Capacitor) vs Web
 *
 * Centralizes every `isAndroid` / `isElectron` / `isWeb` check so the
 * 200+ call sites in the renderer don't need to know about Capacitor.
 * The Bend rebuild already runs pure JS on Android (fallback metrics).
 */

export type Platform = 'electron' | 'android' | 'web';

// Capacitor adds `window.Capacitor` at runtime; we access it via (window as any)
export function getPlatform(): Platform {
  if (typeof window !== 'undefined' && (window as any).Capacitor?.isNativePlatform?.()) {
    const p = (window as any).Capacitor.getPlatform();
    if (p === 'android') return 'android';
    if (p === 'ios') return 'android'; // later map to ios if needed
  }
  if (typeof window !== 'undefined' && !!(window as any).electronAPI) return 'electron';
  // Heuristic: Android WebView user agent contains `; wv)` and `Android`
  if (typeof navigator !== 'undefined' && /Android/.test(navigator.userAgent)) {
    // In Capacitor the WebView UA still contains Android, but isNativePlatform
    // would already have returned true. This catches plain Chrome PWA on Android.
    return 'android';
  }
  return 'web';
}

export const isAndroid = () => getPlatform() === 'android';
export const isElectron = () => getPlatform() === 'electron';
export const isNative = () => isAndroid() || isElectron();
export const isWeb = () => getPlatform() === 'web';

// Helpers for UI

export function shouldUseMobileLayout(): boolean {
  if (isAndroid()) return true;
  if (typeof window === 'undefined') return false;
  return window.innerWidth < 768 || window.innerHeight < 600;
}

export function getRecordingSupportMessage(platform: Platform): string | null {
  if (platform === 'android') return null; // supported via MediaRecorder
  if (platform === 'electron') return null; // supported per capture-platform.ts
  return 'Recording requires Android or Desktop (macOS/Windows) app.';
}
