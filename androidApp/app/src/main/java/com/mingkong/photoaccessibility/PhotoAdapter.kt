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

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): JobHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_photo, parent, false)
        return JobHolder(view)
    }

    override fun onBindViewHolder(holder: JobHolder, position: Int) = holder.bind(getItem(position))

    inner class JobHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val selected = view.findViewById<CheckBox>(R.id.writeCheckBox)
        private val status = view.findViewById<TextView>(R.id.jobStatus)
        private val editor = view.findViewById<EditText>(R.id.descriptionEditor)
        private val write = view.findViewById<Button>(R.id.writeOneButton)
        private val remove = view.findViewById<Button>(R.id.removeButton)
        private var watcher: TextWatcher? = null

        fun bind(job: PhotoJob) {
            itemView.isFocusable = true
            itemView.setOnFocusChangeListener { _, focused ->
                if (focused) onFocused(job.id)
            }
            itemView.setOnClickListener { onFocused(job.id) }
            selected.setOnCheckedChangeListener(null)
            selected.text = job.displayName
            selected.isChecked = job.selectedForWriting
            selected.contentDescription = "是否写入照片 ${job.displayName}"
            selected.setOnCheckedChangeListener { _, value ->
                onFocused(job.id)
                onSelected(job.id, value)
            }

            status.text = buildString {
                append(job.status.label)
                job.error?.let { append("：").append(it) }
            }
            status.contentDescription = "${job.displayName} 当前状态：${status.text}"

            watcher?.let(editor::removeTextChangedListener)
            if (editor.text.toString() != job.description) editor.setText(job.description)
            editor.hint = "${job.displayName} 的无障碍描述，可在写入前修改"
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
            write.contentDescription = "只把描述写入 ${job.displayName} 并自动验证"
            write.setOnClickListener {
                onFocused(job.id)
                onWrite(job.id)
            }
            remove.contentDescription = "从队列移除 ${job.displayName}，不删除原照片"
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
