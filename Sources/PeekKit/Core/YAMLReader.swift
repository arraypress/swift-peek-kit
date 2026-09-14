//
//  YAMLReader.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation
import Yams

/// Turns YAML into rows.
///
/// The work here is not parsing — Yams does that. It is refusing YAML 1.1's
/// scalar resolution, which is what libyaml implements and which silently
/// corrupts ordinary data.
public enum YAMLReader {

    /// A resolver and constructor pair that reads YAML the way JSON would.
    ///
    /// Measured against 325 real files. Stock Yams turns `country: NO` into
    /// `false` (the Norway problem), `22:22` into `1342` (sexagesimal),
    /// `0777` into `511` (leading-zero octal), and a bare date into a Swift
    /// `Date` that no JSON encoder will accept.
    ///
    /// **All three number rules have to be replaced together.** Fixing bool
    /// and int alone left `mode: 0777` falling through to the untouched float
    /// rule and arriving as `777.0` — the corruption moved rather than went
    /// away.
    nonisolated(unsafe) static let resolver: Resolver = {
        var resolver = Resolver.default
        resolver = try! resolver.replacing(.bool, with: "^(?:true|false)$")
        resolver = try! resolver.replacing(.int, with: "^(?:[-+]?(?:0|[1-9][0-9]*)|0o[0-7]+|0x[0-9a-fA-F]+)$")
        resolver = try! resolver.replacing(.float, with: "^[-+]?(?:[0-9]+\\.[0-9]*|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?$")
        // A timestamp has no JSON form, and leaving it resolved makes the
        // whole document unencodable. As text it survives.
        resolver = resolver.removing(.timestamp)
        return resolver
    }()

    /// Integers stay decimal: no leading-zero octal, no underscore grouping.
    nonisolated(unsafe) static let constructor: Constructor = {
        var map = Constructor.defaultScalarMap
        map[.int] = { scalar in
            let text = scalar.string
            if text.hasPrefix("0x") || text.hasPrefix("-0x") {
                return Int(text.replacingOccurrences(of: "0x", with: ""), radix: 16)
            }
            if text.hasPrefix("0o") { return Int(text.dropFirst(2), radix: 8) }
            return Int(text)
        }
        return Constructor(map)
    }()

    /// Reads a YAML document, or a stream of them.
    ///
    /// Multi-document streams are 4% of real files, so every document becomes
    /// rows rather than only the first.
    public static func rows(from text: String) throws -> (rows: [Dataset.Row], fields: [String]?) {
        let documents: [Node]
        do {
            documents = try Yams.compose_all(yaml: text, resolver, constructor).map { $0 }
        } catch {
            throw PeekError.unreadable("YAML: \(error.localizedDescription)")
        }
        guard !documents.isEmpty else { throw PeekError.unreadable("no YAML value found") }

        var rows: [Dataset.Row] = []
        for document in documents {
            rows.append(contentsOf: JSONReader.rows(fromParsed: constructor.any(from: document)))
        }
        // Source order, not alphabetical. A Swift dictionary cannot keep it,
        // so it is read off the node and handed to the Dataset separately —
        // a config file's key order is meaningful in exactly the way a CSV
        // header's is.
        return (rows, keyOrder(of: documents))
    }

    /// Top-level keys, in the order the file wrote them.
    static func keyOrder(of documents: [Node]) -> [String]? {
        var seen: Set<String> = []
        var ordered: [String] = []
        for document in documents {
            let mappings: [Node.Mapping]
            if let mapping = document.mapping {
                mappings = [mapping]
            } else if let sequence = document.sequence {
                mappings = sequence.compactMap(\.mapping)
            } else {
                mappings = []
            }
            for mapping in mappings {
                for key in mapping.keys {
                    guard let name = key.string, seen.insert(name).inserted else { continue }
                    ordered.append(name)
                }
            }
        }
        return ordered.isEmpty ? nil : ordered
    }
}
