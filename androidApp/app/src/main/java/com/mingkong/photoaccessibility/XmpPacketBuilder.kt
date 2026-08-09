package com.mingkong.photoaccessibility

object XmpPacketBuilder {
    const val namespace = "http://iptc.org/std/Iptc4xmpExt/2008-02-29/"
    private const val direct = "Iptc4xmpExt:ArtworkContentDescription"
    private const val nested = "Iptc4xmpExt:AOContentDescription"
    private const val xpacketBegin = "\uFEFF"

    fun build(existing: String?, description: String): String {
        require(description.isNotBlank()) { "描述不能为空" }
        require(description.none { it == '\u0000' || (it.code < 32 && !it.isWhitespace()) }) {
            "描述包含无法写入 XML 的控制字符"
        }
        var xml = existing.orEmpty()
        xml = removeElement(xml, "ArtworkContentDescription")
        xml = removeElement(xml, "AOContentDescription")
        if (xml.isBlank() || !xml.contains("<rdf:RDF")) xml = emptyPacket()
        if (!xml.contains("xmlns:Iptc4xmpExt=\"$namespace\"")) {
            xml = xml.replaceFirst("<rdf:Description", "<rdf:Description xmlns:Iptc4xmpExt=\"$namespace\"")
        }
        val element = "<$direct>${escape(description)}</$direct>"
        xml = if (xml.contains("</rdf:Description>")) {
            xml.replaceFirst("</rdf:Description>", "$element</rdf:Description>")
        } else {
            emptyPacket().replace("</rdf:Description>", "$element</rdf:Description>")
        }
        validate(xml, description)
        return xml
    }

    fun validate(raw: String, expected: String) {
        require(raw.contains("xmlns:Iptc4xmpExt=\"$namespace\"")) { "XMP 命名空间不正确" }
        require(!raw.contains("<$nested")) { "XMP 中仍存在错误的 AOContentDescription" }
        val matches = Regex("<$direct(?:\\s[^>]*)?>([\\s\\S]*?)</$direct>").findAll(raw).toList()
        require(matches.size == 1) { "XMP 必须恰好包含一个直接描述字段" }
        require(unescape(matches.single().groupValues[1]) == expected) { "XMP 描述回读不一致" }
    }

    fun extract(raw: String): String? {
        val match = Regex("<$direct(?:\\s[^>]*)?>([\\s\\S]*?)</$direct>").find(raw) ?: return null
        return unescape(match.groupValues[1])
    }

    private fun removeElement(xml: String, localName: String): String = xml.replace(
        Regex("<Iptc4xmpExt:$localName(?:\\s[^>]*)?>[\\s\\S]*?</Iptc4xmpExt:$localName>"), ""
    )

    private fun escape(value: String) = value.replace("&", "&amp;").replace("<", "&lt;")
        .replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&apos;")

    private fun unescape(value: String) = value.replace("&lt;", "<").replace("&gt;", ">")
        .replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")

    private fun emptyPacket() = """<?xpacket begin="$xpacketBegin" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description rdf:about="" xmlns:Iptc4xmpExt="$namespace"></rdf:Description>
</rdf:RDF></x:xmpmeta><?xpacket end="w"?>"""
}
