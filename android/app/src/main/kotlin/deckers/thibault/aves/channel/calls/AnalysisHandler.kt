package deckers.thibault.aves.channel.calls

import android.app.ActivityManager
import android.content.Context
import android.content.ContextWrapper
import android.util.Log
import androidx.core.app.ComponentActivity
import androidx.core.content.edit
import androidx.lifecycle.LifecycleOwner
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequest
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.workDataOf
import deckers.thibault.aves.AnalysisWorker
import deckers.thibault.aves.utils.FlutterUtils
import deckers.thibault.aves.utils.LogUtils
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.util.concurrent.TimeUnit
import kotlin.math.max

class AnalysisHandler<T>(private val activity: T, private val onAnalysisCompleted: () -> Unit) : MethodChannel.MethodCallHandler
        where T : ContextWrapper,
              T : LifecycleOwner {
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "registerCallback" -> ioScope.launch { Coresult.safe(call, result, ::registerCallback) }
            "startAnalysis" -> Coresult.safe(call, result, ::startAnalysis)
            "scheduleSemanticIndexing" -> Coresult.safe(call, result, ::scheduleSemanticIndexing)
            else -> result.notImplemented()
        }
    }

    private fun registerCallback(call: MethodCall, result: MethodChannel.Result) {
        val callbackHandle = call.argument<Number>("callbackHandle")?.toLong()
        if (callbackHandle == null) {
            result.error("registerCallback-args", "missing arguments", null)
            return
        }

        val preferences = activity.getSharedPreferences(AnalysisWorker.SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
        preferences.edit {
            putLong(AnalysisWorker.PREF_CALLBACK_HANDLE_KEY, callbackHandle)
        }
        result.success(true)
    }

    private fun startAnalysis(call: MethodCall, result: MethodChannel.Result) {
        val force = call.argument<Boolean>("force")
        if (force == null) {
            result.error("startAnalysis-args", "missing arguments", null)
            return
        }

        val activityManager = activity.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val runningAppProcesses = activityManager?.runningAppProcesses
        if (runningAppProcesses != null) {
            val importance = runningAppProcesses[0].importance
            if (importance < ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) {
                // the app is in the background
                result.error("startAnalysis-background", "app is in the background (process importance=$importance)", null)
                return
            }
        }

        // can be null or empty
        val allEntryIds = call.argument<List<Int>>("entryIds")

        // work `Data` cannot occupy more than 10240 bytes when serialized
        // so we save the possibly long list of entry IDs to shared preferences
        val preferences = activity.getSharedPreferences(AnalysisWorker.SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
        preferences.edit {
            putStringSet(AnalysisWorker.PREF_ENTRY_IDS_KEY, allEntryIds?.map { it.toString() }?.toSet())
        }

        val workData = workDataOf(
            AnalysisWorker.KEY_FORCE to force,
        )

        WorkManager.getInstance(activity).beginUniqueWork(
            ANALYSIS_WORK_NAME,
            ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<AnalysisWorker>().apply { setInputData(workData) }.build(),
        ).enqueue()

        attachToActivity()
        result.success(null)
    }

    // periodic background analysis, mainly for semantic indexing
    private fun scheduleSemanticIndexing(call: MethodCall, result: MethodChannel.Result) {
        val mode = call.argument<String>("mode")
        val requireIdle = call.argument<Boolean>("requireIdle") ?: true
        val intervalMinutes = call.argument<Number>("intervalMinutes")?.toLong() ?: DEFAULT_PERIODIC_INTERVAL_MINUTES

        val workManager = WorkManager.getInstance(activity)
        if (mode == null || mode == "off") {
            workManager.cancelUniqueWork(PERIODIC_ANALYSIS_WORK_NAME)
            result.success(null)
            return
        }

        val constraints = Constraints.Builder()
            .setRequiresBatteryNotLow(true)
            .setRequiresCharging(mode == "whileCharging")
            .setRequiresDeviceIdle(requireIdle)
            .build()
        val workData = workDataOf(
            AnalysisWorker.KEY_FORCE to false,
            AnalysisWorker.KEY_PERIODIC to true,
        )
        val request = PeriodicWorkRequestBuilder<AnalysisWorker>(
            max(intervalMinutes, PeriodicWorkRequest.MIN_PERIODIC_INTERVAL_MILLIS / 60000), TimeUnit.MINUTES,
        ).setConstraints(constraints).setInputData(workData).build()
        workManager.enqueueUniquePeriodicWork(PERIODIC_ANALYSIS_WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
        Log.i(LOG_TAG, "Scheduled periodic analysis with mode=$mode requireIdle=$requireIdle interval=${intervalMinutes}min")
        result.success(null)
    }

    private var attached = false

    fun attachToActivity() {
        if (!attached) {
            attached = true
            WorkManager.getInstance(activity).getWorkInfosForUniqueWorkLiveData(ANALYSIS_WORK_NAME).observe(activity) { list ->
                if (list.any { it.state == WorkInfo.State.SUCCEEDED }) {
                    Log.i(LOG_TAG, "Analysis work succeeded for IDs=${list.map { it.id }}")
                    runBlocking {
                        FlutterUtils.runOnUiThread {
                            onAnalysisCompleted()
                        }
                    }
                }
            }
        }
    }

    companion object {
        private val LOG_TAG = LogUtils.createTag<AnalysisHandler<ComponentActivity>>()
        const val CHANNEL = "deckers.thibault/aves/analysis"
        private const val ANALYSIS_WORK_NAME = "analysis_work"
        private const val PERIODIC_ANALYSIS_WORK_NAME = "periodic_analysis_work"
        private const val DEFAULT_PERIODIC_INTERVAL_MINUTES = 60L
    }
}
