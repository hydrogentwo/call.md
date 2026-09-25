package com.videodb.callmd;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import androidx.core.app.NotificationCompat;

/**
 * Foreground service that keeps the MediaRecorder / WebSocket alive when
 * Call.md is in the background during a recording (Android kills background
 * WebViews quickly). The JS side starts this via a Capacitor plugin call
 * before calling androidStartRecording() and stops it after.
 *
 * For the initial scaffold this is a minimal sticky notification; the JS
 * recording logic still lives in src/mobile/capture-android.ts (MediaRecorder).
 * A future native implementation can move the actual MediaRecorder here.
 */
public class RecordingService extends Service {

    private static final String CHANNEL_ID = "callmd_recording";
    private static final int NOTIF_ID = 1;

    @Override
    public void onCreate() {
        super.onCreate();
        createChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Notification notif = new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Call.md is recording")
            .setContentText("Tap to return to the call")
            .setSmallIcon(getApplicationInfo().icon)
            .setOngoing(true)
            .build();
        startForeground(NOTIF_ID, notif);
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onDestroy() {
        stopForeground(true);
        super.onDestroy();
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                CHANNEL_ID, "Call recording",
                NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("Shows while Call.md is recording");
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(ch);
        }
    }
}
