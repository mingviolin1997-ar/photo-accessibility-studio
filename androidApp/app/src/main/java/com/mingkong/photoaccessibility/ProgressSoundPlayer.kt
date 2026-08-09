package com.mingkong.photoaccessibility

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.sin

class ProgressSoundPlayer : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()

    fun playProgress(percent: Int) {
        val frequency = 320.0 + percent.coerceIn(0, 100) * 4.2
        enqueue(listOf(frequency to 70))
    }

    fun playHalfway() {
        enqueue(listOf(520.0 to 70, 0.0 to 50, 690.0 to 90))
    }

    fun playComplete() {
        enqueue(listOf(660.0 to 90, 820.0 to 90, 990.0 to 150))
    }

    private fun enqueue(notes: List<Pair<Double, Int>>) {
        runCatching { executor.execute {
            runCatching {
            val sampleRate = 16_000
            val samples = buildList<Short> {
                notes.forEach { (frequency, milliseconds) ->
                    val count = sampleRate * milliseconds / 1000
                    repeat(count) { index ->
                        val envelope = when {
                            index < 80 -> index / 80.0
                            count - index < 80 -> (count - index) / 80.0
                            else -> 1.0
                        }.coerceIn(0.0, 1.0)
                        val value = if (frequency <= 0) 0.0 else
                            sin(2.0 * PI * frequency * index / sampleRate) * 0.10 * envelope
                        add((value * Short.MAX_VALUE).toInt().toShort())
                    }
                }
            }.toShortArray()
            val track = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build())
                .setAudioFormat(AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build())
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(samples.size * 2)
                .build()
            try {
                track.write(samples, 0, samples.size)
                track.play()
                Thread.sleep(notes.sumOf { it.second }.toLong() + 30)
            } finally {
                track.release()
            }
            }
        } }
    }

    override fun close() {
        executor.shutdownNow()
    }
}
