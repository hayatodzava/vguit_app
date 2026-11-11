package ru.vsuet.vguit

import android.content.Intent
import android.net.Uri
import androidx.core.content.pm.PackageInfoCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Канал для проверки обновлений: версия приложения и открытие ссылки
 * на APK в браузере.
 *
 * Установку выполняет система из браузера — приложение не запрашивает
 * разрешение `REQUEST_INSTALL_PACKAGES`, поэтому Google Play Protect
 * не показывает предупреждение «может устанавливать другие приложения».
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "vguit_app/updater"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "appInfo" -> result.success(appInfo())
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("no_url", "Не передан адрес", null)
                    } else {
                        result.success(openUrl(url))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun appInfo(): Map<String, Any> {
        val info = packageManager.getPackageInfo(packageName, 0)
        return mapOf(
            "versionName" to (info.versionName ?: ""),
            "versionCode" to PackageInfoCompat.getLongVersionCode(info),
            "packageName" to packageName,
        )
    }

    private fun openUrl(url: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            // Нет браузера или ссылка не открылась.
            false
        }
    }
}