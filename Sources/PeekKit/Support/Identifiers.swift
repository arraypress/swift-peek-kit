//
//  Identifiers.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Turning wire names into names a compiler will accept.
///
/// Real payloads carry `user_id`, `Content-Type`, `2fa_enabled` and `class`.
/// Every one of those is a different problem.
public enum Identifiers {

    /// Splits a wire name into its words, whatever convention it arrived in.
    ///
    /// Handles `snake_case`, `kebab-case`, `spaced names` and `camelCase` —
    /// including the acronym run in `HTTPServerError`, which naive splitting
    /// turns into `h, t, t, p, server, error`.
    public static func words(_ raw: String) -> [String] {
        var words: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty { words.append(current.lowercased()); current = "" }
        }

        let scalars = Array(raw.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            let character = Character(scalar)
            if character.isLetter || character.isNumber {
                // A capital starts a new word, unless we are mid-acronym and the
                // next character is also capital — `HTTPServer` splits as
                // HTTP + Server, not H + T + T + P + Server.
                if character.isUppercase, !current.isEmpty {
                    let previous = current.last!
                    let nextIsLower = index + 1 < scalars.count && Character(scalars[index + 1]).isLowercase
                    if previous.isLowercase || previous.isNumber || nextIsLower { flush() }
                }
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return words.filter { !$0.isEmpty }
    }

    /// `user_id` -> `UserId`: the shape a type name takes.
    public static func pascalCase(_ raw: String) -> String {
        let parts = words(raw).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let joined = parts.joined()
        return joined.isEmpty ? "Value" : leadingDigitGuard(joined)
    }

    /// `user_id` -> `userId`: the shape a Swift or TypeScript property takes.
    public static func camelCase(_ raw: String) -> String {
        let parts = words(raw)
        guard let first = parts.first else { return "value" }
        let rest = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return leadingDigitGuard(first + rest.joined())
    }

    /// An identifier may not begin with a digit in any of the three languages.
    private static func leadingDigitGuard(_ name: String) -> String {
        guard let first = name.first, first.isNumber else { return name }
        return "_" + name
    }

    /// A crude singular, for naming the element type of a list.
    ///
    /// Crude on purpose: `addresses` -> `Address` and `items` -> `Item` cover
    /// the overwhelming majority, and a real inflector is a dictionary this
    /// package has no business carrying. Anything it gets wrong is a type
    /// name, which a reader renames in one keystroke.
    public static func singular(_ raw: String) -> String {
        let name = pascalCase(raw)
        if name.count > 3, name.hasSuffix("ies") { return String(name.dropLast(3)) + "y" }
        if name.count > 4, name.hasSuffix("ses") { return String(name.dropLast(2)) }
        // Not every trailing -s is a plural. `status`, `bonus` and `analysis`
        // are whole words, and stripping the s gives `Statu`, which is the
        // sort of type name that makes generated code look untrustworthy.
        let lowered = name.lowercased()
        if lowered.hasSuffix("ss") || lowered.hasSuffix("us") || lowered.hasSuffix("is") { return name }
        if name.count > 3, name.hasSuffix("s") { return String(name.dropLast()) }
        return name
    }

    /// Words a language will not accept as a bare identifier.
    public static func isReserved(_ name: String, in language: CodeLanguage) -> Bool {
        switch language {
        case .swift: swiftReserved.contains(name)
        case .typescript: typeScriptReserved.contains(name)
        case .go: goReserved.contains(name)
        }
    }

    /// Whether a wire name can be written as a bare key in TypeScript.
    public static func isPlainIdentifier(_ raw: String) -> Bool {
        guard let first = raw.first, first.isLetter || first == "_" || first == "$" else { return false }
        return raw.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
    }

    private static let swiftReserved: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
        "init", "inout", "internal", "let", "open", "operator", "private", "protocol", "public",
        "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "continue",
        "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat",
        "return", "switch", "where", "while", "as", "catch", "false", "is", "nil", "super", "self",
        "throw", "throws", "true", "try", "any", "some", "Type", "Protocol",
    ]

    private static let typeScriptReserved: Set<String> = [
        "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
        "do", "else", "enum", "export", "extends", "false", "finally", "for", "function", "if",
        "import", "in", "instanceof", "new", "null", "return", "super", "switch", "this", "throw",
        "true", "try", "typeof", "var", "void", "while", "with",
    ]

    private static let goReserved: Set<String> = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
        "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range",
        "return", "select", "struct", "switch", "type", "var",
    ]
}
