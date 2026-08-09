package com.mingkong.photoaccessibility

import android.content.Context
import androidx.core.content.edit
import androidx.core.net.toUri
import org.json.JSONArray
import org.json.JSONObject

class QueueStore(context: Context) {
    private val preferences = context.getSharedPreferences("queue", Context.MODE_PRIVATE)

    fun load(): MutableList<PhotoJob> =
        decodeJobs(runCatching {
            JSONArray(preferences.getString("jobs", "[]"))
        }.getOrElse { JSONArray() }).onEach { job ->
            if (job.status == JobStatus.RECOGNIZING) job.status = JobStatus.WAITING
            if (job.status == JobStatus.WRITING) job.status = JobStatus.READY
        }

    fun save(jobs: List<PhotoJob>) {
        preferences.edit { putString("jobs", encodeJobs(jobs).toString()) }
    }

    fun loadHistory(
        retentionDays: Int = 30,
        now: Long = System.currentTimeMillis()
    ): MutableList<HistoryBatch> {
        val array = runCatching {
            JSONArray(preferences.getString("history", "[]"))
        }.getOrElse { JSONArray() }
        val batches = buildList {
            for (index in 0 until array.length()) runCatching {
                val item = array.getJSONObject(index)
                add(HistoryBatch(
                    id = item.getString("id"),
                    createdAt = item.getLong("createdAt"),
                    name = item.getString("name"),
                    jobs = decodeJobs(item.optJSONArray("jobs") ?: JSONArray())
                ))
            }
        }
        return retainHistory(batches, retentionDays, now)
            .filter { it.jobs.isNotEmpty() }
            .toMutableList()
    }

    fun saveHistory(batches: List<HistoryBatch>) {
        val array = JSONArray()
        batches.forEach { batch ->
            array.put(JSONObject().apply {
                put("id", batch.id)
                put("createdAt", batch.createdAt)
                put("name", batch.name)
                put("jobs", encodeJobs(batch.jobs))
            })
        }
        preferences.edit { putString("history", array.toString()) }
    }

    private fun decodeJobs(array: JSONArray): MutableList<PhotoJob> = buildList {
        for (index in 0 until array.length()) runCatching {
            val item = array.getJSONObject(index)
            val status = runCatching {
                JobStatus.valueOf(item.optString("status", JobStatus.WAITING.name))
            }.getOrDefault(JobStatus.WAITING)
            add(PhotoJob(
                id = item.getString("id"),
                uri = item.getString("uri").toUri(),
                displayName = item.getString("name"),
                mimeType = item.optString("mime").ifBlank { null },
                selectedForWriting = item.optBoolean("selected", true),
                status = status,
                description = item.optString("description"),
                error = item.optString("error").ifBlank { null }
            ))
        }
    }.toMutableList()

    private fun encodeJobs(jobs: List<PhotoJob>): JSONArray = JSONArray().apply {
        jobs.forEach { job ->
            put(JSONObject().apply {
                put("id", job.id)
                put("uri", job.uri.toString())
                put("name", job.displayName)
                put("mime", job.mimeType ?: "")
                put("selected", job.selectedForWriting)
                put("status", job.status.name)
                put("description", job.description)
                put("error", job.error ?: "")
            })
        }
    }
}
