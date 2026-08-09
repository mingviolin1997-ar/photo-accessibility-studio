package com.mingkong.photoaccessibility

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Button
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
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {
    private val viewModel: MainViewModel by viewModels()
    private lateinit var adapter: PhotoAdapter
    private var setupDialogShowing = false
    private var lastStatus = ""
    private var lastModelAnnouncement = ""
    private var lastDownloadBucket = -1

    private val photoPicker = registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        uris.forEach { uri -> runCatching { contentResolver.takePersistableUriPermission(uri, flags) } }
        viewModel.addPhotos(uris)
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
            onRemove = viewModel::remove
        )
        findViewById<RecyclerView>(R.id.photoList).apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = this@MainActivity.adapter
        }
    }

    private fun configureControls() {
        listOf(R.id.appHeading, R.id.modelHeading, R.id.styleHeading,
            R.id.batchHeading, R.id.queueHeading).forEach { id ->
            ViewCompat.setAccessibilityHeading(findViewById(id), true)
        }
        findViewById<Button>(R.id.checkModelButton).setOnClickListener { viewModel.requestModelSetup() }
        findViewById<Button>(R.id.addPhotosButton).setOnClickListener { photoPicker.launch(arrayOf("image/*")) }
        findViewById<Button>(R.id.selectAllButton).setOnClickListener { viewModel.selectAll(true) }
        findViewById<Button>(R.id.deselectAllButton).setOnClickListener { viewModel.selectAll(false) }
        findViewById<Button>(R.id.recognizeButton).setOnClickListener { viewModel.startRecognition() }
        findViewById<Button>(R.id.writeSelectedButton).setOnClickListener { viewModel.writeSelected() }
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
        findViewById<Button>(R.id.recognizeButton).isEnabled =
            state.modelReady && !state.busy && !state.downloadingModel &&
                state.jobs.any { it.status == JobStatus.WAITING || it.status == JobStatus.FAILED }
        findViewById<Button>(R.id.writeSelectedButton).isEnabled = !state.busy &&
            state.jobs.any { it.selectedForWriting && it.description.isNotBlank() }
        findViewById<Button>(R.id.checkModelButton).isEnabled = !state.downloadingModel

        val targetRadio = radioFor(state.style)
        val group = findViewById<RadioGroup>(R.id.styleGroup)
        if (group.checkedRadioButtonId != targetRadio) group.check(targetRadio)
        findViewById<MaterialSwitch>(R.id.adviceSwitch).apply {
            if (isChecked != state.includeAdvice) isChecked = state.includeAdvice
        }
        findViewById<MaterialSwitch>(R.id.autoWriteSwitch).apply {
            if (isChecked != state.autoWrite) isChecked = state.autoWrite
        }
        if (state.setupPromptPending && !setupDialogShowing) showSetupDialog()
    }

    private fun showSetupDialog() {
        setupDialogShowing = true
        viewModel.setupPromptDisplayed()
        MaterialAlertDialogBuilder(this)
            .setTitle("自动下载并配置本地模型？")
            .setMessage(
                "LiteRT-LM 推理环境已随应用提供，但本机还没有 Qwen3.5 4B 多模态模型。" +
                    "是否现在从 Hugging Face 下载固定版本？下载约 5.26GB，支持断点续传，" +
                    "完成后会核对 SHA-256。建议连接 Wi-Fi，并预留至少 6GB 空间。"
            )
            .setPositiveButton("下载并自动配置") { _, _ -> viewModel.downloadAndLoadModel() }
            .setNegativeButton("暂不下载") { _, _ -> viewModel.declineSetup() }
            .setOnDismissListener { setupDialogShowing = false }
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
