package com.mingkong.photoaccessibility

import android.graphics.BitmapFactory
import java.nio.ByteBuffer
import java.security.MessageDigest

data class ImageIntegrity(val width: Int, val height: Int, val pixelDigest: String)

object ImageIntegrityChecker {
    fun snapshot(data: ByteArray): ImageIntegrity {
        val options = BitmapFactory.Options().apply { inPreferredConfig = android.graphics.Bitmap.Config.ARGB_8888 }
        val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size, options)
            ?: throw IllegalArgumentException("无法解码照片像素")
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            val row = IntArray(bitmap.width)
            val buffer = ByteBuffer.allocate(bitmap.width * 4)
            for (y in 0 until bitmap.height) {
                bitmap.getPixels(row, 0, bitmap.width, 0, y, bitmap.width, 1)
                buffer.clear()
                row.forEach { buffer.putInt(it) }
                digest.update(buffer.array())
            }
            ImageIntegrity(bitmap.width, bitmap.height, digest.digest().joinToString("") { "%02x".format(it) })
        } finally {
            bitmap.recycle()
        }
    }
}
