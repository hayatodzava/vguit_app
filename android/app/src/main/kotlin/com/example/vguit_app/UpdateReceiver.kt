package com.example.vguit_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Перезапуск после обновления: система шлёт MY_PACKAGE_REPLACED, когда
 * установлена новая версия нашего пакета.
 *
 * На Android 10+ фоновый запуск активности может быть отклонён системой —
 * тогда пользователь просто откроет приложение сам, ничего не сломается.
 */
class UpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        try {
            val launch = context.packageManager
                .getLaunchIntentForPackage(context.packageName) ?: return
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(launch)
        } catch (_: Exception) {
            // Запуск из фона запрещён — не мешаем пользователю.
        }
    }
}