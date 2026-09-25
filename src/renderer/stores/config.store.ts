import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { AUTO_LANGUAGE } from '../../shared/constants/languages';

interface ConfigState {
  accessToken: string | null;
  userName: string | null;
  apiKey: string | null;
  apiUrl: string | null;
  transcriptionLanguage: string;
  onboardingComplete: boolean;

  setAuth: (accessToken: string, userName: string, apiKey: string) => void;
  setConfig: (config: Partial<ConfigState>) => void;
  hydrateFromMain: () => Promise<void>;
  clearAuth: () => void;
  isAuthenticated: () => boolean;
  completeOnboarding: () => void;
}

export const useConfigStore = create<ConfigState>()(
  persist(
    (set, get) => ({
      accessToken: null,
      userName: null,
      apiKey: null,
      apiUrl: null,
      transcriptionLanguage: AUTO_LANGUAGE,
      onboardingComplete: false,

      setAuth: (accessToken, userName, apiKey) => {
        set({ accessToken, userName, apiKey });
        // Desktop: main process owns credentials (encrypted via OS keyring).
        // Android: Capacitor Preferences (encrypted SharedPreferences on device).
        void (async () => {
          try {
            const api: any = (window as any).electronAPI;
            if (api?.app?.saveSettings) {
              await api.app.saveSettings({ accessToken, userName, apiKey });
            } else {
              // Fallback — Android / Web: persist via Preferences if available
              const { Preferences } = await import('@capacitor/preferences').catch(() => ({ Preferences: null as any }));
              if (Preferences) {
                await Preferences.set({ key: 'callmd:accessToken', value: JSON.stringify(accessToken) });
                await Preferences.set({ key: 'callmd:userName', value: JSON.stringify(userName) });
                // On Android we *do* store apiKey in Preferences (Keystore-backed when available)
                await Preferences.set({ key: 'callmd:apiKey', value: JSON.stringify(apiKey) });
              }
            }
          } catch {}
        })();
      },

      setConfig: (config) => {
        set(config);
      },

      /**
       * Loads settings the renderer does not persist itself - the API key lives
       * only in the main process - and the saved transcription language.
       * On Android, Preferences is the source of truth.
       */
      hydrateFromMain: async () => {
        try {
          const api: any = (window as any).electronAPI;
          if (api?.app?.getSettings) {
            const settings = await api.app.getSettings();
            if (settings) {
              set((state) => ({
                apiKey: settings.apiKey ?? state.apiKey,
                apiUrl: (settings as any).apiUrl ?? state.apiUrl,
                userName: (settings as any).userName ?? null,
                accessToken: (settings as any).accessToken ?? null,
                onboardingComplete: Boolean((settings as any).accessToken) && state.onboardingComplete,
                transcriptionLanguage: (settings as any).transcriptionLanguage || AUTO_LANGUAGE,
              }));
              return;
            }
          }
        } catch {
          // fall through to Preferences
        }
        // Android / Web fallback — Preferences
        try {
          const { Preferences } = await import('@capacitor/preferences').catch(() => ({ Preferences: null as any }));
          if (!Preferences) return;
          const get = async (k: string) => {
            const { value } = await Preferences.get({ key: k });
            return value ? (JSON.parse(value) as string) : null;
          };
          const [accessToken, userName, apiKey, transcriptionLanguage] = await Promise.all([
            get('callmd:accessToken'),
            get('callmd:userName'),
            get('callmd:apiKey'),
            get('callmd:transcriptionLanguage'),
          ]);
          if (accessToken || userName || apiKey) {
            set((s) => ({
              accessToken: accessToken ?? s.accessToken,
              userName: userName ?? s.userName,
              apiKey: apiKey ?? s.apiKey,
              transcriptionLanguage: transcriptionLanguage || s.transcriptionLanguage,
              onboardingComplete: Boolean(accessToken) && s.onboardingComplete,
            }));
          }
        } catch {
          // Settings are optional
        }
      },

      clearAuth: () => {
        set({
          accessToken: null,
          userName: null,
          apiKey: null,
          onboardingComplete: false,
        });
      },

      isAuthenticated: () => {
        return !!get().accessToken;
      },

      completeOnboarding: () => {
        set({ onboardingComplete: true });
      },
    }),
    {
      name: 'call-md-config',
      // The API key is deliberately absent: localStorage is plaintext on disk
      // and any renderer script can read it. The main process holds the key
      // (encrypted via the OS keyring) and rehydrates it through `get-settings`
      // on startup.
      partialize: (state) => ({
        accessToken: state.accessToken,
        userName: state.userName,
        onboardingComplete: state.onboardingComplete,
      }),
    }
  )
);
