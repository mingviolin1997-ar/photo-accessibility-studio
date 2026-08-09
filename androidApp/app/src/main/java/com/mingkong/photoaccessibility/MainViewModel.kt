package com.mingkong.photoaccessibility

import android.app.Application
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.core.content.edit
import kotlinx.coroutines.Dispatchers
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
    private val jobs = queueStore.load()

    private val initialStyle = runCatching {
        DescriptionStyle.valueOf(settings.getString("style", DescriptionStyle.MEDIUM.name)!!)
    }.getOrDefault(DescriptionStyle.MEDIUM)
    private val _state = MutableStateFlow(MainUiState(
        jobs = snapshot(),
        style = initialStyle,
        includeAdvice = settings.getBoolean("includeAdvice", false),
        autoWrite = settings.getBoolean("autoWrite", true)
    ))
    val state: StateFlow<MainUiState> = _state.asStateFlow()

    init {
        if (downloader.isReady()) loadDownloadedModel()
        else _state.update {
            it.copy(
                modelStatus = "LiteRT-LM 已内置；尚未下载 Qwen3.5 4B 多模态模型。",
                setupPromptPending = true
            )
        }
    }

    fun setupPromptDisplayed() = _state.update { it.copy(setupPromptPending = false) }

    fun declineSetup() = _state.update {
        it.copy(modelStatus = "已暂不下载。需要时可按“下载或检查本地模型”。")
    }

    fun requestModelSetup() {
        if (downloader.isReady()) loadDownloadedModel()
        else _state.update { it.copy(setupPromptPending = true) }
    }

    fun downloadAndLoadModel() {
        if (_state.value.downloadingModel) return
        _state.update {
            it.copy(downloadingModel = true, modelReady = false,
                modelStatus = "准备下载固定版本 Qwen3.5 4B 模型。")
        }
        viewModelScope.launch {
            try {
                val file = downloader.download { progress ->
                    _state.update { current -> current.copy(
                        modelProgress = progress.percent,
                        modelProgressText = DownloadText.progress(progress),
                        modelStatus = progress.currentStep
                    ) }
                }
                loadModel(file)
            } catch (error: Throwable) {
                _state.update { it.copy(
                    downloadingModel = false,
                    modelReady = false,
                    modelStatus = "自动配置失败：${error.message ?: error.javaClass.simpleName}"
                ) }
            }
        }
    }

    fun addPhotos(uris: List<Uri>) {
        val existing = jobs.map { it.uri }.toSet()
        uris.filterNot { it in existing }.forEach { uri ->
            jobs += PhotoJob(
                uri = uri,
                displayName = displayName(uri),
                mimeType = resolver.getType(uri)
            )
        }
        publish("已添加 ${uris.count { it !in existing }} 张照片。")
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
        jobs.removeAll { it.id == id }
        publish("已从队列移除；原照片未删除。")
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
                publish("正在识别第 ${index + 1} 张，共 ${ids.size} 张：${job.displayName}", index * 100 / ids.size)
                try {
                    job.description = runtime.describe(job.uri, _state.value.style, _state.value.includeAdvice)
                    job.status = JobStatus.READY
                    if (_state.value.autoWrite && job.selectedForWriting) write(job)
                } catch (error: Throwable) {
                    job.status = JobStatus.FAILED
                    job.error = error.message ?: error.javaClass.simpleName
                }
                publish("已处理 ${index + 1}/${ids.size}：${job.displayName}", (index + 1) * 100 / ids.size)
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
                publish("已写入 ${index + 1}/${ids.size}：${job.displayName}", (index + 1) * 100 / ids.size)
            }
            _state.update { it.copy(busy = false, status = summary()) }
        }
    }

    private suspend fun write(job: PhotoJob) {
        job.status = JobStatus.WRITING
        job.error = null
        publish("正在写入并自动验证：${job.displayName}")
        withContext(Dispatchers.IO) { metadataWriter.write(job.uri, job.description) }
        job.status = JobStatus.COMPLETED
    }

    private fun loadDownloadedModel() {
        if (_state.value.downloadingModel || _state.value.modelReady) return
        _state.update { it.copy(downloadingModel = true, modelStatus = "正在加载 LiteRT-LM 与 Qwen3.5 4B。") }
        viewModelScope.launch {
            try { loadModel(downloader.modelFile) }
            catch (error: Throwable) {
                _state.update { it.copy(downloadingModel = false, modelReady = false,
                    modelStatus = "本地模型加载失败：${error.message ?: error.javaClass.simpleName}") }
            }
        }
    }

    private suspend fun loadModel(file: java.io.File) {
        runtime.load(file)
        _state.update { it.copy(
            downloadingModel = false,
            modelReady = true,
            modelProgress = 100,
            modelProgressText = "Qwen3.5 4B 已下载、校验并由 LiteRT-LM 加载。",
            modelStatus = "Qwen3.5 4B 与 LiteRT-LM 已就绪；照片仅在本机处理。"
        ) }
    }

    private fun mutate(id: String, block: (PhotoJob) -> Unit) {
        jobs.firstOrNull { it.id == id }?.let(block)
        publish()
    }

    private fun publish(message: String? = null, progress: Int? = null) {
        queueStore.save(jobs)
        _state.update { current -> current.copy(
            jobs = snapshot(),
            status = message ?: current.status,
            progress = progress ?: current.progress
        ) }
    }

    private fun snapshot() = jobs.map { it.copy() }

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

    override fun onCleared() {
        runtime.close()
        super.onCleared()
    }
}
