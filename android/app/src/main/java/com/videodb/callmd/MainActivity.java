package com.videodb.callmd;

import android.os.Bundle;
import android.view.WindowManager;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.Bridge;
import android.webkit.WebView;
import android.os.Build;

/**
 * Call.md — Android MainActivity
 *
 * BridgeActivity hosts the Capacitor WebView that renders dist/renderer.
 * We keep the screen on during recordings and enable WebView debugging
 * in debug builds so `chrome://inspect` works.
 */
public class MainActivity extends BridgeActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Keep screen on while the app is visible — critical during 2h recordings.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        // Edge-to-edge on Android 15+ (Capacitor handles insets via CSS env(safe-area-inset-*))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            getWindow().setDecorFitsSystemWindows(false);
        }
    }

    @Override
    public void onStart() {
        super.onStart();
        // Enable remote debugging in debug builds only
        if ((getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            try {
                WebView.setWebContentsDebuggingEnabled(true);
            } catch (Exception ignored) {}
        }
    }

    // Back button is handled in JS via @capacitor/app BackButton listener.
    // If the WebView can go back we do; otherwise we let the system handle it
    // (JS calls App.exitApp when at root).
}
