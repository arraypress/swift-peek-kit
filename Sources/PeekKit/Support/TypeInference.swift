//
//  TypeInference.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Turning measured shapes into declarations.
///
/// The whole point of generating from a `Shape` rather than from one sample
/// document is that optionality stops being a guess. A field is optional
/// because it was *measured* absent in some rows, not because it happened to
/// be null in the response someone pasted.
public enum TypeInference {

    /// Builds the declarations a dataset's shape implies.
    ///
    /// - Parameters:
    ///   - shapes: Field shapes, as `Shape.of` returns them. Pass the
    ///     `nested: true` form to get nested types rather than one flat one.
    ///   - rootName: What to call the top-level type.
    ///   - enumLimit: The most distinct values a string field may take and
    ///     still be considered an enumeration.
    public static func types(
        from shapes: [FieldShape],
        rootName: String = "Root",
        enumLimit: Int = 24
    ) -> [GeneratedType] {
        let paths = shapes.map(\.name)
        let byPath = Dictionary(shapes.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        var out: [GeneratedType] = []
        var used: Set<String> = [rootName]

        func unique(_ candidate: String) -> String {
            var name = candidate.isEmpty ? "Value" : candidate
            var suffix = 2
            while used.contains(name) {
                name = "\(candidate)\(suffix)"
                suffix += 1
            }
            used.insert(name)
            return name
        }

        func build(prefix: String, typeName: String) {
            let slot = out.count
            out.append(GeneratedType(name: typeName, fields: []))

            var fields: [GeneratedField] = []
            for path in immediateChildren(of: prefix, in: paths) {
                guard let shape = byPath[path] else { continue }
                let segment = lastSegment(path)
                let isOptional = shape.missing > 0
                let hasChildren = !immediateChildren(of: path, in: paths).isEmpty

                if hasChildren {
                    // A path with children is an object, or a list of them.
                    if shape.kind == .array {
                        let element = unique(Identifiers.singular(segment))
                        build(prefix: path, typeName: element)
                        fields.append(.init(wireName: segment, type: .array(.object(element)), isOptional: isOptional))
                    } else {
                        let nested = unique(Identifiers.pascalCase(segment))
                        build(prefix: path, typeName: nested)
                        fields.append(.init(wireName: segment, type: .object(nested), isOptional: isOptional))
                    }
                } else {
                    let type = scalar(shape, enumName: { unique(Identifiers.pascalCase(segment)) }, enumLimit: enumLimit)
                    fields.append(.init(wireName: segment, type: type, isOptional: isOptional))
                }
            }
            out[slot] = GeneratedType(name: typeName, fields: fields)
        }

        build(prefix: "", typeName: rootName)
        return out
    }

    // MARK: - Pieces

    /// Children one level below a prefix. An empty prefix means the top level.
    static func immediateChildren(of prefix: String, in paths: [String]) -> [String] {
        let lead = prefix.isEmpty ? "" : prefix + "."
        return paths.filter { path in
            guard path.hasPrefix(lead), path.count > lead.count else { return false }
            return !path.dropFirst(lead.count).contains(".")
        }
    }

    static func lastSegment(_ path: String) -> String {
        String(path.split(separator: ".").last ?? Substring(path))
    }

    /// The type one leaf field takes.
    ///
    /// `enumName` is a closure so that a type name is only claimed when the
    /// field really is an enumeration — calling it reserves the name.
    static func scalar(
        _ shape: FieldShape,
        enumName: () -> String,
        enumLimit: Int
    ) -> GeneratedFieldType {
        let kinds = shape.kinds.filter { $0 != .null }
        guard kinds.count == 1, let kind = kinds.first, shape.present > 0 else { return .unknown }

        switch kind {
        case .boolean:
            return .boolean
        case .number:
            return isIntegral(shape) ? .integer : .double
        case .string:
            if let cases = enumCases(shape, limit: enumLimit) {
                return .enumeration(name: enumName(), cases: cases)
            }
            return .string
        case .array:
            // `Shape` does not descend into arrays of scalars, so the element
            // type was never observed. Saying `[String]` here would be a
            // guess; the emitters mark it instead.
            return .array(.unknown)
        case .object, .null:
            return .unknown
        }
    }

    /// Whether every number seen was whole.
    ///
    /// `ValueKind` is deliberately coarse and does not separate 1 from 1.5,
    /// so this reads the range and the samples. It is a sample-based answer:
    /// more `--examples` makes it stronger, and it is stated as such.
    static func isIntegral(_ shape: FieldShape) -> Bool {
        guard let minimum = shape.minimum, let maximum = shape.maximum else { return false }
        guard minimum == minimum.rounded(), maximum == maximum.rounded() else { return false }
        return shape.examples.allSatisfy { Int($0) != nil }
    }

    /// The enumeration a string field spells, but only when every distinct
    /// value was actually seen.
    ///
    /// Guessing a case list from three samples of a nine-value field would
    /// produce a type that fails to decode the other six. So this returns
    /// nothing unless the samples cover the distinct count — which means the
    /// caller asked for enough of them.
    static func enumCases(_ shape: FieldShape, limit: Int) -> [String]? {
        guard shape.distinct >= 2, shape.distinct <= limit else { return nil }

        // Every distinct value must actually have been seen. Guessing a case
        // list from three samples of a nine-value field produces a type that
        // fails to decode the other six.
        guard shape.examples.count >= shape.distinct else { return nil }

        // A closed set REPEATS. Names, emails and ids do not — they have about
        // as many distinct values as rows, and an early version of this turned
        // every one of them into an enumeration. Requiring each value to have
        // been seen roughly twice is what separates `status` from `full_name`,
        // and it is measured rather than assumed.
        guard shape.present >= shape.distinct * 2 else { return nil }

        // And do not decide from a handful of rows: three rows cannot
        // establish that a field is closed, however neatly they repeat.
        guard shape.present >= minimumRowsForEnum else { return nil }

        return shape.examples.sorted()
    }

    /// Below this many observations, no string field becomes an enumeration.
    static let minimumRowsForEnum = 8
}
