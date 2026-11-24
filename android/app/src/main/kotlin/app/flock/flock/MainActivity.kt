package app.flock.flock

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flock/config")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasGoogleMapsKey" -> result.success(hasMapsKey())
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasMapsKey(): Boolean = try {
        val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
        !info.metaData?.getString("com.google.android.geo.API_KEY").isNullOrBlank()
    } catch (e: Exception) {
        false
    }
}
