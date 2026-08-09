package com.mingkong.photoaccessibility

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.util.UUID
import kotlin.math.max

data class PreparedModelImage(
    val file: File,
    val width: Int,
    val height: Int,
    val byteCount: Long
)

class ImagePreprocessor(
    private val resolver: ContentResolver,
    private val cacheDirectory: File,
    private val maximumDimension: Int = 1280
) {
    fun prepare(uri: Uri): PreparedModelImage {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            ?: error("无法读取照片")
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "设备无法解码这种照片格式" }

        var sample = 1
        while (max(bounds.outWidth / sample, bounds.outHeight / sample) > maximumDimension * 2) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
            ?: error("设备无法解码照片像素")
        val rotated = applyOrientation(decoded, readOrientation(uri))
        val scale = (maximumDimension.toFloat() / max(rotated.width, rotated.height)).coerceAtMost(1f)
        val resized = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                rotated,
                (rotated.width * scale).toInt().coerceAtLeast(1),
                (rotated.height * scale).toInt().coerceAtLeast(1),
                true
            )
        } else rotated

        val directory = File(cacheDirectory, "vision-input").apply { mkdirs() }
        val file = File(directory, "${UUID.randomUUID()}.jpg")
        try {
            file.outputStream().buffered().use { output ->
                require(resized.compress(Bitmap.CompressFormat.JPEG, 82, output)) {
                    "无法为本地模型生成节能输入图像"
                }
            }
            return PreparedModelImage(file, resized.width, resized.height, file.length())
        } finally {
            if (resized !== rotated) resized.recycle()
            if (rotated !== decoded) rotated.recycle()
            decoded.recycle()
        }
    }

    private fun readOrientation(uri: Uri): Int = runCatching {
        resolver.openInputStream(uri)?.use { input ->
            ExifInterface(input).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
        } ?: ExifInterface.ORIENTATION_NORMAL
    }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

    private fun applyOrientation(bitmap: Bitmap, orientation: Int): Bitmap {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }
}
