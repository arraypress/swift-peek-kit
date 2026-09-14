//
//  TypeScriptEmitter.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Renders generated types as TypeScript declarations.
enum TypeScriptEmitter {

    static func render(_ types: [GeneratedType]) -> String {
        var blocks: [String] = []
        var unions: [String] = []

        for type in types {
            var lines: [String] = ["export interface \(type.name) {"]
            for field in type.fields {
                let key = Identifiers.isPlainIdentifier(field.wireName) ? field.wireName : "\"\(field.wireName)\""
                let (rendered, note) = annotation(field.type)
                // A field PeekKit counted as missing was absent, null, or empty,
                // so both the optional marker and the null are earned.
                let mark = field.isOptional ? "?" : ""
                let tail = field.isOptional ? " | null" : ""
                lines.append("  \(key)\(mark): \(rendered)\(tail);\(note)")
                if case .enumeration(let name, let cases) = field.type {
                    unions.append("export type \(name) = \(cases.map { "\"\($0)\"" }.joined(separator: " | "));")
                }
            }
            lines.append("}")
            blocks.append(lines.joined(separator: "\n"))
        }
        return (blocks + unions).joined(separator: "\n\n") + "\n"
    }

    static func annotation(_ type: GeneratedFieldType) -> (String, String) {
        switch type {
        case .integer, .double: ("number", "")
        case .string: ("string", "")
        case .boolean: ("boolean", "")
        case .object(let name): (name, "")
        case .enumeration(let name, _): (name, "")
        case .unknown: ("unknown", "  // mixed or unobserved — check this one")
        case .array(let element):
            switch element {
            case .unknown: ("unknown[]", "  // element type not observed; --nested reveals objects")
            default: ("\(annotation(element).0)[]", annotation(element).1)
            }
        }
    }
}
