package com.mingkong.photoaccessibility

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.nio.charset.StandardCharsets
import java.util.zip.CRC32

class RawXmpContainerTest {
    @Test fun injectsAndReplacesRawJpegPacketWithoutChangingImageBytes() {
        val original = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 0xd9.toByte())
        val first = XmpPacketBuilder.build(null, "第一条描述")
        val second = XmpPacketBuilder.build(first, "第二条描述")

        val written = RawXmpContainer.write(original, first)
        val replaced = RawXmpContainer.write(written, second)

        assertEquals("第二条描述", XmpPacketBuilder.extract(RawXmpContainer.read(replaced)!!))
        assertArrayEquals(original.copyOfRange(2, 4), replaced.copyOfRange(replaced.size - 2, replaced.size))
    }

    @Test fun injectsRawPngPacketBeforeIend() {
        val original = pngWithOnlyIend()
        val packet = XmpPacketBuilder.build(null, "PNG 描述")
        val written = RawXmpContainer.write(original, packet)

        assertEquals("PNG 描述", XmpPacketBuilder.extract(RawXmpContainer.read(written)!!))
        assertArrayEquals(original.copyOfRange(original.size - 12, original.size),
            written.copyOfRange(written.size - 12, written.size))
    }

    private fun pngWithOnlyIend(): ByteArray {
        val output = ByteArrayOutputStream()
        output.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
        val type = "IEND".toByteArray(StandardCharsets.US_ASCII)
        DataOutputStream(output).writeInt(0)
        output.write(type)
        DataOutputStream(output).writeInt(CRC32().apply { update(type) }.value.toInt())
        return output.toByteArray()
    }
}
