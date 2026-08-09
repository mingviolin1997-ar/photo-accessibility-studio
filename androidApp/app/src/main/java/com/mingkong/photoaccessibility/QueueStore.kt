package com.mingkong.photoaccessibility

import android.content.Context
import androidx.core.content.edit
import androidx.core.net.toUri
import org.json.JSONArray
import org.json.JSONObject

class QueueStore(context: Context) {
    private val preferences = context.getSharedPreferences("queue", Context.MODE_PRIVATE)

    fun load(): MutableList<PhotoJob> {
        val array = runCatching { JSONArray(preferences.getString("jobs", "[]")) }.getOrElse { JSONArray() }
        return buildList {
            for (index in 0 until array.length()) runCatching {
                val item = array.getJSONObject(index)
                var status = JobStatus.valueOf(item.optString("status", JobStatus.WAITING.name))
                if (status == JobStatus.RECOGNIZING) status = JobStatus.WAITING
                if (status == JobStatus.WRITING) status = JobStatus.READY
                add(PhotoJob(
                    id = item.getString("id"), uri = item.getString("uri").toUri(),
                    displayName = item.getString("name"), mimeType = item.optString("mime").ifBlank { null },
                    selectedForWriting = item.optBoolean("selected", true), status = status,
                    description = item.optString("description"), error = item.optString("error").ifBlank { null }
                ))
            }
        }.toMutableList()
    }

    fun save(jobs: List<PhotoJob>) {
        val array = JSONArray()
        jobs.forEach { job ->
            array.put(JSONObject().apply {
                put("id", job.id); put("uri", job.uri.toString()); put("name", job.displayName)
                put("mime", job.mimeType ?: ""); put("selected", job.selectedForWriting)
                put("status", job.status.name); put("description", job.description); put("error", job.error ?: "")
            })
        }
        preferences.edit { putString("jobs", array.toString()) }
    }
}
