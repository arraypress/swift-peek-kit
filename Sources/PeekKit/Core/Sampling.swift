//
//  Sampling.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//
//  Rows that represent a file, rather than the rows that happen to be first.
//
//  WHY THIS EXISTS, with the measurement that prompted it. Taking the head of a data file
//  tells you about the head of the data file. Asked for five rows of an 87,921-row sample
//  manifest, `rows --limit 5` returned five identical-looking rows — all from the same pack,
//  genre and class — because the file is grouped by pack. Out of 164 packs, 20 genres and 53
//  classes, you learned about one of each and could reasonably conclude the data was
//  uniform. It is not; the head was.
//
//  Grouped, sorted and append-ordered files are the normal case, not the exception, so a
//  head is unrepresentative far more often than it is representative.
//

import Foundation

/// Picking rows that stand for the whole.
public enum Sampling {

    /// Every strategy for choosing rows.
    public enum Strategy: String, Sendable, CaseIterable {
        /// The first n rows, in file order.
        case head
        /// n rows drawn uniformly at random, reproducibly.
        case random
        /// n rows spaced evenly from first to last.
        case spread
    }

    /// Choose `count` rows from `rows`.
    ///
    /// - Parameters:
    ///   - rows: the whole dataset.
    ///   - count: how many to return. More than there are returns all of them.
    ///   - strategy: how to choose.
    ///   - seed: makes ``Strategy/random`` reproducible. The same seed over the same file
    ///     gives the same rows, which is what separates a sample you can quote in a bug
    ///     report from one you cannot.
    public static func pick<Row>(from rows: [Row], count: Int,
                                 strategy: Strategy, seed: UInt64 = 0) -> [Row] {
        guard count > 0, !rows.isEmpty else { return [] }
        guard count < rows.count else { return rows }

        switch strategy {
        case .head:
            return Array(rows.prefix(count))
        case .spread:
            return spread(from: rows, count: count)
        case .random:
            return random(from: rows, count: count, seed: seed)
        }
    }

    /// `count` rows spaced evenly across the file, first and last included.
    ///
    /// Deterministic without a seed, which makes it the better default for a sorted file:
    /// you see the beginning, the end, and an even walk between, so a trend is visible in a
    /// way neither a head nor a random draw shows.
    static func spread<Row>(from rows: [Row], count: Int) -> [Row] {
        guard count > 1 else { return rows.isEmpty ? [] : [rows[0]] }
        // Step across count-1 intervals so both ends are hit exactly.
        let step = Double(rows.count - 1) / Double(count - 1)
        var picked: [Row] = []
        picked.reserveCapacity(count)
        var lastIndex = -1
        for step_i in 0 ..< count {
            let index = min(rows.count - 1, Int((Double(step_i) * step).rounded()))
            // Rounding can land twice on the same row when count approaches the row count;
            // stepping forward keeps the result the size that was asked for.
            let chosen = index > lastIndex ? index : min(rows.count - 1, lastIndex + 1)
            picked.append(rows[chosen])
            lastIndex = chosen
        }
        return picked
    }

    /// `count` rows drawn uniformly at random, in file order.
    ///
    /// Uses reservoir sampling: one pass, no shuffle of the whole file, and memory
    /// proportional to the sample rather than the data. The result is sorted back into file
    /// order afterwards because a sample that jumps around is harder to read than one that
    /// does not, and the order carries no information either way.
    static func random<Row>(from rows: [Row], count: Int, seed: UInt64) -> [Row] {
        var generator = SplitMix64(seed: seed)
        var reservoir = Array(rows.indices.prefix(count))

        for index in count ..< rows.count {
            let candidate = Int(generator.next(upperBound: UInt64(index + 1)))
            if candidate < count { reservoir[candidate] = index }
        }
        return reservoir.sorted().map { rows[$0] }
    }
}

/// A small, seedable, deterministic generator.
///
/// Swift's `SystemRandomNumberGenerator` cannot be seeded, and `Int.random(in:)` without one
/// gives a different answer on every run — which would make `--seed` a lie. SplitMix64 is the
/// standard choice here: a few lines, passes the usual statistical batteries, and identical
/// on every platform, so a seeded sample is the same sample on another machine.
struct SplitMix64: RandomNumberGenerator {

    private var state: UInt64

    init(seed: UInt64) {
        // Any seed, including zero, has to produce a usable stream — zero is the default, so
        // the degenerate case is the common one. The additive constant guarantees it.
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
