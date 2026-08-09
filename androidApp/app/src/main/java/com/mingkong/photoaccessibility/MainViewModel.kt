package com.mingkong.photoaccessibility

import android.app.Application
import android.net.Uri
import android.graphics.BitmapFactory
import android.provider.OpenableColumns
import androidx.exifinterface.media.ExifInterface
import androidx.documentfile.provider.DocumentFile
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.core.content.edit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val resolver = application.contentResolver
    private val queueStore = QueueStore(application)
    private val settings = application.getSharedPreferences("settings", 0)
    private val downloader = ModelDownloader(application)
    private val metadataWriter = ImageMetadataWriter(resolver)
    private val runtime = LiteRtVisionRuntime(resolver, application.cacheDir)
    private val engineDiagnostic = LiteRtEngineDiagnostics.inspect()
    private var modelDownloadJob: Job? = null
    private val historyRetentionDays =
        settings.getInt("historyRetentionDays", 30).coerceIn(1, 365)
    private val restoredJobs = queueStore.load()
    private val history = queueStore.loadHistory(historyRetentionDays).apply {
        val described = restoredJobs.filter { it.description.isNotBlank() }.map { it.copy() }
        if (described.isNotEmpty()) add(0, HistoryBatch(jobs = described))
        val retained = retainHistory(this, historyRetentionDays)
        clear()
        addAll(retained)
    }
    private val jobs = mutableListOf<PhotoJob>()

    private val storedEngine = InferenceEngine.stored(
        settings.getString("selectedInferenceEngine", null)
    )
    private val initialEngine = storedEngine ?: InferenceEngine.LITERT_SMART
    private val initialModel = VisionModel.stored(settings.getString("selectedVisionModel", null))

    private val initialStyle = runCatching {
        DescriptionStyle.valueOf(settings.getString("style", DescriptionStyle.MEDIUM.name)!!)
    }.getOrDefault(DescriptionStyle.MEDIUM)
    private val _state = MutableStateFlow(MainUiState(
        jobs = snapshot(),
        history = historySnapshot(),
        style = initialStyle,
        includeAdvice = settings.getBoolean("includeAdvice", false),
        autoWrite = settings.getBoolean("autoWrite", true),
        historyRetentionDays = historyRetentionDays,
        selectedEngine = initialEngine,
        selectedModel = initialModel,
        installedModels = downloader.installedModels(),
        engineReady = engineDiagnostic.ready,
        engineDiagnostic = engineDiagnostic.message
    ))
    val state: StateFlow<MainUiState> = _state.asStateFlow()

    init {
        queueStore.save(jobs)
        queueStore.saveHistory(history)
        when {
            !engineDiagnostic.ready -> _state.update {
                it.copy(
                    modelStatus = "内置推理引擎自检失败：${engineDiagnostic.message}",
                    activeEngineLabel = "不可用"
                )
            }
            storedEngine == null -> _state.update {
                it.copy(
                    modelStatus = "首次使用，请先选择 LiteRT-LM 智能加速或 CPU 兼容模式。",
                    engineChoicePending = true
                )
            }
            downloader.isReady(initialModel) -> loadDownloadedModel()
            else -> _state.update {
                val lastFailure = settings.getString("lastModelDownloadFailure", null)
                it.copy(
                    modelStatus = if (lastFailure.isNullOrBlank()) {
                        "LiteRT-LM 引擎已内置；尚未下载 ${initialModel.displayName}。"
                    } else {
                        "上次模型下载失败：$lastFailure。可以重新尝试并断点续传。"
                    },
                    setupPromptPending = true
                )
            }
        }
    }

    fun engineChoiceDisplayed() = _state.update { it.copy(engineChoicePending = false) }
    fun modelChoiceDisplayed() = _state.update { it.copy(modelChoicePending = false) }
    fun setupPromptDisplayed() = _state.update { it.copy(setupPromptPending = false) }

    fun declineSetup() = _state.update {
        it.copy(modelStatus = "已暂不下载 ${it.selectedModel.displayName}；需要时可按“下载或检查当前模型”。")
    }

    fun requestEngineChoice() {
        if (_state.value.busy || _state.value.downloadingModel || !_state.value.engineReady) return
        _state.update { it.copy(engineChoicePending = true) }
    }

    fun requestModelChoice() {
        if (_state.value.busy || _state.value.downloadingModel) return
        _state.update { it.copy(modelChoicePending = true) }
    }

    fun chooseEngine(selected: InferenceEngine) {
        if (_state.value.busy || _state.value.downloadingModel || !_state.value.engineReady) return
        settings.edit { putString("selectedInferenceEngine", selected.name) }
        _state.update {
            it.copy(
                selectedEngine = selected,
                modelReady = false,
                activeEngineLabel = "正在切换",
                modelStatus = "已选择 ${selected.displayName}；正在检查当前模型。"
            )
        }
        viewModelScope.launch {
            withContext(Dispatchers.IO) { runtime.close() }
            if (downloader.isReady(_state.value.selectedModel)) loadDownloadedModel()
            else _state.update { it.copy(setupPromptPending = true) }
        }
    }

    fun chooseModel(selected: VisionModel) {
        if (_state.value.busy || _state.value.downloadingModel) return
        settings.edit { putString("selectedVisionModel", selected.name) }
        _state.update {
            it.copy(
                selectedModel = selected,
                modelReady = false,
                activeEngineLabel = "正在切换",
                modelProgress = 0,
                modelProgressText = "",
                modelStatus = "已选择 ${selected.displayName}；正在检查本地安装。"
            )
        }
        viewModelScope.launch {
            withContext(Dispatchers.IO) { runtime.close() }
            if (downloader.isReady(selected)) loadDownloadedModel()
            else _state.update {
                it.copy(
                    installedModels = downloader.installedModels(),
                    modelStatus = "本机尚未安装 ${selected.displayName}。",
                    setupPromptPending = true
                )
            }
        }
    }

    fun requestModelSetup() {
        if (!_state.value.engineReady) {
            _state.update {
                it.copy(modelStatus = "无法配置模型：${it.engineDiagnostic}")
            }
            return
        }
        val model = _state.value.selectedModel
        if (downloader.isReady(model)) loadDownloadedModel()
        else _state.update { it.copy(setupPromptPending = true) }
    }

    fun downloadAndLoadModel(huggingFaceToken: String? = null) {
        if (_state.value.downloadingModel || !_state.value.engineReady) return
        val model = _state.value.selectedModel
        _state.update {
            it.copy(downloadingModel = true, modelDownloadCancelable = true, modelReady = false,
                modelStatus = "准备下载固定版本 ${model.displayName}。")
        }
        modelDownloadJob?.cancel()
        modelDownloadJob = viewModelScope.launch {
            try {
                val file = downloader.download(model, huggingFaceToken) { progress ->
                    _state.update { current -> current.copy(
                        modelProgress = progress.percent,
                        modelProgressText = DownloadText.progress(progress),
                        modelStatus = progress.currentStep
                    ) }
                }
                loadModel(file, model, _state.value.selectedEngine)
            } catch (cancelled: CancellationException) {
                _state.update { it.copy(
                    downloadingModel = false,
                    modelDownloadCancelable = false,
                    modelReady = false,
                    installedModels = downloader.installedModels(),
                    modelProgressText = "下载已取消。已经完成的数据仍保留；再次点击下载即可断点续传。",
                    modelStatus = "已取消 ${model.displayName} 下载；可随时继续。"
                ) }
            } catch (error: Throwable) {
                val reason = error.message ?: error.javaClass.simpleName
                settings.edit { putString("lastModelDownloadFailure", reason) }
                _state.update { it.copy(
                    downloadingModel = false,
                    modelDownloadCancelable = false,
                    modelReady = false,
                    installedModels = downloader.installedModels(),
                    modelProgressText = "失败原因：$reason。已下载部分会保留；检查网络、权限或空间后点击重试。",
                    modelStatus = "自动配置失败：$reason"
                ) }
            }
            modelDownloadJob = null
        }
    }

    fun cancelModelDownload() {
        if (!_state.value.modelDownloadCancelable) return
        _state.update {
            it.copy(modelStatus = "正在停止模型下载；已经完成的数据会保留。")
        }
        modelDownloadJob?.cancel()
    }

    fun deleteSelectedModel() {
        if (_state.value.busy || _state.value.downloadingModel) return
        val model = _state.value.selectedModel
        viewModelScope.launch {
            _state.update { it.copy(downloadingModel = true, modelReady = false,
                modelStatus = "正在移除 ${model.displayName}。") }
            withContext(Dispatchers.IO) { runtime.close() }
            val deleted = withContext(Dispatchers.IO) { downloader.delete(model) }
            _state.update { it.copy(
                downloadingModel = false,
                installedModels = downloader.installedModels(),
                activeEngineLabel = "尚未加载",
                modelStatus = if (deleted) {
                    "已移除 ${model.displayName}；可随时重新下载。"
                } else {
                    "无法完整移除 ${model.displayName}，请重试。"
                }
            ) }
        }
    }

    fun addPhotos(uris: List<Uri>) {
        val existing = jobs.map { it.uri }.toSet()
        val newUris = uris.filterNot { it in existing }
        if (newUris.isEmpty()) {
            publish("所选照片已经在当前工作区中。")
            return
        }
        _state.update { it.copy(status = "正在读取 ${newUris.size} 张照片的格式和拍摄时间。") }
        viewModelScope.launch {
            val imported = withContext(Dispatchers.IO) {
                newUris.map { uri ->
                    val metadata = photoMetadata(uri)
                    PhotoJob(
                        uri = uri,
                        displayName = displayName(uri),
                        mimeType = resolver.getType(uri),
                        captureTime = metadata.captureTime,
                        pixelWidth = metadata.width,
                        pixelHeight = metadata.height
                    )
                }
            }
            jobs += imported
            publish("已添加 ${imported.size} 张照片。")
        }
    }

    fun selectAll(value: Boolean) {
        jobs.forEach { it.selectedForWriting = value }
        publish(if (value) "已选择全部照片用于写入。" else "已取消选择全部照片。")
    }

    fun setStyle(style: DescriptionStyle) {
        settings.edit { putString("style", style.name) }
        _state.update { it.copy(style = style) }
    }

    fun setIncludeAdvice(value: Boolean) {
        settings.edit { putBoolean("includeAdvice", value) }
        _state.update { it.copy(includeAdvice = value) }
    }

    fun setAutoWrite(value: Boolean) {
        settings.edit { putBoolean("autoWrite", value) }
        _state.update { it.copy(autoWrite = value) }
    }

    fun setSelected(id: String, value: Boolean) = mutate(id) { it.selectedForWriting = value }
    fun setDescription(id: String, value: String) = mutate(id) { it.description = value }

    fun remove(id: String) {
        if (_state.value.busy) return
        jobs.firstOrNull { it.id == id }?.let { archive(listOf(it)) }
        jobs.removeAll { it.id == id }
        publish("已从当前工作区移除素材和对应结果；有描述的项目已进入历史，手机媒体库中的原照片未删除。")
    }

    fun clearCurrent() {
        if (_state.value.busy || jobs.isEmpty()) return
        val count = jobs.size
        archive(jobs)
        jobs.clear()
        publish("已清空当前工作区的 $count 项；有描述的项目已进入历史，手机媒体库中的照片未删除。", 0)
    }

    fun clearHistory() {
        history.clear()
        publish("已清空软件历史记录；手机媒体库中的照片和导出文件未删除。")
    }

    fun deleteHistoryBatch(id: String) {
        history.removeAll { it.id == id }
        publish("已删除所选历史批次；手机媒体库中的照片未删除。")
    }

    fun deleteHistoryItem(batchId: String, jobId: String) {
        val index = history.indexOfFirst { it.id == batchId }
        if (index < 0) return
        val batch = history[index]
        val remaining = batch.jobs.filterNot { it.id == jobId }
        if (remaining.isEmpty()) history.removeAt(index)
        else history[index] = batch.copy(jobs = remaining)
        publish("已删除所选历史记录；手机媒体库中的照片未删除。")
    }

    fun setHistoryRetentionDays(days: Int) {
        val safeDays = days.coerceIn(1, 365)
        settings.edit { putInt("historyRetentionDays", safeDays) }
        val retained = retainHistory(history, safeDays)
        val removed = history.sumOf { it.jobs.size } - retained.sumOf { it.jobs.size }
        history.clear()
        history.addAll(retained)
        publish(if (removed > 0) {
            "已清理 $removed 条超过 $safeDays 天的软件历史记录；手机媒体库中的照片未删除。"
        } else {
            "历史记录保留期已设为 $safeDays 天。"
        })
        _state.update { it.copy(historyRetentionDays = safeDays) }
    }

    fun startRecognition() {
        if (!_state.value.modelReady) {
            requestModelSetup()
            return
        }
        if (_state.value.busy) return
        val ids = jobs.filter { it.status == JobStatus.WAITING || it.status == JobStatus.FAILED }.map { it.id }
        if (ids.isEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(busy = true, progress = 0) }
            ids.forEachIndexed { index, id ->
                val job = jobs.firstOrNull { it.id == id } ?: return@forEachIndexed
                job.status = JobStatus.RECOGNIZING
                job.error = null
                publish("正在识别第 ${index + 1} 张，共 ${ids.size} 张", index * 100 / ids.size)
                try {
                    job.description = runtime.describe(
                        job.uri,
                        _state.value.style,
                        _state.value.includeAdvice
                    ) { stage ->
                        _state.update { it.copy(status = "第 ${index + 1} 张：$stage") }
                    }
                    job.status = JobStatus.READY
                    if (_state.value.autoWrite && job.selectedForWriting) write(job)
                } catch (error: Throwable) {
                    job.status = JobStatus.FAILED
                    job.error = error.message ?: error.javaClass.simpleName
                }
                publish("已处理 ${index + 1}/${ids.size}", (index + 1) * 100 / ids.size)
            }
            _state.update { it.copy(busy = false, status = summary()) }
        }
    }

    fun writeSelected() {
        val ids = jobs.filter {
            it.selectedForWriting && it.description.isNotBlank() && it.status != JobStatus.COMPLETED
        }.map { it.id }
        writeIds(ids)
    }

    fun writeOne(id: String) = writeIds(listOf(id))

    fun exportAll(destinationTree: Uri) {
        if (_state.value.busy) return
        val candidates = jobs.filter { it.description.isNotBlank() }.map { it.copy() }
        if (candidates.isEmpty()) {
            publish("没有可导出的描述结果。")
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(busy = true, progress = 0, status = "正在准备批量导出。") }
            var succeeded = 0
            var failed = 0
            val root = DocumentFile.fromTreeUri(getApplication(), destinationTree)
            if (root == null || !root.canWrite()) {
                _state.update { it.copy(busy = false, status = "所选文件夹不可写，请重新选择。") }
                return@launch
            }
            candidates.forEachIndexed { index, job ->
                var destination: DocumentFile? = null
                try {
                    val (mime, extension) = exportFormat(job.mimeType)
                    val created = withContext(Dispatchers.IO) {
                        root.createFile(mime, "${index + 1}.$extension")
                            ?: error("无法在所选文件夹创建第 ${index + 1} 张照片")
                    }
                    destination = created
                    withContext(Dispatchers.IO) {
                        resolver.openInputStream(job.uri)?.use { input ->
                            resolver.openOutputStream(created.uri, "wt")?.use { output ->
                                input.copyTo(output)
                                output.flush()
                            } ?: error("无法写入导出文件")
                        } ?: error("无法读取原照片")
                        metadataWriter.write(created.uri, job.description)
                    }
                    succeeded += 1
                } catch (error: Throwable) {
                    withContext(Dispatchers.IO) { runCatching { destination?.delete() } }
                    failed += 1
                }
                _state.update { it.copy(
                    progress = (index + 1) * 100 / candidates.size,
                    status = "已导出并验证 ${index + 1}/${candidates.size}"
                ) }
            }
            _state.update { it.copy(
                busy = false,
                status = "批量导出完成：成功 $succeeded 张，失败 $failed 张。导出文件按 1、2、3 编号。"
            ) }
        }
    }

    private fun writeIds(ids: List<String>) {
        if (ids.isEmpty() || _state.value.busy) return
        viewModelScope.launch {
            _state.update { it.copy(busy = true, progress = 0) }
            ids.forEachIndexed { index, id ->
                val job = jobs.firstOrNull { it.id == id } ?: return@forEachIndexed
                try {
                    write(job)
                } catch (error: Throwable) {
                    job.status = JobStatus.FAILED
                    job.error = error.message ?: error.javaClass.simpleName
                }
                publish("已写入 ${index + 1}/${ids.size}", (index + 1) * 100 / ids.size)
            }
            _state.update { it.copy(busy = false, status = summary()) }
        }
    }

    private suspend fun write(job: PhotoJob) {
        job.status = JobStatus.WRITING
        job.error = null
        publish("正在写入并自动验证${itemNumber(job)}")
        withContext(Dispatchers.IO) { metadataWriter.write(job.uri, job.description) }
        job.status = JobStatus.COMPLETED
    }

    private fun loadDownloadedModel() {
        if (_state.value.downloadingModel || _state.value.modelReady) return
        val model = _state.value.selectedModel
        val inferenceEngine = _state.value.selectedEngine
        _state.update { it.copy(
            downloadingModel = true,
            modelDownloadCancelable = false,
            modelStatus = "正在用 ${inferenceEngine.displayName} 加载 ${model.displayName}。"
        ) }
        viewModelScope.launch {
            try { loadModel(downloader.modelFile(model), model, inferenceEngine) }
            catch (error: Throwable) {
                _state.update { it.copy(downloadingModel = false, modelReady = false,
                    modelDownloadCancelable = false,
                    modelStatus = "本地模型加载失败：${error.message ?: error.javaClass.simpleName}") }
            }
        }
    }

    private suspend fun loadModel(
        file: java.io.File,
        model: VisionModel,
        inferenceEngine: InferenceEngine
    ) {
        val result = runtime.load(file, model, inferenceEngine)
        settings.edit { remove("lastModelDownloadFailure") }
        _state.update { it.copy(
            downloadingModel = false,
            modelDownloadCancelable = false,
            modelReady = true,
            installedModels = downloader.installedModels(),
            activeEngineLabel = result.activeEngineLabel,
            modelProgress = 100,
            modelProgressText = "${model.displayName} 已下载、校验并加载。",
            modelStatus = "${model.displayName} 与 ${result.activeEngineLabel} 已就绪；照片仅在本机处理。"
        ) }
    }

    private fun mutate(id: String, block: (PhotoJob) -> Unit) {
        jobs.firstOrNull { it.id == id }?.let(block)
        publish()
    }

    private fun publish(message: String? = null, progress: Int? = null) {
        queueStore.save(jobs)
        queueStore.saveHistory(history)
        _state.update { current -> current.copy(
            jobs = snapshot(),
            history = historySnapshot(),
            status = message ?: current.status,
            progress = progress ?: current.progress
        ) }
    }

    private fun snapshot() = jobs.map { it.copy() }

    private fun historySnapshot() = history.map { batch ->
        batch.copy(jobs = batch.jobs.map { it.copy() })
    }

    private fun archive(candidates: List<PhotoJob>) {
        val described = candidates.filter { it.description.isNotBlank() }.map { it.copy() }
        if (described.isEmpty()) return
        history.add(0, HistoryBatch(jobs = described))
        val days = _state.value.historyRetentionDays
        val retained = retainHistory(history, days)
        history.clear()
        history.addAll(retained)
    }

    private fun summary(): String {
        val complete = jobs.count { it.status == JobStatus.COMPLETED }
        val ready = jobs.count { it.status == JobStatus.READY }
        val failed = jobs.count { it.status == JobStatus.FAILED }
        return "批处理完成：已写入并验证 $complete 张，待写入 $ready 张，失败 $failed 张。"
    }

    private fun displayName(uri: Uri): String {
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        return name ?: uri.lastPathSegment ?: "未命名照片"
    }

    private fun itemNumber(job: PhotoJob): String {
        val index = jobs.indexOfFirst { it.id == job.id }
        return if (index >= 0) "第 ${index + 1} 张照片" else "当前照片"
    }

    private fun exportFormat(mimeType: String?): Pair<String, String> = when (mimeType) {
        "image/jpeg", "image/jpg" -> "image/jpeg" to "jpg"
        "image/png" -> "image/png" to "png"
        else -> error("当前只能无损注入 JPEG 或 PNG；未在未获同意时转换照片格式")
    }

    private data class PhotoMetadata(
        val captureTime: String?,
        val width: Int?,
        val height: Int?
    )

    private fun photoMetadata(uri: Uri): PhotoMetadata {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        runCatching {
            resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        }
        val captureTime = runCatching {
            resolver.openInputStream(uri)?.use { input ->
                val exif = ExifInterface(input)
                (exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                    ?: exif.getAttribute(ExifInterface.TAG_DATETIME))?.let(::readableExifDate)
            }
        }.getOrNull()
        return PhotoMetadata(
            captureTime = captureTime,
            width = bounds.outWidth.takeIf { it > 0 },
            height = bounds.outHeight.takeIf { it > 0 }
        )
    }

    private fun readableExifDate(value: String): String {
        val match = Regex("^(\\d{4}):(\\d{2}):(\\d{2})(.*)$").find(value) ?: return value
        return "${match.groupValues[1]}-${match.groupValues[2]}-${match.groupValues[3]}${match.groupValues[4]}"
    }

    override fun onCleared() {
        runtime.close()
        super.onCleared()
    }
}
