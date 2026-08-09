import Foundation

enum XMPPacketError: LocalizedError {
    case malformedPacket
    case directFieldMissing
    case nestedFieldPresent

    var errorDescription: String? {
        switch self {
        case .malformedPacket: return "原始 XMP packet 结构无法安全修改"
        case .directFieldMissing: return "XMP 中缺少直接的 ArtworkContentDescription 元素"
        case .nestedFieldPresent: return "XMP 中仍存在错误的 AOContentDescription 嵌套元素"
        }
    }
}

struct XMPPacketBuilder {
    static let namespace = "http://iptc.org/std/Iptc4xmpExt/2008-02-29/"
    static let directElement = "Iptc4xmpExt:ArtworkContentDescription"
    static let nestedElement = "Iptc4xmpExt:AOContentDescription"

    func build(existing: Data?, description: String) throws -> Data {
        var xml = existing.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            xml = minimalPacket
        }
        xml = removingElements(named: "ArtworkContentDescription", from: xml)
        xml = removingElements(named: "AOContentDescription", from: xml)
        guard let openingRange = xml.range(of: #"<rdf:Description\b[^>]*>"#,
                                           options: .regularExpression) else {
            throw XMPPacketError.malformedPacket
        }
        var opening = String(xml[openingRange])
        let namespacePattern = #"\s+xmlns:Iptc4xmpExt\s*=\s*("[^"]*"|'[^']*')"#
        if let regex = try? NSRegularExpression(pattern: namespacePattern) {
            let range = NSRange(opening.startIndex..<opening.endIndex, in: opening)
            opening = regex.stringByReplacingMatches(in: opening, range: range, withTemplate: "")
        }
        let suffix = opening.hasSuffix("/>") ? "/>" : ">"
        opening.removeLast(suffix.count)
        opening += " xmlns:Iptc4xmpExt=\"\(Self.namespace)\"\(suffix)"
        xml.replaceSubrange(openingRange, with: opening)
        let element = "<\(Self.directElement)>\(escape(description))</\(Self.directElement)>"
        if opening.hasSuffix("/>") {
            guard let refreshed = xml.range(of: #"<rdf:Description\b[^>]*/>"#,
                                            options: .regularExpression) else {
                throw XMPPacketError.malformedPacket
            }
            var expanded = String(xml[refreshed])
            expanded.removeLast(2)
            expanded += ">\n\(element)\n</rdf:Description>"
            xml.replaceSubrange(refreshed, with: expanded)
        } else if let closing = xml.range(of: "</rdf:Description>") {
            xml.insert(contentsOf: "\n\(element)\n", at: closing.lowerBound)
        } else {
            throw XMPPacketError.malformedPacket
        }
        let data = Data(xml.utf8)
        try validateRaw(data)
        return data
    }

    func validateRaw(_ data: Data) throws {
        guard let xml = String(data: data, encoding: .utf8),
              xml.contains("xmlns:Iptc4xmpExt=\"\(Self.namespace)\"") ||
              xml.contains("xmlns:Iptc4xmpExt='\(Self.namespace)'") else {
            throw XMPPacketError.directFieldMissing
        }
        let directPattern = #"<Iptc4xmpExt:ArtworkContentDescription(?:\s[^>]*)?>[\s\S]*?</Iptc4xmpExt:ArtworkContentDescription>"#
        guard xml.range(of: directPattern, options: .regularExpression) != nil else {
            throw XMPPacketError.directFieldMissing
        }
        guard !xml.contains("<\(Self.nestedElement)") else {
            throw XMPPacketError.nestedFieldPresent
        }
    }

    private func removingElements(named localName: String, from xml: String) -> String {
        let pattern = #"<(?:[A-Za-z_][\w.-]*:)?"# + localName +
            #"\b[^>]*>[\s\S]*?</(?:[A-Za-z_][\w.-]*:)?"# + localName + #">"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return xml }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.stringByReplacingMatches(in: xml, range: range, withTemplate: "")
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private var minimalPacket: String {
        """
        <?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""></rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }
}
