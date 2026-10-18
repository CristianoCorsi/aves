package deckers.thibault.aves.aves_semantic

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import com.google.ai.edge.litertlm.ActivationDataType
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.EmbeddingEngine
import com.google.ai.edge.litertlm.EmbeddingEngineConfig
import com.google.ai.edge.litertlm.EmbeddingOptions
import com.google.ai.edge.litertlm.InputData
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.Executors

class AvesSemanticPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> launch(result) { load(call) }
            "unload" -> launch(result) { SemanticEngineHolder.unload(); null }
            "embedTexts" -> launch(result) { embedTexts(call) }
            "embedImages" -> launch(result) { embedImages(call) }
            "getInfo" -> launch(result) { getInfo() }
            else -> result.notImplemented()
        }
    }

    private fun launch(result: MethodChannel.Result, op: suspend () -> Any?) {
        scope.launch {
            try {
                val value = withContext(SemanticEngineHolder.dispatcher) { op() }
                result.success(value)
            } catch (e: SemanticPluginException) {
                result.error(e.code, e.message, null)
            } catch (e: Throwable) {
                Log.w(LOG_TAG, "semantic engine call failed", e)
                result.error("engine-error", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun load(call: MethodCall): Any? {
        val modelPath = call.argument<String>("modelPath") ?: throw SemanticPluginException("args", "missing model path")
        val backend = call.argument<String>("backend") ?: "auto"
        if (!File(modelPath).exists()) throw SemanticPluginException("model-missing", "no model at path=$modelPath")
        SemanticEngineHolder.configure(context, modelPath, backend)
        SemanticEngineHolder.ensureLoaded()
        return null
    }

    private fun embedTexts(call: MethodCall): List<FloatArray?> {
        val texts = call.argument<List<String>>("texts") ?: throw SemanticPluginException("args", "missing texts")
        return SemanticEngineHolder.embed(texts.map { InputData.Text(it) })
    }

    private fun embedImages(call: MethodCall): List<FloatArray?> {
        val images = call.argument<List<ByteArray>>("images") ?: throw SemanticPluginException("args", "missing images")
        return SemanticEngineHolder.embed(images.map { InputData.Image(it) })
    }

    private fun getInfo(): Map<String, Any?> {
        return hashMapOf(
            "loaded" to SemanticEngineHolder.isLoaded,
            "backend" to SemanticEngineHolder.activeBackend,
            "dimension" to SemanticEngineHolder.dimension,
            "thermalStatus" to thermalStatus(),
        )
    }

    private fun thermalStatus(): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager?
        return powerManager?.currentThermalStatus
    }

    companion object {
        private const val LOG_TAG = "AvesSemantic"
        const val CHANNEL = "deckers.thibault/aves_semantic/engine"
    }
}

class SemanticPluginException(val code: String, override val message: String?) : Exception(message)

// engine shared by all Flutter engines of the process (UI and background workers),
// as the model is too large to be loaded twice
object SemanticEngineHolder {
    private const val LOG_TAG = "AvesSemantic"
    private const val IDLE_UNLOAD_DELAY_MILLIS = 60 * 1000L

    // single thread, as the native engine is not meant to be used concurrently
    val dispatcher = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    private val idleScope = CoroutineScope(SupervisorJob() + dispatcher)
    private var idleJob: Job? = null

    private var engine: EmbeddingEngine? = null
    private var appContext: Context? = null
    private var modelPath: String? = null
    private var requestedBackend: String = "auto"

    var activeBackend: String? = null
        private set
    var dimension: Int? = null
        private set

    val isLoaded: Boolean
        get() = engine != null

    fun configure(context: Context, modelPath: String, backend: String) {
        if (this.modelPath != modelPath || requestedBackend != backend) {
            unload()
        }
        appContext = context.applicationContext
        this.modelPath = modelPath
        requestedBackend = backend
    }

    fun ensureLoaded(): EmbeddingEngine {
        engine?.let { return it }

        val context = appContext ?: throw SemanticPluginException("not-loaded", "engine is not configured")
        val path = modelPath ?: throw SemanticPluginException("not-loaded", "engine is not configured")
        val candidates = when (requestedBackend) {
            "cpu" -> listOf("cpu")
            "gpu" -> listOf("gpu", "cpu")
            "npu" -> listOf("npu", "gpu", "cpu")
            else -> listOf("gpu", "cpu")
        }

        var lastError: Throwable? = null
        for (candidate in candidates) {
            try {
                val created = EmbeddingEngine(createConfig(context, path, candidate))
                created.initialize()
                engine = created
                activeBackend = candidate
                Log.i(LOG_TAG, "loaded model=$path with backend=$candidate")
                return created
            } catch (e: Throwable) {
                Log.w(LOG_TAG, "failed to load model=$path with backend=$candidate", e)
                lastError = e
            }
        }
        throw SemanticPluginException("load-failed", lastError?.message ?: "failed to load model")
    }

    private fun createConfig(context: Context, path: String, backend: String): EmbeddingEngineConfig {
        val cacheDir = File(context.cacheDir, "semantic").apply { mkdirs() }.path
        val mainBackend = when (backend) {
            "gpu" -> Backend.GPU()
            "npu" -> Backend.NPU(context.applicationInfo.nativeLibraryDir)
            else -> Backend.CPU()
        }
        return EmbeddingEngineConfig(
            modelPath = path,
            backend = mainBackend,
            visionBackend = mainBackend,
            cacheDir = cacheDir,
            // GPU default activations (float16) are reported to corrupt embeddings
            activationDataType = if (backend == "gpu") ActivationDataType.FLOAT32 else null,
        )
    }

    fun embed(contents: List<InputData>): List<FloatArray?> {
        val loaded = ensureLoaded()
        val options = EmbeddingOptions(normalize = true)
        val vectors = try {
            loaded.computeEmbeddingBatch(contents.map { listOf(it) }, options).map { response -> response.embedding as FloatArray? }
        } catch (e: Throwable) {
            // retry one by one, so that a single invalid input does not fail the whole batch
            Log.w(LOG_TAG, "batch embedding failed, retrying one by one", e)
            contents.map { content ->
                try {
                    loaded.computeEmbedding(listOf(content), options).embedding
                } catch (e: Throwable) {
                    Log.w(LOG_TAG, "embedding failed for input type=${content.javaClass.simpleName}", e)
                    null
                }
            }
        }
        vectors.firstNotNullOfOrNull { it }?.let { dimension = it.size }
        scheduleIdleUnload()
        return vectors
    }

    private fun scheduleIdleUnload() {
        idleJob?.cancel()
        idleJob = idleScope.launch {
            delay(IDLE_UNLOAD_DELAY_MILLIS)
            Log.i(LOG_TAG, "unload model after idle delay")
            unload()
        }
    }

    fun unload() {
        idleJob?.cancel()
        idleJob = null
        try {
            engine?.close()
        } catch (e: Throwable) {
            Log.w(LOG_TAG, "failed to close engine", e)
        }
        engine = null
        activeBackend = null
    }
}
