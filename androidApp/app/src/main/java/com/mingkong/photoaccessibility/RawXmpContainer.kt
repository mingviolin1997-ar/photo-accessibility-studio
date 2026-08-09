package com.mingkong.photoaccessibility

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.nio.charset.StandardCharsets
import java.util.zip.CRC32

object RawXmpContainer {
    private val jpegHeader = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(StandardCharsets.US_ASCII)
    private val pngSignature = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)
    private const val pngKeyword = "XML:com.adobe.xmp"

    enum class Format { JPEG, PNG }

    fun detect(data: ByteArray): Format = when {
        data.size >= 2 && data[0] == 0xff.toByte() && data[1] == 0xd8.toByte() -> Format.JPEG
        data.size >= 8 && data.copyOfRange(0, 8).contentEquals(pngSignature) -> Format.PNG
        else -> throw IllegalArgumentException("Android 测试版目前只安全写入 JPEG 和 PNG")
    }

    fun read(data: ByteArray): String? = when (detect(data)) {
        Format.JPEG -> readJpeg(data)
        Format.PNG -> readPng(data)
    }

    fun write(data: ByteArray, packet: String): ByteArray = when (detect(data)) {
        Format.JPEG -> writeJpeg(data, packet)
        Format.PNG -> writePng(data, packet)
    }

    private fun readJpeg(data: ByteArray): String? {
        var offset = 2
        while (offset + 4 <= data.size) {
            require(data[offset] == 0xff.toByte()) { "JPEG 标记结构无效" }
            val marker = data[offset + 1].toInt() and 0xff
            if (marker == 0xda || marker == 0xd9) return null
            if (marker in 0xd0..0xd7 || marker == 0x01) { offset += 2; continue }
            val length = unsignedShort(data, offset + 2)
            val end = offset + 2 + length
            require(length >= 2 && end <= data.size) { "JPEG 段长度无效" }
            if (marker == 0xe1 && startsWith(data, offset + 4, jpegHeader)) {
                return String(data, offset + 4 + jpegHeader.size,
                    end - offset - 4 - jpegHeader.size, StandardCharsets.UTF_8)
            }
            offset = end
        }
        return null
    }

    private fun writeJpeg(data: ByteArray, packet: String): ByteArray {
        val packetBytes = packet.toByteArray(StandardCharsets.UTF_8)
        val payloadSize = jpegHeader.size + packetBytes.size
        require(payloadSize + 2 <= 65535) { "XMP packet 超过 JPEG APP1 容量" }
        val output = ByteArrayOutputStream(data.size + payloadSize + 4)
        output.write(data, 0, 2)
        output.write(0xff); output.write(0xe1)
        output.write((payloadSize + 2) ushr 8); output.write((payloadSize + 2) and 0xff)
        output.write(jpegHeader); output.write(packetBytes)
        var offset = 2
        while (offset < data.size) {
            require(offset + 2 <= data.size && data[offset] == 0xff.toByte()) { "JPEG 标记结构无效" }
            val marker = data[offset + 1].toInt() and 0xff
            if (marker == 0xda || marker == 0xd9) {
                output.write(data, offset, data.size - offset)
                break
            }
            if (marker in 0xd0..0xd7 || marker == 0x01) {
                output.write(data, offset, 2); offset += 2; continue
            }
            require(offset + 4 <= data.size) { "JPEG 段不完整" }
            val length = unsignedShort(data, offset + 2)
            val end = offset + 2 + length
            require(length >= 2 && end <= data.size) { "JPEG 段长度无效" }
            val isXmp = marker == 0xe1 && startsWith(data, offset + 4, jpegHeader)
            if (!isXmp) output.write(data, offset, end - offset)
            offset = end
        }
        return output.toByteArray()
    }

    private fun readPng(data: ByteArray): String? {
        var offset = 8
        while (offset + 12 <= data.size) {
            val length = unsignedInt(data, offset)
            val end = offset + 12L + length
            require(length <= Int.MAX_VALUE && end <= data.size) { "PNG 块长度无效" }
            val type = String(data, offset + 4, 4, StandardCharsets.US_ASCII)
            if (type == "iTXt") parsePngXmp(data.copyOfRange(offset + 8, offset + 8 + length.toInt()))?.let { return it }
            offset = end.toInt()
            if (type == "IEND") break
        }
        return null
    }

    private fun writePng(data: ByteArray, packet: String): ByteArray {
        val output = ByteArrayOutputStream(data.size + packet.length + 64)
        output.write(pngSignature)
        var offset = 8
        while (offset + 12 <= data.size) {
            val length = unsignedInt(data, offset)
            val end = offset + 12L + length
            require(length <= Int.MAX_VALUE && end <= data.size) { "PNG 块长度无效" }
            val type = String(data, offset + 4, 4, StandardCharsets.US_ASCII)
            val chunkData = data.copyOfRange(offset + 8, offset + 8 + length.toInt())
            val isXmp = type == "iTXt" && parsePngXmp(chunkData) != null
            if (type == "IEND") writePngXmp(output, packet)
            if (!isXmp) output.write(data, offset, end.toInt() - offset)
            offset = end.toInt()
            if (type == "IEND") break
        }
        return output.toByteArray()
    }

    private fun parsePngXmp(data: ByteArray): String? {
        val keywordEnd = data.indexOf(0)
        if (keywordEnd < 0 || String(data, 0, keywordEnd, StandardCharsets.ISO_8859_1) != pngKeyword) return null
        var cursor = keywordEnd + 1
        if (cursor + 2 > data.size || data[cursor].toInt() != 0) return null
        cursor += 2
        cursor = data.indexOf(0, cursor).takeIf { it >= 0 }?.plus(1) ?: return null
        cursor = data.indexOf(0, cursor).takeIf { it >= 0 }?.plus(1) ?: return null
        return String(data, cursor, data.size - cursor, StandardCharsets.UTF_8)
    }

    private fun writePngXmp(output: ByteArrayOutputStream, packet: String) {
        val content = ByteArrayOutputStream().apply {
            write(pngKeyword.toByteArray(StandardCharsets.ISO_8859_1)); repeat(5) { write(0) }
            write(packet.toByteArray(StandardCharsets.UTF_8))
        }.toByteArray()
        val type = "iTXt".toByteArray(StandardCharsets.US_ASCII)
        DataOutputStream(output).writeInt(content.size)
        output.write(type); output.write(content)
        val crc = CRC32().apply { update(type); update(content) }.value
        DataOutputStream(output).writeInt(crc.toInt())
    }

    private fun unsignedShort(data: ByteArray, offset: Int) =
        ((data[offset].toInt() and 0xff) shl 8) or (data[offset + 1].toInt() and 0xff)

    private fun unsignedInt(data: ByteArray, offset: Int): Long =
        ((data[offset].toLong() and 0xff) shl 24) or ((data[offset + 1].toLong() and 0xff) shl 16) or
            ((data[offset + 2].toLong() and 0xff) shl 8) or (data[offset + 3].toLong() and 0xff)

    private fun startsWith(data: ByteArray, offset: Int, prefix: ByteArray): Boolean =
        offset >= 0 && offset + prefix.size <= data.size && prefix.indices.all { data[offset + it] == prefix[it] }

    private fun ByteArray.indexOf(value: Int, start: Int = 0): Int {
        for (index in start until size) if ((this[index].toInt() and 0xff) == value) return index
        return -1
    }
}
