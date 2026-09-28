package com.modu.reader.smsprobe;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

/** Separate disposable APK. No SMS/contact/storage/network permissions.
 * Synthetic focus events are NOT a substitute for an actual incoming SMS.
 * Target 28 permits background focus requests from an adb-invoked receiver;
 * the production application's target SDK is unchanged.
 */
public final class ProbeReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        String mode = intent.getStringExtra("mode");
        NotificationManager notifications = context.getSystemService(NotificationManager.class);
        if ("notification".equals(mode)) {
            notifications.createNotificationChannel(new NotificationChannel(
                "modu-sms-probe", "One synthetic message", NotificationManager.IMPORTANCE_DEFAULT));
            notifications.notify(1, new Notification.Builder(context, "modu-sms-probe")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Modu test: one message")
                .setContentText("Synthetic notification; no real SMS was sent.")
                .setOnlyAlertOnce(true).build());
            Log.i("ModuSmsProbe", "ONE_NOTIFICATION_POSTED");
            return;
        }
        if ("cleanup".equals(mode)) {
            notifications.cancel(1);
            notifications.deleteNotificationChannel("modu-sms-probe");
            return;
        }
        if (!"duck".equals(mode) && !"pause".equals(mode)) return;
        final PendingResult pending = goAsync();
        AudioManager audio = context.getSystemService(AudioManager.class);
        Handler handler = new Handler(Looper.getMainLooper());
        AudioFocusRequest request = new AudioFocusRequest.Builder(
                "duck".equals(mode) ? AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                    : AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            .setOnAudioFocusChangeListener(change -> Log.i("ModuSmsProbe", "FOCUS_CHANGE=" + change), handler)
            .build();
        int result = audio.requestAudioFocus(request);
        Log.i("ModuSmsProbe", "REQUEST " + mode + " result=" + result);
        int duration = Math.max(100, Math.min(5000, intent.getIntExtra("duration", 1200)));
        handler.postDelayed(() -> {
            audio.abandonAudioFocusRequest(request);
            Log.i("ModuSmsProbe", "FOCUS_ABANDONED");
            pending.finish();
        }, duration);
    }
}
