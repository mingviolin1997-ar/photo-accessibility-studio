package com.mingkong.photoaccessibility

import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView

class PhotoAdapter(
    private val onSelected: (String, Boolean) -> Unit,
    private val onDescription: (String, String) -> Unit,
    private val onWrite: (String) -> Unit,
    private val onRemove: (String) -> Unit,
    private val onFocused: (String) -> Unit
) : ListAdapter<PhotoJob, PhotoAdapter.JobHolder>(Diff) {
    private val expandedEditors = mutableSetOf<String>()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): JobHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_photo, parent, false)
        return JobHolder(view)
    }

    override fun onBindViewHolder(holder: JobHolder, position: Int) =
        holder.bind(getItem(position), position + 1)

    inner class JobHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val selected = view.findViewById<CheckBox>(R.id.writeCheckBox)
        private val status = view.findViewById<TextView>(R.id.jobStatus)
        private val details = view.findViewById<TextView>(R.id.photoDetails)
        private val description = view.findViewById<TextView>(R.id.descriptionText)
        private val edit = view.findViewById<Button>(R.id.editDescriptionButton)
        private val editor = view.findViewById<EditText>(R.id.descriptionEditor)
        private val write = view.findViewById<Button>(R.id.writeOneButton)
        private val remove = view.findViewById<Button>(R.id.removeButton)
        private var watcher: TextWatcher? = null

        fun bind(job: PhotoJob, number: Int) {
            val itemLabel = "第 $number 张照片"
            itemView.isFocusable = true
            itemView.setOnFocusChangeListener { _, focused ->
                if (focused) onFocused(job.id)
            }
            itemView.setOnClickListener { onFocused(job.id) }
            selected.setOnCheckedChangeListener(null)
            selected.text = itemLabel
            selected.isChecked = job.selectedForWriting
            selected.contentDescription = "$itemLabel，是否写入描述"
            selected.setOnCheckedChangeListener { _, value ->
                onFocused(job.id)
                onSelected(job.id, value)
            }

            status.text = buildString {
                append(job.status.label)
                job.error?.let { append("：").append(it) }
            }
            status.contentDescription = "$itemLabel 当前状态：${status.text}"

            details.text = buildString {
                append("格式：").append(job.mimeType ?: "未知")
                if (job.pixelWidth != null && job.pixelHeight != null) {
                    append("；尺寸：").append(job.pixelWidth).append(" 乘 ").append(job.pixelHeight)
                }
                append("；拍摄时间：").append(job.captureTime ?: "照片中没有可读取的拍摄时间")
            }
            details.contentDescription = "$itemLabel 详细信息：${details.text}"

            description.text = job.description.ifBlank { "尚未生成无障碍描述。" }
            description.contentDescription = "$itemLabel 的无障碍描述：${description.text}"
            val expanded = job.id in expandedEditors
            editor.visibility = if (expanded) View.VISIBLE else View.GONE
            edit.text = if (expanded) "收起编辑框" else "编辑描述"
            edit.contentDescription = "$itemLabel，${edit.text}"
            edit.isEnabled = job.description.isNotBlank()
            edit.setOnClickListener {
                onFocused(job.id)
                if (job.id in expandedEditors) expandedEditors.remove(job.id)
                else expandedEditors.add(job.id)
                val position = bindingAdapterPosition
                if (position != RecyclerView.NO_POSITION) notifyItemChanged(position)
            }

            watcher?.let(editor::removeTextChangedListener)
            if (editor.text.toString() != job.description) editor.setText(job.description)
            editor.hint = "$itemLabel 的无障碍描述，可在写入前修改"
            editor.setOnFocusChangeListener { _, focused ->
                if (focused) onFocused(job.id)
            }
            watcher = object : TextWatcher {
                override fun beforeTextChanged(value: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(value: CharSequence?, start: Int, before: Int, count: Int) {
                    onDescription(job.id, value?.toString().orEmpty())
                }
                override fun afterTextChanged(value: Editable?) = Unit
            }.also(editor::addTextChangedListener)

            write.isEnabled = job.description.isNotBlank() && job.status != JobStatus.WRITING
            write.contentDescription = "只把描述写入${itemLabel}并自动验证"
            write.setOnClickListener {
                onFocused(job.id)
                onWrite(job.id)
            }
            remove.contentDescription = "从队列移除$itemLabel，不删除原照片"
            remove.isEnabled =
                job.status != JobStatus.RECOGNIZING && job.status != JobStatus.WRITING
            remove.setOnClickListener {
                onFocused(job.id)
                onRemove(job.id)
            }
        }
    }

    private object Diff : DiffUtil.ItemCallback<PhotoJob>() {
        override fun areItemsTheSame(oldItem: PhotoJob, newItem: PhotoJob) = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: PhotoJob, newItem: PhotoJob) = oldItem == newItem
    }
}
