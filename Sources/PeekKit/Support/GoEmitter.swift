//
//  GoEmitter.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Renders generated types as Go declarations.
enum GoEmitter {

    static func render(_ types: [GeneratedType]) -> String {
        var blocks: [String] = []
        var enums: [String] = []

        for type in types {
            // gofmt aligns struct columns, so emitting them already aligned is
            // what a Go reader expects to see.
            let rows = type.fields.map { field -> (String, String, String, String) in
                let (rendered, note) = annotation(field.type, optional: field.isOptional)
                let tag = "`json:\"\(field.wireName)\(field.isOptional ? ",omitempty" : "")\"`"
                return (name(field.wireName), rendered, tag, note)
            }
            let nameWidth = rows.map(\.0.count).max() ?? 0
            let typeWidth = rows.map(\.1.count).max() ?? 0

            var lines = ["type \(type.name) struct {"]
            for (fieldName, fieldType, tag, note) in rows {
                let paddedName = fieldName.padding(toLength: max(nameWidth, fieldName.count), withPad: " ", startingAt: 0)
                let paddedType = fieldType.padding(toLength: max(typeWidth, fieldType.count), withPad: " ", startingAt: 0)
                lines.append("\t\(paddedName) \(paddedType) \(tag)\(note)")
            }
            lines.append("}")
            blocks.append(lines.joined(separator: "\n"))

            for field in type.fields {
                if case .enumeration(let enumName, let cases) = field.type {
                    enums.append(enumeration(named: enumName, cases: cases))
                }
            }
        }
        return (blocks + enums).joined(separator: "\n\n") + "\n"
    }

    /// Exported Go field names, with the initialisms Go style insists on.
    static func name(_ wireName: String) -> String {
        let initialisms: Set<String> = [
            "id", "url", "uri", "api", "http", "https", "json", "xml", "html",
            "sql", "uuid", "ip", "db", "ttl", "cpu", "ram", "os", "eof",
        ]
        let parts = Identifiers.words(wireName).map { word -> String in
            initialisms.contains(word) ? word.uppercased() : word.prefix(1).uppercased() + word.dropFirst()
        }
        let joined = parts.joined()
        guard let first = joined.first, !first.isNumber else { return "F" + joined }
        return joined.isEmpty ? "Value" : joined
    }

    static func annotation(_ type: GeneratedFieldType, optional: Bool) -> (String, String) {
        let (base, note) = bare(type)
        // A pointer is how Go says "this may be absent" for a scalar. Slices
        // and maps are already nilable, so pointing at them adds nothing.
        let needsPointer = optional && !base.hasPrefix("[]")
        return ((needsPointer ? "*" : "") + base, note)
    }

    private static func bare(_ type: GeneratedFieldType) -> (String, String) {
        switch type {
        case .integer: ("int", "")
        case .double: ("float64", "")
        case .string: ("string", "")
        case .boolean: ("bool", "")
        case .object(let name): (name, "")
        case .enumeration(let name, _): (name, "")
        case .unknown: ("any", "  // mixed or unobserved — check this one")
        case .array(let element):
            switch element {
            case .unknown: ("[]any", "  // element type not observed; --nested reveals objects")
            default: ("[]\(bare(element).0)", bare(element).1)
            }
        }
    }

    static func enumeration(named enumName: String, cases: [String]) -> String {
        var lines = ["type \(enumName) string", "", "const ("]
        let labels = cases.map { enumName + name($0) }
        let width = labels.map(\.count).max() ?? 0
        for (label, value) in zip(labels, cases) {
            let padded = label.padding(toLength: max(width, label.count), withPad: " ", startingAt: 0)
            lines.append("\t\(padded) \(enumName) = \"\(value)\"")
        }
        lines.append(")")
        return lines.joined(separator: "\n")
    }
}
