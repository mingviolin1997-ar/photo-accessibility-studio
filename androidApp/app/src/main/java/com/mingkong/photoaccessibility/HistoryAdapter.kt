package com.mingkong.photoaccessibility

import android.graphics.Typeface
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView

class HistoryAdapter(
    private val onDeleteBatch: (String) -> Unit,
    private val onDeleteItem: (String, String) -> Unit
) : ListAdapter<HistoryBatch, HistoryAdapter.HistoryHolder>(Diff) {
    private val expandedIds = mutableSetOf<String>()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): HistoryHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_history_batch, parent, false)
        return HistoryHolder(view)
    }

    override fun onBindViewHolder(holder: HistoryHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class HistoryHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val toggle = view.findViewById<Button>(R.id.historyBatchToggle)
        private val details = view.findViewById<LinearLayout>(R.id.historyBatchDetails)
        private val deleteBatch = view.findViewById<Button>(R.id.deleteHistoryBatchButton)

        fun bind(batch: HistoryBatch) {
            val expanded = batch.id in expandedIds
            toggle.text = itemView.context.getString(
                R.string.history_batch_count,
                batch.name,
                batch.jobs.size
            )
            toggle.contentDescription = "历史批次 " + batch.name + "，包含 " +
                batch.jobs.size + " 张照片，" + if (expanded) "已展开" else "已折叠"
            details.visibility = if (expanded) View.VISIBLE else View.GONE
            deleteBatch.visibility = if (expanded) View.VISIBLE else View.GONE
            toggle.setOnClickListener {
                if (!expandedIds.add(batch.id)) expandedIds.remove(batch.id)
                val position = bindingAdapterPosition
                if (position != RecyclerView.NO_POSITION) notifyItemChanged(position)
            }

            details.removeAllViews()
            batch.jobs.forEach { job ->
                details.addView(historyJobView(batch, job))
            }
            deleteBatch.contentDescription =
                "删除历史批次 " + batch.name + "，不删除手机媒体库中的照片"
            deleteBatch.setOnClickListener { onDeleteBatch(batch.id) }
        }

        private fun historyJobView(batch: HistoryBatch, job: PhotoJob): View {
            val context = itemView.context
            val padding = (12 * context.resources.displayMetrics.density).toInt()
            return LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(padding, padding, padding, padding)
                addView(TextView(context).apply {
                    text = job.displayName
                    setTypeface(typeface, Typeface.BOLD)
                })
                addView(TextView(context).apply {
                    text = job.description
                    contentDescription = job.displayName + " 的无障碍描述：" + job.description
                })
                addView(Button(context).apply {
                    text = context.getString(R.string.delete_history_item)
                    minHeight = (48 * context.resources.displayMetrics.density).toInt()
                    contentDescription =
                        "删除 " + job.displayName + " 的历史记录，不删除手机媒体库中的照片"
                    setOnClickListener { onDeleteItem(batch.id, job.id) }
                })
            }
        }
    }

    private object Diff : DiffUtil.ItemCallback<HistoryBatch>() {
        override fun areItemsTheSame(oldItem: HistoryBatch, newItem: HistoryBatch) =
            oldItem.id == newItem.id

        override fun areContentsTheSame(oldItem: HistoryBatch, newItem: HistoryBatch) =
            oldItem == newItem
    }
}
