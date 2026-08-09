package com.mingkong.photoaccessibility

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class XmpPacketBuilderTest {
    @Test fun createsExactlyOneFlatPreviewField() {
        val value = "一张照片，白色小狗站在蓝色门旁。"
        val packet = XmpPacketBuilder.build(null, value)

        assertEquals(value, XmpPacketBuilder.extract(packet))
        assertTrue(packet.contains("<Iptc4xmpExt:ArtworkContentDescription>"))
        assertTrue(packet.contains(XmpPacketBuilder.namespace))
        assertFalse(packet.contains("Iptc4xmpExt:AOContentDescription"))
    }

    @Test fun replacesNestedAndExistingDescriptions() {
        val old = """<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:Iptc4xmpExt="${XmpPacketBuilder.namespace}"><Iptc4xmpExt:ArtworkContentDescription>旧描述</Iptc4xmpExt:ArtworkContentDescription><Iptc4xmpExt:AOContentDescription>错误字段</Iptc4xmpExt:AOContentDescription></rdf:Description></rdf:RDF></x:xmpmeta>"""
        val packet = XmpPacketBuilder.build(old, "新描述")

        XmpPacketBuilder.validate(packet, "新描述")
        assertFalse(packet.contains("旧描述"))
        assertFalse(packet.contains("AOContentDescription"))
    }

    @Test fun insertsIntoTopLevelDescriptionWithoutDamagingNestedLightroomMetadata() {
        val existing = """<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:Iptc4xmpExt='old'><Iptc4xmpExt:ArtworkOrObject><rdf:Bag><rdf:li><rdf:Description><Iptc4xmpExt:AOContentDescription>错误嵌套描述</Iptc4xmpExt:AOContentDescription></rdf:Description></rdf:li></rdf:Bag></Iptc4xmpExt:ArtworkOrObject><dc:creator xmlns:dc="http://purl.org/dc/elements/1.1/"><rdf:Seq><rdf:li>保留作者</rdf:li></rdf:Seq></dc:creator></rdf:Description></rdf:RDF></x:xmpmeta>"""

        val packet = XmpPacketBuilder.build(existing, "新的直接描述")

        XmpPacketBuilder.validate(packet, "新的直接描述")
        assertTrue(packet.indexOf("ArtworkContentDescription") < packet.indexOf("ArtworkOrObject"))
        assertTrue(packet.contains("保留作者"))
        assertFalse(packet.contains("AOContentDescription"))
        assertEquals(1, Regex("xmlns:Iptc4xmpExt=").findAll(packet).count())
    }

    @Test(expected = IllegalStateException::class)
    fun refusesToDiscardMalformedExistingPacket() {
        XmpPacketBuilder.build("<x:xmpmeta>保留但结构不完整</x:xmpmeta>", "描述")
    }
}
