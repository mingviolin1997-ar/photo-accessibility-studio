package com.mingkong.photoaccessibility

import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.RadioGroup
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.materialswitch.MaterialSwitch
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {
    private val viewModel: MainViewModel by viewModels()
    private lateinit var adapter: PhotoAdapter
    private lateinit var historyAdapter: HistoryAdapter
    private var setupDialogShowing = false
    private var engineDialogShowing = false
    private var modelDialogShowing = false
    private var historyExpanded = false
    private var focusedJobId: String? = null
    private var lastStatus = ""
    private var lastModelAnnouncement = ""
    private var lastDownloadBucket = -1
    private val progressSoundPlayer = ProgressSoundPlayer()
    private var soundJob: Job? = null
    private var halfwaySoundPlayed = false
    private var wasBusy = false

    private val photoPicker = registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        uris.forEach { uri -> runCatching { contentResolver.takePersistableUriPermission(uri, flags) } }
        viewModel.addPhotos(uris)
    }

    private val exportFolderPicker = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            runCatching {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            }
            viewModel.exportAll(uri)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        configureQueue()
        configureControls()
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.state.collect(::render)
            }
        }
    }

    private fun configureQueue() {
        adapter = PhotoAdapter(
            onSelected = viewModel::setSelected,
            onDescription = viewModel::setDescription,
            onWrite = viewModel::writeOne,
            onRemove = viewModel::remove,
            onFocused = { focusedJobId = it }
        )
        findViewById<RecyclerView>(R.id.photoList).apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = this@MainActivity.adapter
        }
        historyAdapter = HistoryAdapter(
            onDeleteBatch = viewModel::deleteHistoryBatch,
            onDeleteItem = viewModel::deleteHistoryItem
        )
        findViewById<RecyclerView>(R.id.historyList).apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = historyAdapter
        }
    }

    private fun configureControls() {
        listOf(R.id.appHeading, R.id.modelHeading, R.id.styleHeading,
            R.id.batchHeading, R.id.queueHeading, R.id.historyToggleButton).forEach { id ->
            ViewCompat.setAccessibilityHeading(findViewById(id), true)
        }
        findViewById<Button>(R.id.chooseEngineButton).setOnClickListener {
            viewModel.requestEngineChoice()
        }
        findViewById<Button>(R.id.chooseModelButton).setOnClickListener {
            viewModel.requestModelChoice()
        }
        findViewById<Button>(R.id.checkModelButton).setOnClickListener { viewModel.requestModelSetup() }
        findViewById<Button>(R.id.deleteModelButton).setOnClickListener { showDeleteModelDialog() }
        findViewById<Button>(R.id.addPhotosButton).setOnClickListener { photoPicker.launch(arrayOf("image/*")) }
        findViewById<Button>(R.id.selectAllButton).setOnClickListener { viewModel.selectAll(true) }
        findViewById<Button>(R.id.deselectAllButton).setOnClickListener { viewModel.selectAll(false) }
        findViewById<Button>(R.id.recognizeButton).setOnClickListener { viewModel.startRecognition() }
        findViewById<Button>(R.id.writeSelectedButton).setOnClickListener { viewModel.writeSelected() }
        findViewById<Button>(R.id.exportAllButton).setOnClickListener { exportFolderPicker.launch(null) }
        findViewById<Button>(R.id.clearCurrentButton).setOnClickListener {
            focusedJobId = null
            viewModel.clearCurrent()
        }
        findViewById<Button>(R.id.historyToggleButton).setOnClickListener {
            historyExpanded = !historyExpanded
            render(viewModel.state.value)
        }
        findViewById<Button>(R.id.clearHistoryButton).setOnClickListener {
            viewModel.clearHistory()
        }
        findViewById<Button>(R.id.historyRetentionButton).setOnClickListener {
            showHistoryRetentionDialog()
        }
        findViewById<RadioGroup>(R.id.styleGroup).setOnCheckedChangeListener { _, id ->
            styleFor(id)?.let(viewModel::setStyle)
        }
        findViewById<MaterialSwitch>(R.id.adviceSwitch).setOnCheckedChangeListener { _, value ->
            viewModel.setIncludeAdvice(value)
        }
        findViewById<MaterialSwitch>(R.id.autoWriteSwitch).setOnCheckedChangeListener { _, value ->
            viewModel.setAutoWrite(value)
        }
    }

    private fun render(state: MainUiState) {
        adapter.submitList(state.jobs)
        historyAdapter.submitList(state.history)
        if (focusedJobId != null && state.jobs.none { it.id == focusedJobId }) {
            focusedJobId = null
        }
        findViewById<TextView>(R.id.queueHeading).text =
            getString(R.string.queue_count, state.jobs.size)
        val statusView = findViewById<TextView>(R.id.statusText)
        statusView.text = state.status
        if (state.status != lastStatus) {
            statusView.announceForAccessibility(state.status)
            lastStatus = state.status
        }

        val modelStatus = findViewById<TextView>(R.id.modelStatusText)
        modelStatus.text = state.modelStatus
        if (state.modelStatus != lastModelAnnouncement && !state.downloadingModel) {
            modelStatus.announceForAccessibility(state.modelStatus)
            lastModelAnnouncement = state.modelStatus
        }
        findViewById<TextView>(R.id.activeEngineText).text =
            getString(R.string.active_engine_format, state.activeEngineLabel)
        findViewById<Button>(R.id.chooseEngineButton).apply {
            text = "推理引擎：${state.selectedEngine.displayName}"
            contentDescription = "$text。点击切换；${state.selectedEngine.description}"
            isEnabled = !state.busy && !state.downloadingModel
        }
        findViewById<Button>(R.id.chooseModelButton).apply {
            val installed = if (state.selectedModel in state.installedModels) "，已安装" else "，未安装"
            text = "视觉模型：${state.selectedModel.displayName}$installed"
            contentDescription = "$text。点击查看模型说明并切换"
            isEnabled = !state.busy && !state.downloadingModel
        }

        val modelProgress = findViewById<ProgressBar>(R.id.modelProgressBar)
        val modelProgressText = findViewById<TextView>(R.id.modelProgressText)
        val showModelProgress = state.downloadingModel || state.modelProgress == 100
        modelProgress.visibility = if (showModelProgress) View.VISIBLE else View.GONE
        modelProgressText.visibility = if (showModelProgress) View.VISIBLE else View.GONE
        modelProgress.progress = state.modelProgress
        modelProgress.contentDescription = "模型配置进度百分之 ${state.modelProgress}"
        modelProgressText.text = state.modelProgressText
        val bucket = state.modelProgress / 10
        if (state.downloadingModel && bucket > lastDownloadBucket) {
            modelProgressText.announceForAccessibility("模型下载进度百分之 ${state.modelProgress}")
            lastDownloadBucket = bucket
        }

        findViewById<ProgressBar>(R.id.progressBar).progress = state.progress
        updateProgressSounds(state)
        findViewById<Button>(R.id.recognizeButton).isEnabled =
            state.modelReady && !state.busy && !state.downloadingModel &&
                state.jobs.any { it.status == JobStatus.WAITING || it.status == JobStatus.FAILED }
        findViewById<Button>(R.id.writeSelectedButton).isEnabled = !state.busy &&
            state.jobs.any { it.selectedForWriting && it.description.isNotBlank() }
        findViewById<Button>(R.id.exportAllButton).isEnabled = !state.busy &&
            state.jobs.any { it.description.isNotBlank() }
        findViewById<Button>(R.id.checkModelButton).apply {
            text = "下载或检查当前模型（${state.selectedModel.downloadSize}）"
            isEnabled = !state.downloadingModel && !state.busy
        }
        findViewById<Button>(R.id.deleteModelButton).apply {
            text = "移除 ${state.selectedModel.displayName} 以释放空间"
            isEnabled = state.selectedModel in state.installedModels &&
                !state.downloadingModel && !state.busy
        }
        findViewById<Button>(R.id.clearCurrentButton).isEnabled =
            state.jobs.isNotEmpty() && !state.busy
        val historyCount = state.history.sumOf { it.jobs.size }
        findViewById<Button>(R.id.historyToggleButton).apply {
            text = "历史记录：$historyCount 张，${if (historyExpanded) "已展开" else "已折叠"}"
            contentDescription = text
        }
        findViewById<View>(R.id.historyPanel).visibility =
            if (historyExpanded) View.VISIBLE else View.GONE
        findViewById<Button>(R.id.clearHistoryButton).isEnabled = state.history.isNotEmpty()
        findViewById<Button>(R.id.historyRetentionButton).apply {
            text = "历史默认保留 ${state.historyRetentionDays} 天"
            contentDescription = "历史记录保留期 ${state.historyRetentionDays} 天，点击可调整"
        }

        val targetRadio = radioFor(state.style)
        val group = findViewById<RadioGroup>(R.id.styleGroup)
        if (group.checkedRadioButtonId != targetRadio) group.check(targetRadio)
        findViewById<MaterialSwitch>(R.id.adviceSwitch).apply {
            if (isChecked != state.includeAdvice) isChecked = state.includeAdvice
        }
        findViewById<MaterialSwitch>(R.id.autoWriteSwitch).apply {
            if (isChecked != state.autoWrite) isChecked = state.autoWrite
        }
        when {
            state.engineChoicePending && !engineDialogShowing -> showEngineDialog()
            state.modelChoicePending && !modelDialogShowing -> showModelDialog()
            state.setupPromptPending && !setupDialogShowing &&
                !engineDialogShowing && !modelDialogShowing -> showSetupDialog()
        }
    }

    private fun updateProgressSounds(state: MainUiState) {
        if (state.busy && !state.downloadingModel && soundJob == null) {
            halfwaySoundPlayed = state.progress >= 50
            soundJob = lifecycleScope.launch {
                while (isActive && viewModel.state.value.busy &&
                    !viewModel.state.value.downloadingModel
                ) {
                    val progress = viewModel.state.value.progress
                    if (!halfwaySoundPlayed && progress >= 50) {
                        progressSoundPlayer.playHalfway()
                        halfwaySoundPlayed = true
                    } else {
                        progressSoundPlayer.playProgress(progress)
                    }
                    delay(1_000)
                }
            }
        } else if (!state.busy && soundJob != null) {
            soundJob?.cancel()
            soundJob = null
        }
        if (wasBusy && !state.busy && state.progress >= 100) {
            progressSoundPlayer.playComplete()
        }
        wasBusy = state.busy
    }

    override fun onDestroy() {
        soundJob?.cancel()
        progressSoundPlayer.close()
        super.onDestroy()
    }

    private fun showHistoryRetentionDialog() {
        val days = intArrayOf(7, 30, 90, 365)
        val labels = arrayOf("7 天", "30 天", "90 天", "365 天")
        val current = days.indexOf(viewModel.state.value.historyRetentionDays)
        MaterialAlertDialogBuilder(this)
            .setTitle("选择历史保留时间")
            .setSingleChoiceItems(labels, current) { dialog, which ->
                viewModel.setHistoryRetentionDays(days[which])
                dialog.dismiss()
            }
            .setNegativeButton("取消", null)
            .show()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if ((keyCode == KeyEvent.KEYCODE_DEL || keyCode == KeyEvent.KEYCODE_FORWARD_DEL) &&
            event.isMetaPressed
        ) {
            val id = focusedJobId
                ?: viewModel.state.value.jobs.firstOrNull { it.selectedForWriting }?.id
            if (id != null) {
                viewModel.remove(id)
                focusedJobId = null
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun showSetupDialog() {
        setupDialogShowing = true
        viewModel.setupPromptDisplayed()
        val model = viewModel.state.value.selectedModel
        val tokenInput = if (model.requiresHuggingFaceToken) {
            EditText(this).apply {
                hint = "Hugging Face 读取令牌"
                contentDescription = "Hugging Face 读取令牌；只用于本次下载，不会保存"
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
                setPadding(48, 20, 48, 20)
            }
        } else null
        val licenseNote = if (model.requiresHuggingFaceToken) {
            "此 Google 模型仓库受 Gemma 许可保护。请先在 Hugging Face 模型页面接受许可，再在下方输入具有读取权限的令牌；令牌只用于本次下载，不会保存。"
        } else {
            "此模型无需账号或密钥。"
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("下载并自动配置 ${model.displayName}？")
            .setMessage(
                "LiteRT-LM 已随应用提供。本机还没有 ${model.displayName}，下载量${model.downloadSize}，" +
                    "支持断点续传，完成后会核对固定版本、文件长度和 SHA-256。" +
                    "建议使用 Wi-Fi 并额外预留至少 768MB 校验空间。\n\n" +
                    "${model.recommendation}\n\n$licenseNote"
            )
            .apply { if (tokenInput != null) setView(tokenInput) }
            .setPositiveButton("下载并自动配置") { _, _ ->
                viewModel.downloadAndLoadModel(tokenInput?.text?.toString())
            }
            .setNegativeButton("暂不下载") { _, _ -> viewModel.declineSetup() }
            .setOnDismissListener { setupDialogShowing = false }
            .show()
    }

    private fun showEngineDialog() {
        engineDialogShowing = true
        viewModel.engineChoiceDisplayed()
        val engines = InferenceEngine.entries
        val labels = engines.map { "${it.displayName}。${it.description}" }.toTypedArray()
        val selected = engines.indexOf(viewModel.state.value.selectedEngine)
        MaterialAlertDialogBuilder(this)
            .setTitle("选择 Android 推理引擎")
            .setSingleChoiceItems(labels, selected) { dialog, which ->
                viewModel.chooseEngine(engines[which])
                dialog.dismiss()
            }
            .setNegativeButton("取消", null)
            .setOnDismissListener { engineDialogShowing = false }
            .show()
    }

    private fun showModelDialog() {
        modelDialogShowing = true
        viewModel.modelChoiceDisplayed()
        val state = viewModel.state.value
        val models = VisionModel.entries
        val labels = models.map { model ->
            val installed = if (model in state.installedModels) "已安装。" else "未安装。"
            "$installed ${model.selectionLabel}"
        }.toTypedArray()
        val selected = models.indexOf(state.selectedModel)
        MaterialAlertDialogBuilder(this)
            .setTitle("选择本地视觉模型")
            .setSingleChoiceItems(labels, selected) { dialog, which ->
                viewModel.chooseModel(models[which])
                dialog.dismiss()
            }
            .setNegativeButton("取消", null)
            .setOnDismissListener { modelDialogShowing = false }
            .show()
    }

    private fun showDeleteModelDialog() {
        val model = viewModel.state.value.selectedModel
        MaterialAlertDialogBuilder(this)
            .setTitle("移除 ${model.displayName}？")
            .setMessage("只删除应用管理的模型文件，不删除照片、描述或历史记录。以后可以重新下载。")
            .setPositiveButton("移除模型") { _, _ -> viewModel.deleteSelectedModel() }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun styleFor(id: Int): DescriptionStyle? = when (id) {
        R.id.styleLow -> DescriptionStyle.LOW
        R.id.styleMedium -> DescriptionStyle.MEDIUM
        R.id.styleHigh -> DescriptionStyle.HIGH
        R.id.stylePhotographer -> DescriptionStyle.PHOTOGRAPHER
        else -> null
    }

    private fun radioFor(style: DescriptionStyle): Int = when (style) {
        DescriptionStyle.LOW -> R.id.styleLow
        DescriptionStyle.MEDIUM -> R.id.styleMedium
        DescriptionStyle.HIGH -> R.id.styleHigh
        DescriptionStyle.PHOTOGRAPHER -> R.id.stylePhotographer
    }
}
