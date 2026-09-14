//
//  ElementShapes.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Correcting paths that reach through an array.
///
/// `items.sku` resolves to *every* sku in the row, so its shape is an array —
/// which is true of the path but wrong for the element type a declaration
/// needs. `items` is `[Item]`; `sku` inside `Item` is a string, not a list of
/// them. Flattening one level puts the array-ness back at the level that owns
/// it.
enum ElementShapes {

    static func corrected(_ shapes: [FieldShape], in dataset: Dataset, examples: Int) -> [FieldShape] {
        let byPath = Dictionary(shapes.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        return shapes.map { shape in
            guard shape.kind == .array, shape.name.contains(".") else { return shape }
            let parent = shape.name.split(separator: ".").dropLast().joined(separator: ".")
            guard let parentShape = byPath[parent], parentShape.kind == .array else { return shape }

            let flattened = dataset.rows.flatMap { row -> [Value] in
                guard let value = Dataset.value(at: shape.name, in: row) else { return [] }
                guard case .array(let items) = value else { return [value] }
                return items
            }
            return Shape.describe(name: shape.name, values: flattened, examples: examples)
        }
    }
}
