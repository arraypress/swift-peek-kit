//
//  SwiftEmitter.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Renders generated types as Swift declarations.
enum SwiftEmitter {

    static func render(_ types: [GeneratedType]) -> String {
        var blocks: [String] = []
        var enums: [String] = []

        for type in types {
            var lines: [String] = ["struct \(type.name): Codable {"]
            for field in type.fields {
                let name = property(field.wireName)
                let rendered = annotation(field.type, optional: field.isOptional)
                lines.append("    let \(name): \(rendered.type)\(rendered.comment)")
                if case .enumeration(let name, let cases) = field.type {
                    enums.append(enumeration(named: name, cases: cases))
                }
            }
            if let keys = codingKeys(type.fields) {
                lines.append("")
                lines.append(keys)
            }
            lines.append("}")
            blocks.append(lines.joined(separator: "\n"))
        }

        return (blocks + enums).joined(separator: "\n\n") + "\n"
    }

    // MARK: - Pieces

    /// A property name, back-ticked when it collides with a keyword.
    static func property(_ wireName: String) -> String {
        let name = Identifiers.camelCase(wireName)
        return Identifiers.isReserved(name, in: .swift) ? "`\(name)`" : name
    }

    static func annotation(_ type: GeneratedFieldType, optional: Bool) -> (type: String, comment: String) {
        let (base, note) = bare(type)
        return (base + (optional ? "?" : ""), note)
    }

    private static func bare(_ type: GeneratedFieldType) -> (String, String) {
        switch type {
        case .integer: ("Int", "")
        case .double: ("Double", "")
        case .string: ("String", "")
        case .boolean: ("Bool", "")
        case .object(let name): (name, "")
        case .enumeration(let name, _): (name, "")
        case .unknown: ("String", "  // mixed or unobserved — check this one")
        case .array(let element):
            switch element {
            case .unknown: ("[String]", "  // element type not observed; --nested reveals objects")
            default: ("[\(bare(element).0)]", bare(element).1)
            }
        }
    }

    /// Only emitted when a wire name and its property name actually differ —
    /// a `CodingKeys` block that restates every name unchanged is noise.
    static func codingKeys(_ fields: [GeneratedField]) -> String? {
        let mapped = fields.filter { Identifiers.camelCase($0.wireName) != $0.wireName }
        guard !mapped.isEmpty else { return nil }
        var lines = ["    enum CodingKeys: String, CodingKey {"]
        for field in fields {
            let name = Identifiers.camelCase(field.wireName)
            let escaped = Identifiers.isReserved(name, in: .swift) ? "`\(name)`" : name
            if name == field.wireName {
                lines.append("        case \(escaped)")
            } else {
                lines.append("        case \(escaped) = \"\(field.wireName)\"")
            }
        }
        lines.append("    }")
        return lines.joined(separator: "\n")
    }

    static func enumeration(named name: String, cases: [String]) -> String {
        var lines = ["enum \(name): String, Codable {"]
        for value in cases {
            let label = Identifiers.camelCase(value)
            let escaped = Identifiers.isReserved(label, in: .swift) ? "`\(label)`" : label
            lines.append("    case \(escaped) = \"\(value)\"")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}
