/**
 * Android Capture — MediaRecorder + MediaProjection instead of VideoDB binary.
 *
 * On Desktop, `videodb/bin/capture` spawns a native binary (darwin-arm64,
 * win32-x64). On Android we use the browser MediaRecorder API, which
 * Capacitor's WebView fully supports, plus Android's MediaProjection for
 * screen audio. No binary needed.
 *
 * This module is tree-shaken on Desktop (only imported when isAndroid()).
 */

export interface AndroidCaptureState {
  isRecording: boolean;
  startTimeMs: number | null;
  chunks: Blob[];
}

let state: AndroidCaptureState = { isRecording: false, startTimeMs: null, chunks: [] };
let mediaRecorder: MediaRecorder | null = null;
let mediaStream: MediaStream | null = null;

export async function androidCheckRecordingSupport(): Promise<{ supported: boolean; reason?: string }> {
  if (typeof navigator === 'undefined' || !navigator.mediaDevices?.getUserMedia) {
    return { supported: false, reason: 'MediaDevices API not available in this WebView.' };
  }
  if (typeof MediaRecorder === 'undefined') {
    return { supported: false, reason: 'MediaRecorder not available.' };
  }
  return { supported: true };
}

export async function androidStartRecording(opts: { mic: boolean; screen: boolean } = { mic: true, screen: false }): Promise<void> {
  if (state.isRecording) throw new Error('Already recording');

  // Prefer getDisplayMedia for screen when requested (needs Android 10+ + user gesture)
  if (opts.screen && (navigator.mediaDevices as any).getDisplayMedia) {
    try {
      const display = await (navigator.mediaDevices as any).getDisplayMedia({ audio: true, video: true });
      const audio = opts.mic ? await navigator.mediaDevices.getUserMedia({ audio: true }) : null;
      const tracks: MediaStreamTrack[] = [];
      for (const t of display.getAudioTracks()) tracks.push(t);
      if (audio) for (const t of audio.getAudioTracks()) tracks.push(t);
      // If we need video for “screen” we could also add video tracks, but Call.md
      // on Android currently records audio only (screen capture is opt-in).
      mediaStream = new MediaStream(tracks);
    } catch (e) {
      // Fall back to mic only if display media denied
      mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    }
  } else {
    mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
  }

  mediaRecorder = new MediaRecorder(mediaStream, { mimeType: MediaRecorder.isTypeSupported('audio/webm;codecs=opus') ? 'audio/webm;codecs=opus' : 'audio/webm' });
  state.chunks = [];
  state.startTimeMs = Date.now();
  state.isRecording = true;

  mediaRecorder.ondataavailable = (ev) => {
    if (ev.data && ev.data.size > 0) state.chunks.push(ev.data);
  };

  mediaRecorder.start(1000); // emit every 1s for live transcription fan-out
}

export async function androidStopRecording(): Promise<Blob | null> {
  if (!state.isRecording || !mediaRecorder) return null;
  return await new Promise<Blob | null>((resolve) => {
    mediaRecorder!.onstop = () => {
      state.isRecording = false;
      const blob = state.chunks.length ? new Blob(state.chunks, { type: mediaRecorder!.mimeType }) : null;
      // cleanup tracks so mic indicator disappears
      try { mediaStream?.getTracks().forEach((t) => t.stop()); } catch {}
      mediaRecorder = null; mediaStream = null;
      resolve(blob);
    };
    try { mediaRecorder!.stop(); } catch { resolve(null); }
  });
}

export function androidGetRecordingDurationMs(): number | null {
  if (!state.isRecording || state.startTimeMs == null) return null;
  return Date.now() - state.startTimeMs;
}

// Pause is implemented by pausing the MediaRecorder (keeps the same file)
export function androidPauseRecording(): void {
  if (mediaRecorder?.state === 'recording') mediaRecorder.pause();
}
export function androidResumeRecording(): void {
  if (mediaRecorder?.state === 'paused') mediaRecorder.resume();
}
