//
//  ValueKind.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a value turned out to be.
///
/// Deliberately coarse. The question a shape answers is "can I do maths on
/// this column, and does it ever go missing" — not which of six integer
/// widths it would occupy.
public enum ValueKind: String, Sendable, CaseIterable, Codable {
    case number
    case string
    case boolean
    case null
    case array
    case object
}
