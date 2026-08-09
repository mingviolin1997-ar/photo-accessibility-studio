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
        if (xml.isBlank()) xml = emptyPacket()
        xml = removeElement(xml, "ArtworkContentDescription")
        xml = removeElement(xml, "AOContentDescription")

        val openingRegex = Regex("<rdf:Description\\b[^>]*>")
        val openingMatch = openingRegex.find(xml)
            ?: error("原始 XMP packet 缺少 rdf:Description，无法安全修改")
        var opening = openingMatch.value.replace(
            Regex("\\s+xmlns:Iptc4xmpExt\\s*=\\s*(\"[^\"]*\"|'[^']*')"),
            ""
        )
        val suffix = if (opening.endsWith("/>")) "/>" else ">"
        opening = opening.dropLast(suffix.length) + " xmlns:Iptc4xmpExt=\"$namespace\"$suffix"
        xml = xml.replaceRange(openingMatch.range, opening)

        val element = "<$direct>${escape(description)}</$direct>"
        val refreshed = openingRegex.find(xml)
            ?: error("无法定位更新后的 rdf:Description")
        xml = if (refreshed.value.endsWith("/>")) {
            val expanded = refreshed.value.dropLast(2) + ">\n$element\n</rdf:Description>"
            xml.replaceRange(refreshed.range, expanded)
        } else {
            xml.substring(0, refreshed.range.last + 1) + "\n$element\n" +
                xml.substring(refreshed.range.last + 1)
        }
        validate(xml, description)
        return xml
    }

    fun validate(raw: String, expected: String) {
        require(raw.contains("xmlns:Iptc4xmpExt=\"$namespace\"") ||
            raw.contains("xmlns:Iptc4xmpExt='$namespace'")) { "XMP 命名空间不正确" }
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
        Regex(
            "<(?:[A-Za-z_][\\w.-]*:)?$localName\\b[^>]*>[\\s\\S]*?</(?:[A-Za-z_][\\w.-]*:)?$localName>"
        ),
        ""
    )

    private fun escape(value: String) = value.replace("&", "&amp;").replace("<", "&lt;")
        .replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&apos;")

    private fun unescape(value: String) = value.replace("&lt;", "<").replace("&gt;", ">")
        .replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")

    private fun emptyPacket() = """<?xpacket begin="$xpacketBegin" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description rdf:about=""></rdf:Description>
</rdf:RDF></x:xmpmeta><?xpacket end="w"?>"""
}
