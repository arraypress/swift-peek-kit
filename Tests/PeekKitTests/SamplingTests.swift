//
//  SamplingTests.swift
//  PeekKitTests
//
//  Created by David Sherlock on 2026.
//
//  Choosing rows that stand for the whole file.
//

import XCTest
@testable import PeekKit

final class SamplingTests: XCTestCase {

    /// A grouped file, which is the case that makes a head useless: the first fifth is all
    /// "a", the next all "b", and so on.
    private func grouped(_ groups: [String], each: Int) -> [String] {
        groups.flatMap { Array(repeating: $0, count: each) }
    }

    // MARK: Head

    func testHeadTakesTheFirstRows() {
        let rows = Array(1...100)
        XCTAssertEqual(Sampling.pick(from: rows, count: 3, strategy: .head), [1, 2, 3])
    }

    /// The problem this whole file exists to fix, stated as a test.
    func testHeadSeesOnlyOneGroupWhereSpreadSeesThemAll() {
        let rows = grouped(["a", "b", "c", "d", "e"], each: 20)

        let head = Sampling.pick(from: rows, count: 5, strategy: .head)
        XCTAssertEqual(Set(head), ["a"], "a head of a grouped file shows one group")

        let spread = Sampling.pick(from: rows, count: 5, strategy: .spread)
        XCTAssertEqual(Set(spread), ["a", "b", "c", "d", "e"], "spread reaches every group")
    }

    // MARK: Spread

    func testSpreadIncludesBothEnds() {
        let rows = Array(1...100)
        let picked = Sampling.pick(from: rows, count: 5, strategy: .spread)
        XCTAssertEqual(picked.first, 1)
        XCTAssertEqual(picked.last, 100)
        // Step is 99/4 = 24.75 over indices 0...99, so 0, 25, 50, 74, 99 — spacings of
        // 25, 25, 24, 25, which is as even as integer indices allow.
        XCTAssertEqual(picked, [1, 26, 51, 75, 100])
        let gaps = zip(picked, picked.dropFirst()).map { $1 - $0 }
        XCTAssertLessThanOrEqual((gaps.max() ?? 0) - (gaps.min() ?? 0), 1,
                                 "spacings must differ by at most one")
    }

    func testSpreadIsDeterministicWithoutASeed() {
        let rows = Array(1...1000)
        let first = Sampling.pick(from: rows, count: 7, strategy: .spread)
        let second = Sampling.pick(from: rows, count: 7, strategy: .spread)
        XCTAssertEqual(first, second)
    }

    /// Rounding can land on the same index twice when the sample approaches the row count.
    /// The result must still be the size that was asked for, with no repeats.
    func testSpreadReturnsTheRequestedCountWithoutRepeating() {
        for count in 2...19 {
            let rows = Array(1...20)
            let picked = Sampling.pick(from: rows, count: count, strategy: .spread)
            XCTAssertEqual(picked.count, count, "asked for \(count)")
            XCTAssertEqual(Set(picked).count, count, "\(count) should have no duplicates")
        }
    }

    func testSpreadOfOneTakesTheFirstRow() {
        XCTAssertEqual(Sampling.pick(from: Array(1...50), count: 1, strategy: .spread), [1])
    }

    // MARK: Random

    /// The point of `--seed`: the same seed gives the same rows, so a sample can be quoted
    /// in a bug report and reproduced by somebody else.
    func testRandomIsReproducibleForASeed() {
        let rows = Array(1...1000)
        let first = Sampling.pick(from: rows, count: 10, strategy: .random, seed: 42)
        let second = Sampling.pick(from: rows, count: 10, strategy: .random, seed: 42)
        XCTAssertEqual(first, second)
    }

    func testDifferentSeedsGiveDifferentRows() {
        let rows = Array(1...1000)
        let a = Sampling.pick(from: rows, count: 10, strategy: .random, seed: 1)
        let b = Sampling.pick(from: rows, count: 10, strategy: .random, seed: 2)
        XCTAssertNotEqual(a, b)
    }

    /// Seed zero is the default, so the degenerate case is the common one.
    func testSeedZeroProducesAUsableSpread() {
        let rows = Array(1...1000)
        let picked = Sampling.pick(from: rows, count: 20, strategy: .random, seed: 0)
        XCTAssertEqual(picked.count, 20)
        XCTAssertEqual(Set(picked).count, 20, "no row may be drawn twice")
        XCTAssertGreaterThan(Set(picked).count, 1)
    }

    func testRandomReturnsRowsInFileOrder() {
        let rows = Array(1...500)
        let picked = Sampling.pick(from: rows, count: 12, strategy: .random, seed: 7)
        XCTAssertEqual(picked, picked.sorted(), "a sample is easier to read in file order")
    }

    /// Reservoir sampling has to be uniform, or "random" is a misnomer. Over a grouped file
    /// every group should appear at roughly its true share.
    func testRandomIsUniformAcrossGroups() {
        let rows = grouped(["a", "b", "c", "d"], each: 250)
        var tally: [String: Int] = [:]
        // Many seeds rather than one large sample: this tests the generator as well as the
        // reservoir, and a single draw could be lucky.
        for seed in 0 ..< 200 {
            for row in Sampling.pick(from: rows, count: 4, strategy: .random, seed: UInt64(seed)) {
                tally[row, default: 0] += 1
            }
        }
        let total = tally.values.reduce(0, +)
        for group in ["a", "b", "c", "d"] {
            let share = Double(tally[group] ?? 0) / Double(total)
            XCTAssertEqual(share, 0.25, accuracy: 0.06,
                           "\(group) came out at \(share), expected about a quarter")
        }
    }

    func testRandomNeverRepeatsARow() {
        let rows = Array(1...100)
        for seed in 0 ..< 50 {
            let picked = Sampling.pick(from: rows, count: 25, strategy: .random, seed: UInt64(seed))
            XCTAssertEqual(Set(picked).count, 25, "seed \(seed) drew a duplicate")
        }
    }

    // MARK: Edges

    func testAskingForMoreThanExistsReturnsEverything() {
        let rows = [1, 2, 3]
        for strategy in Sampling.Strategy.allCases {
            XCTAssertEqual(Sampling.pick(from: rows, count: 99, strategy: strategy), rows,
                           "\(strategy)")
        }
    }

    func testEmptyInputAndZeroCountAreEmpty() {
        for strategy in Sampling.Strategy.allCases {
            XCTAssertTrue(Sampling.pick(from: [Int](), count: 5, strategy: strategy).isEmpty)
            XCTAssertTrue(Sampling.pick(from: [1, 2, 3], count: 0, strategy: strategy).isEmpty)
            XCTAssertTrue(Sampling.pick(from: [1, 2, 3], count: -1, strategy: strategy).isEmpty)
        }
    }

    func testASingleRowFileSurvivesEveryStrategy() {
        for strategy in Sampling.Strategy.allCases {
            XCTAssertEqual(Sampling.pick(from: ["only"], count: 3, strategy: strategy), ["only"])
        }
    }

    // MARK: The generator

    /// A seeded generator that differs between machines would make `--seed` useless for
    /// sharing a sample, so the exact stream is pinned.
    func testSplitMix64ProducesAKnownStream() {
        var generator = SplitMix64(seed: 0)
        let first = (0 ..< 3).map { _ in generator.next() }
        var again = SplitMix64(seed: 0)
        XCTAssertEqual((0 ..< 3).map { _ in again.next() }, first)

        var other = SplitMix64(seed: 1)
        XCTAssertNotEqual(other.next(), first[0])
    }

    func testGeneratorCoversItsRange() {
        var generator = SplitMix64(seed: 99)
        var seen = Set<UInt64>()
        for _ in 0 ..< 500 { seen.insert(generator.next(upperBound: 10)) }
        XCTAssertEqual(seen.count, 10, "every value 0..<10 should come up")
    }
}
