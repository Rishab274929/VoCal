// Foreground-service notification — Android port of the iOS Live
// Activity (VoCalWidgetLiveActivity.swift). Pins a persistent
// notification showing today's calorie + protein progress while the
// service is running, mirroring how iOS Live Activities appear on the
// lock screen and Dynamic Island.
//
// Lifecycle:
//   - Flutter starts the service via MethodChannel("startVocalSessionService")
//     after a meaningful logging moment (first meal of the day, etc.)
//     so the notification doesn't appear on a fresh-install with zero
//     state.
//   - Service registers a BroadcastReceiver for the same
//     WIDGET_RELOAD action VocalWidgetProvider listens for. Every
//     meal mutation re-reads SharedPreferences and rebuilds the
//     notification — push-based, no polling.
//   - Flutter calls stopVocalSessionService to dismiss (typically on
//     sign-out or an explicit user toggle in Settings).
//
// Channel: a dedicated low-importance channel so the ongoing
// notification doesn't ping the user every time it updates. Plays no
// sound, no vibration — it's a status surface, not an alert.

package best.vocal.vocal

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import org.json.JSONException
import org.json.JSONObject

class VocalSessionService : Service() {

    private val reloadReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == VocalWidgetProvider.ACTION_RELOAD) {
                postOrUpdateNotification()
            }
        }
    }
    private var receiverRegistered = false

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                postOrUpdateNotification(isInitial = true)
                if (!receiverRegistered) {
                    // Android 14+ requires explicit receiver-export flags;
                    // we want internal-only because the broadcast is
                    // ours.
                    val filter = IntentFilter(VocalWidgetProvider.ACTION_RELOAD)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(reloadReceiver, filter, RECEIVER_NOT_EXPORTED)
                    } else {
                        @Suppress("UnspecifiedRegisterReceiverFlag")
                        registerReceiver(reloadReceiver, filter)
                    }
                    receiverRegistered = true
                }
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                if (receiverRegistered) {
                    try { unregisterReceiver(reloadReceiver) } catch (_: Throwable) {}
                    receiverRegistered = false
                }
                stopSelf()
            }
        }
        // START_STICKY so Android re-creates the service if it's killed
        // under memory pressure — the notification gets re-posted from
        // SharedPreferences and the user keeps their live activity.
        return START_STICKY
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            try { unregisterReceiver(reloadReceiver) } catch (_: Throwable) {}
            receiverRegistered = false
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun postOrUpdateNotification(isInitial: Boolean = false) {
        val snap = readSnapshot()
        val eaten = snap.optInt("caloriesEaten", 0).coerceAtLeast(0)
        val goal = snap.optInt("calorieGoal", 2000).coerceAtLeast(1)
        val remaining = (goal - eaten).coerceAtLeast(0)
        val proteinEaten = snap.optInt("proteinEaten", 0).coerceAtLeast(0)
        val proteinGoal = snap.optInt("proteinGoal", 140).coerceAtLeast(1)
        val pct = ((eaten.toDouble() / goal) * 100).coerceIn(0.0, 100.0).toInt()

        val tap = packageManager.getLaunchIntentForPackage(packageName)
        val tapPi = tap?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }

        val title = String.format("%,d kcal left", remaining)
        val subtitle = String.format(
            "%,d / %,d · P %dg / %dg",
            eaten,
            goal,
            proteinEaten,
            proteinGoal
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setStyle(NotificationCompat.BigTextStyle().bigText(subtitle))
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setProgress(100, pct, false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .also { b -> if (tapPi != null) b.setContentIntent(tapPi) }

        if (isInitial) {
            startForeground(NOTIFICATION_ID, builder.build())
        } else {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, builder.build())
        }
    }

    private fun readSnapshot(): JSONObject {
        val prefs = getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE
        )
        val raw = prefs.getString(
            "flutter.${VocalWidgetProvider.WIDGET_SNAPSHOT_KEY}",
            null
        ) ?: return JSONObject()
        return try {
            JSONObject(raw)
        } catch (_: JSONException) {
            JSONObject()
        }
    }

    private fun ensureChannel() {
        // O+ requires a channel before posting any notification. Low
        // importance so the ongoing tile doesn't make noise on every
        // refresh; the channel is dedicated to this service so users
        // can mute it in system settings without touching alerting
        // channels we might add later (e.g., a reminders channel).
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.vocal_session_channel),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = getString(R.string.vocal_session_channel_desc)
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            nm.createNotificationChannel(channel)
        }
    }

    companion object {
        const val ACTION_START = "best.vocal.vocal.SESSION_START"
        const val ACTION_STOP = "best.vocal.vocal.SESSION_STOP"
        private const val CHANNEL_ID = "vocal_session_v1"
        private const val NOTIFICATION_ID = 4101
    }
}
