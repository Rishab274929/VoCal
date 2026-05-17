package best.vocal.vocal

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /// MethodChannel name MUST match the Dart side
    /// (lib/services/widget_bridge.dart). Two methods:
    ///   - reloadWidget: pushes a broadcast to VocalWidgetProvider so the
    ///     home-screen tile redraws after a meal mutation.
    ///   - startVocalSessionService / stopVocalSessionService: start or
    ///     stop the ongoing-notification "live activity" foreground
    ///     service that mirrors today's totals in the notification
    ///     shade (iOS Live Activity equivalent).
    private val widgetChannelName = "best.vocal.vocal/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            widgetChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "reloadWidget" -> {
                    // Send the broadcast WITH the receiver explicit so
                    // Android 14+ doesn't drop an implicit one. The
                    // VocalWidgetProvider handles ACTION_RELOAD in its
                    // onReceive and runs onUpdate against every live
                    // widget instance.
                    val intent = Intent(applicationContext, VocalWidgetProvider::class.java)
                        .setAction(VocalWidgetProvider.ACTION_RELOAD)
                    applicationContext.sendBroadcast(intent)
                    result.success(null)
                }
                "startVocalSessionService" -> {
                    val intent = Intent(applicationContext, VocalSessionService::class.java)
                        .setAction(VocalSessionService.ACTION_START)
                    // startForegroundService on API 26+; foreground promotion
                    // happens inside the service via startForeground().
                    applicationContext.startForegroundService(intent)
                    result.success(null)
                }
                "stopVocalSessionService" -> {
                    val intent = Intent(applicationContext, VocalSessionService::class.java)
                        .setAction(VocalSessionService.ACTION_STOP)
                    applicationContext.startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
