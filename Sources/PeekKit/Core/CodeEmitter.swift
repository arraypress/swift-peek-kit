//
//  CodeEmitter.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Declarations for the data, generated from its measured shape.
///
/// The difference from generating out of one sample document is optionality.
/// A single response cannot tell you whether `email` is nullable or merely
/// null this time; a shape read over every row can, because it counted.
/// Enumerations work the same way — a string field only becomes an `enum`
/// when every distinct value it takes was actually observed.
public enum CodeEmitter {

    /// Renders a dataset's shape as source in one language.
    ///
    /// - Parameters:
    ///   - shapes: Field shapes from `Shape.of`. Pass the `nested: true` form
    ///     to get nested types instead of one flat one with dotted names.
    ///   - language: What to write.
    ///   - rootName: The name for the top-level type.
    ///   - enumLimit: The most distinct values a string may take and still be
    ///     treated as an enumeration.
    public static func emit(
        _ shapes: [FieldShape],
        as language: CodeLanguage,
        rootName: String = "Root",
        enumLimit: Int = 24
    ) -> String {
        let types = TypeInference.types(from: shapes, rootName: rootName, enumLimit: enumLimit)
        return emit(types, as: language)
    }

    /// Renders a dataset directly — the form a caller usually wants.
    ///
    /// Shapes the data, corrects the paths that reach through arrays so the
    /// array-ness sits on the field that owns it, and emits. Reading enough
    /// `examples` matters: a string field only becomes an enumeration when
    /// every distinct value it takes was actually sampled.
    public static func emit(
        _ dataset: Dataset,
        as language: CodeLanguage,
        rootName: String = "Root",
        examples: Int = 20,
        enumLimit: Int = 24
    ) -> String {
        let measured = Shape.of(dataset, examples: examples, nested: true)
        let corrected = ElementShapes.corrected(measured, in: dataset, examples: examples)
        return emit(corrected, as: language, rootName: rootName, enumLimit: enumLimit)
    }

    /// Renders already-inferred types. Useful when a caller wants to inspect
    /// or adjust the types before they are written out.
    public static func emit(_ types: [GeneratedType], as language: CodeLanguage) -> String {
        switch language {
        case .swift: SwiftEmitter.render(types)
        case .typescript: TypeScriptEmitter.render(types)
        case .go: GoEmitter.render(types)
        }
    }
}
