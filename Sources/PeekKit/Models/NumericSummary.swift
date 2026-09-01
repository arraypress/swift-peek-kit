//
//  NumericSummary.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The distribution of one numeric field.
///
/// Percentiles rather than a standard deviation, because the things this is
/// pointed at — render levels, response times, file sizes — are skewed, and
/// a mean with a sigma describes a normal distribution none of them have.
public struct NumericSummary: Sendable, Encodable, Equatable {

    public let field: String
    public let count: Int
    public let missing: Int
    public let minimum: Double
    public let p10: Double
    public let p25: Double
    public let median: Double
    public let p75: Double
    public let p90: Double
    public let maximum: Double
    public let mean: Double
    public let sum: Double

    public init(
        field: String,
        count: Int,
        missing: Int,
        minimum: Double,
        p10: Double,
        p25: Double,
        median: Double,
        p75: Double,
        p90: Double,
        maximum: Double,
        mean: Double,
        sum: Double
    ) {
        self.field = field
        self.count = count
        self.missing = missing
        self.minimum = minimum
        self.p10 = p10
        self.p25 = p25
        self.median = median
        self.p75 = p75
        self.p90 = p90
        self.maximum = maximum
        self.mean = mean
        self.sum = sum
    }
}
