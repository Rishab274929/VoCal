// Home-screen widget — Android port of VoCalWidget.swift.
//
// Reads today's calorie + protein snapshot from Flutter's
// SharedPreferences (the shared_preferences plugin namespaces all keys
// with a "flutter." prefix in the FlutterSharedPreferences file) and
// renders a small progress ring + macro line. Two sizes:
//   - small (2x2): kcal ring + headline number
//   - medium (4x2): same ring + protein bar + remaining-kcal copy
//
// iOS parity: schema matches WidgetBridge.swift's WidgetSnapshot
// exactly so any future cross-platform tooling reads one shape.
//
// Refresh: Flutter publishes a fresh snapshot after every meal mutation
// via MethodChannel("best.vocal.vocal/widget").invokeMethod("reloadWidget");
// MainActivity converts that into a broadcast that lands here in
// onUpdate. We don't set an updatePeriodMillis on the AppWidget metadata
// because the AlarmManager-backed periodic refresh has a 30-min floor
// and the push model is more accurate.

package best.vocal.vocal

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONException
import org.json.JSONObject

class VocalWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val snapshot = readSnapshot(context)
        for (id in appWidgetIds) {
            // Pick layout based on size. Android tells us this via
            // getAppWidgetOptions().minWidth / minHeight; for v1 we use
            // a single layout that adapts via match_parent and let the
            // launcher resize. Simpler to ship.
            val views = RemoteViews(context.packageName, R.layout.vocal_widget)
            populate(context, views, snapshot)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // Push-refresh from Flutter: MainActivity sends ACTION_RELOAD
        // when meals mutate so the tile updates without waiting for
        // the launcher's next periodic tick.
        if (intent.action == ACTION_RELOAD) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, VocalWidgetProvider::class.java)
            )
            if (ids.isNotEmpty()) onUpdate(context, manager, ids)
        }
    }

    private fun populate(context: Context, views: RemoteViews, snap: Snapshot) {
        val eaten = snap.caloriesEaten.coerceAtLeast(0)
        val goal = snap.calorieGoal.coerceAtLeast(1) // avoid /0 in the bar
        val remaining = (snap.calorieGoal - snap.caloriesEaten).coerceAtLeast(0)
        val pct = ((eaten.toDouble() / goal) * 100).coerceIn(0.0, 100.0).toInt()
        val proteinEaten = snap.proteinEaten.coerceAtLeast(0)
        val proteinGoal = snap.proteinGoal.coerceAtLeast(1)
        val proteinPct =
            ((proteinEaten.toDouble() / proteinGoal) * 100)
                .coerceIn(0.0, 100.0)
                .toInt()

        views.setTextViewText(
            R.id.widget_kcal_remaining,
            String.format("%,d", remaining)
        )
        views.setTextViewText(
            R.id.widget_kcal_label,
            "kcal left"
        )
        views.setTextViewText(
            R.id.widget_kcal_breakdown,
            String.format("%,d / %,d", eaten, snap.calorieGoal)
        )
        // ProgressBar — calorie ring substitute. RemoteViews supports
        // setProgress; we don't have access to a real ring widget
        // without RemoteViewsService, and ProgressBar is plenty for a
        // small tile.
        views.setProgressBar(R.id.widget_kcal_bar, 100, pct, false)
        views.setTextViewText(
            R.id.widget_protein,
            "P ${proteinEaten}g / ${snap.proteinGoal}g"
        )
        views.setProgressBar(R.id.widget_protein_bar, 100, proteinPct, false)

        // Tap-to-open: clicking the widget launches MainActivity. The
        // PendingIntent must use FLAG_IMMUTABLE on API 23+ (we ship
        // minSdk 24) — Android 12+ also requires FLAG_UPDATE_CURRENT
        // when we re-use the same request code.
        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
        if (launch != null) {
            val pi = PendingIntent.getActivity(
                context,
                0,
                launch,
                PendingIntent.FLAG_IMMUTABLE or
                    PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setOnClickPendingIntent(R.id.widget_root, pi)
        }
    }

    private fun readSnapshot(context: Context): Snapshot {
        // Flutter shared_preferences plugin stores everything in a
        // single "FlutterSharedPreferences" file and namespaces all
        // user keys with the "flutter." prefix (v2.x behavior). So the
        // Dart-side WidgetBridge.snapshotKey "vocal.widget.snapshot.v1"
        // is accessed here as "flutter.vocal.widget.snapshot.v1".
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE
        )
        val raw = prefs.getString(
            "flutter.${WIDGET_SNAPSHOT_KEY}",
            null
        ) ?: return Snapshot.empty
        return try {
            val j = JSONObject(raw)
            Snapshot(
                caloriesEaten = j.optInt("caloriesEaten", 0),
                calorieGoal = j.optInt("calorieGoal", 2000),
                proteinEaten = j.optInt("proteinEaten", 0),
                proteinGoal = j.optInt("proteinGoal", 140)
            )
        } catch (_: JSONException) {
            Snapshot.empty
        }
    }

    /// Compact snapshot — mirror of the iOS WidgetBridge.WidgetSnapshot
    /// shape. Stays a plain data class so future Dart-side schema
    /// changes (e.g. adding micros) only need one parser update.
    private data class Snapshot(
        val caloriesEaten: Int,
        val calorieGoal: Int,
        val proteinEaten: Int,
        val proteinGoal: Int
    ) {
        companion object {
            val empty = Snapshot(0, 2000, 0, 140)
        }
    }

    companion object {
        /// Custom action MainActivity sends to push-refresh the tile.
        const val ACTION_RELOAD = "best.vocal.vocal.WIDGET_RELOAD"
        const val WIDGET_SNAPSHOT_KEY = "vocal.widget.snapshot.v1"
    }
}
