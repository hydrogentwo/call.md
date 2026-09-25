/**
 * Android Storage — IndexedDB + Capacitor Preferences fallback for SQLite.
 *
 * On Desktop, history/transcripts live in better-sqlite3 (Drizzle ORM).
 * On Android, better-sqlite3 cannot run (no native prebuild). Capacitor
 * provides @capacitor-community/sqlite but to keep the APK lean we default
 * to IndexedDB + Preferences, with an optional SQLite upgrade path.
 *
 * This module exposes the same surface as `src/main/db/index.ts` (CRUD for
 * recordings, segments) but backed by IndexedDB. The renderer calls it
 * through the Android tRPC mock (src/renderer/api/android-trpc.ts).
 */

import { Preferences } from '@capacitor/preferences';

export interface AndroidRecording {
  id: number;
  sessionId: string;
  status: 'recording' | 'processing' | 'available' | 'failed';
  duration: number | null;
  createdAt: string;
  insights: string | null;
  shortOverview?: string | null;
}

const DB_NAME = 'callmd-android';
const STORE_RECORDINGS = 'recordings';
const STORE_SEGMENTS = 'segments';

function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 2);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE_RECORDINGS)) {
        db.createObjectStore(STORE_RECORDINGS, { keyPath: 'id', autoIncrement: true });
      }
      if (!db.objectStoreNames.contains(STORE_SEGMENTS)) {
        const s = db.createObjectStore(STORE_SEGMENTS, { keyPath: 'id' });
        s.createIndex('sessionId', 'sessionId', { unique: false });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export async function androidListRecordings(): Promise<AndroidRecording[]> {
  try {
    const db = await openDB();
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_RECORDINGS, 'readonly');
      const store = tx.objectStore(STORE_RECORDINGS);
      const req = store.getAll();
      req.onsuccess = () => resolve(req.result ?? []);
      req.onerror = () => reject(req.error);
    });
  } catch {
    // Fallback: Preferences JSON blob (for very old WebViews without IndexedDB)
    const { value } = await Preferences.get({ key: 'callmd:recordings' });
    return value ? (JSON.parse(value) as AndroidRecording[]) : [];
  }
}

export async function androidSaveRecording(rec: Omit<AndroidRecording, 'id'> & { id?: number }): Promise<number> {
  const db = await openDB();
  return await new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_RECORDINGS, 'readwrite');
    const store = tx.objectStore(STORE_RECORDINGS);
    const req = store.put(rec as any);
    req.onsuccess = () => resolve(req.result as number);
    req.onerror = () => reject(req.error);
  });
}

export async function androidGetRecording(id: number | string): Promise<AndroidRecording | null> {
  const db = await openDB();
  return await new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_RECORDINGS, 'readonly');
    const store = tx.objectStore(STORE_RECORDINGS);
    const req = store.get(Number(id));
    req.onsuccess = () => resolve(req.result ?? null);
    req.onerror = () => reject(req.error);
  });
}

// ── Transcript segments (used by Bend metrics on device) ─
export interface AndroidSegment {
  id: string;
  sessionId: string;
  channel: 'me' | 'them';
  text: string;
  startTime: number;
  endTime: number;
  isFinal: boolean;
}

export async function androidSaveSegment(seg: AndroidSegment): Promise<void> {
  const db = await openDB();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE_SEGMENTS, 'readwrite');
    tx.objectStore(STORE_SEGMENTS).put(seg);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export async function androidListSegments(sessionId: string): Promise<AndroidSegment[]> {
  const db = await openDB();
  return await new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_SEGMENTS, 'readonly');
    const idx = tx.objectStore(STORE_SEGMENTS).index('sessionId');
    const req = idx.getAll(sessionId);
    req.onsuccess = () => resolve(req.result ?? []);
    req.onerror = () => reject(req.error);
  });
}
