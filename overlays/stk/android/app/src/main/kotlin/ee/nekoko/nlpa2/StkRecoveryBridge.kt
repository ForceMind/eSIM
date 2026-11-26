package ee.nekoko.nlpa2

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

/** Launch only system-provided, exported STK launcher activities. No CAT commands or card I/O. */
internal class StkRecoveryBridge(private val activity: Activity) {
    companion object {
        private val packages = listOf("com.android.stk", "com.android.stk1", "com.android.stk2")
    }

    private data class Entry(val component: ComponentName, val label: String)

    private fun entries(): List<Entry> {
        val pm = activity.packageManager
        return packages.flatMap { pkg ->
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(pkg)
            pm.queryIntentActivities(intent, 0).mapNotNull { resolved ->
                val info = resolved.activityInfo ?: return@mapNotNull null
                val flags = info.applicationInfo.flags
                val system = (flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0
                // The query already filters effectively disabled components, including
                // STK launchers enabled at runtime despite a disabled manifest default.
                if (!system || info.packageName != pkg || !info.exported) return@mapNotNull null
                Entry(ComponentName(info.packageName, info.name), resolved.loadLabel(pm).toString())
            }
        }.distinctBy { it.component }.sortedBy { it.component.flattenToString() }
    }

    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "list" -> result.success(entries().map {
                    mapOf("id" to it.component.flattenToString(), "label" to it.label,
                        "packageName" to it.component.packageName)
                })
                "open" -> {
                    val requested = call.argument<String>("id")
                    val entry = entries().firstOrNull { it.component.flattenToString() == requested }
                    if (entry == null) {
                        result.error("UNAVAILABLE", "No enabled public STK launcher matches this selection", null)
                        return
                    }
                    activity.startActivity(Intent(Intent.ACTION_MAIN)
                        .addCategory(Intent.CATEGORY_LAUNCHER).setComponent(entry.component))
                    result.success("launch_requested")
                }
                "settings" -> {
                    activity.startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                    result.success("settings_requested")
                }
                else -> result.notImplemented()
            }
        } catch (_: ActivityNotFoundException) {
            result.error("UNAVAILABLE", "System activity is unavailable", null)
        } catch (_: SecurityException) {
            result.error("DENIED", "Android refused to launch the system activity", null)
        } catch (_: RuntimeException) {
            result.error("FAILED", "Unable to request system activity", null)
        }
    }
}
