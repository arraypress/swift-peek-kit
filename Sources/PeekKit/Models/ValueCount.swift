//
//  ValueCount.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// How often one value of a field occurred.
public struct ValueCount: Sendable, Encodable, Equatable {

    /// The value, as text.
    public let value: String

    /// How many rows held it.
    public let count: Int

    /// Its share of the rows counted, from 0 to 1.
    public let share: Double

    public init(value: String, count: Int, share: Double) {
        self.value = value
        self.count = count
        self.share = share
    }
}
