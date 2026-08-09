package com.mingkong.photoaccessibility

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns

data class MetadataWriteResult(val description: String, val integrity: ImageIntegrity)

class ImageMetadataWriter(private val resolver: ContentResolver) {
    companion object { private const val MAX_BYTES = 80 * 1024 * 1024 }

    fun readDescription(uri: Uri): String? {
        val raw = RawXmpContainer.read(readBytes(uri)) ?: return null
        return XmpPacketBuilder.extract(raw)
    }

    fun write(uri: Uri, description: String): MetadataWriteResult {
        val normalized = description.trim().split(Regex("\\s+")).joinToString(" ")
        require(normalized.isNotEmpty()) { "描述不能为空" }
        val originalName = displayName(uri)
        val original = readBytes(uri)
        require(original.size <= MAX_BYTES) { "单张照片超过 80MB，已跳过以保护设备内存" }
        val before = ImageIntegrityChecker.snapshot(original)
        val existing = RawXmpContainer.read(original)
        val packet = XmpPacketBuilder.build(existing, normalized)
        val modified = RawXmpContainer.write(original, packet)
        verifyBytes(modified, normalized, before)

        var sourceChanged = false
        try {
            overwrite(uri, modified)
            sourceChanged = true
            val finalBytes = readBytes(uri)
            require(displayName(uri) == originalName) { "文件名发生变化" }
            val finalIntegrity = verifyBytes(finalBytes, normalized, before)
            return MetadataWriteResult(normalized, finalIntegrity)
        } catch (error: Throwable) {
            if (sourceChanged) {
                try { overwrite(uri, original) }
                catch (recovery: Throwable) {
                    throw IllegalStateException("写入验证失败且原图恢复失败：${recovery.localizedMessage}", error)
                }
            }
            throw error
        }
    }

    private fun verifyBytes(data: ByteArray, expected: String, before: ImageIntegrity): ImageIntegrity {
        val raw = RawXmpContainer.read(data) ?: error("写入后缺少原始 XMP packet")
        XmpPacketBuilder.validate(raw, expected)
        require(XmpPacketBuilder.extract(raw) == expected) { "描述字段回读不一致" }
        val after = ImageIntegrityChecker.snapshot(data)
        require(after == before) { "照片尺寸或解码像素发生变化" }
        return after
    }

    private fun readBytes(uri: Uri): ByteArray = resolver.openInputStream(uri)?.use { it.readBytes() }
        ?: error("无法读取照片")

    private fun overwrite(uri: Uri, data: ByteArray) {
        resolver.openOutputStream(uri, "wt")?.use { output -> output.write(data); output.flush() }
            ?: error("照片提供方没有授予写入权限")
    }

    private fun displayName(uri: Uri): String {
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        return name ?: uri.lastPathSegment.orEmpty()
    }
}
