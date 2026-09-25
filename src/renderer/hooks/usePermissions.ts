import { useState, useEffect, useCallback } from 'react';
import { getElectronAPI } from '../api/ipc';
import type { PermissionStatus } from '../../shared/types/ipc.types';

export function usePermissions() {
  const [status, setStatus] = useState<PermissionStatus>({
    microphone: false,
    screen: false,
    accessibility: false,
  });
  const [loading, setLoading] = useState(true);

  const checkPermissions = useCallback(async () => {
    // Android: permissions are runtime + WebView-granted; if Capacitor is native,
    // assume mic will be granted via the system prompt on first getUserMedia.
    try {
      // @ts-ignore
      const isAndroid = typeof window !== 'undefined' && window.Capacitor?.isNativePlatform?.() && window.Capacitor.getPlatform() === 'android';
      if (isAndroid) {
        // Check via MediaDevices permission query if available
        try {
          const mic = await (navigator as any).permissions?.query?.({ name: 'microphone' as any });
          const screen = { state: 'granted' as const }; // screen capture is per-session on Android
          setStatus({
            microphone: mic?.state === 'granted' || false,
            screen: true, // not a persistent permission on Android
            accessibility: true,
          });
          // also allow mic prompt to succeed — treat as granted after query
          if (mic?.state !== 'granted') {
            // optimistic: WebView will prompt on getUserMedia; we show CTA
            setStatus((p) => ({ ...p }));
          }
        } catch {
          setStatus({ microphone: false, screen: true, accessibility: true });
        }
        setLoading(false);
        return;
      }
    } catch {}
    const api = getElectronAPI();
    if (!api) {
      setLoading(false);
      return;
    }

    try {
      const permStatus = await api.permissions.getStatus();
      setStatus(permStatus);
    } catch (error) {
      console.error('Failed to check permissions:', error);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    checkPermissions();
  }, [checkPermissions]);

  const requestMicPermission = useCallback(async () => {
    try {
      // @ts-ignore
      const isAndroid = typeof window !== 'undefined' && window.Capacitor?.isNativePlatform?.() && window.Capacitor.getPlatform() === 'android';
      if (isAndroid) {
        try {
          const s = await navigator.mediaDevices.getUserMedia({ audio: true });
          s.getTracks().forEach((t) => t.stop());
          setStatus((prev) => ({ ...prev, microphone: true }));
          return true;
        } catch {
          return false;
        }
      }
    } catch {}
    const api = getElectronAPI();
    if (!api) return false;

    const granted = await api.permissions.requestMicPermission();
    if (granted) {
      setStatus((prev) => ({ ...prev, microphone: true }));
    }
    return granted;
  }, []);

  const requestScreenPermission = useCallback(async () => {
    const api = getElectronAPI();
    if (!api) return false;

    const granted = await api.permissions.requestScreenPermission();
    await checkPermissions(); // Re-check since user needs to grant manually
    return granted;
  }, [checkPermissions]);

  const openSettings = useCallback(async (pane: string) => {
    const api = getElectronAPI();
    if (!api) return;
    await api.permissions.openSystemSettings(pane);
  }, []);

  const allGranted = status.microphone && status.screen;

  return {
    status,
    loading,
    allGranted,
    checkPermissions,
    requestMicPermission,
    requestScreenPermission,
    openSettings,
  };
}
