# PeekKit

Describe and summarise tabular data — JSON, NDJSON, CSV and TSV — without
reading it.

The engine behind [`peek`](https://github.com/arraypress/swift-peek-cli). No
network, no dependencies, no model.

## Why

Every analysis begins with the same throwaway script: dig the JSON out of a
tool's noisy output, pull one field, sort it, take the median, count how often
each value appears, compare it against yesterday's run. It gets written fresh
every time and thrown away every time.

```swift
let dataset = try DatasetReader.read(contentsOf: url)

Shape.of(dataset)                                  // fields, types, what's missing
try Statistics.summary(of: "peak", in: dataset)    // min, p10, median, p90, max
try Statistics.counts(of: "issues.code", in: dataset)
try Comparison.diff(before: a, after: b, key: "file", tolerance: 0.5)
```

## What it handles that a split does not

**JSON buried in noise.** Tool output is rarely clean — a plug-in logs, a
framework warns, a banner prints. The reader finds the first complete JSON
value in the text, honouring strings and escapes so a bracket inside a value
does not end it early.

**Real CSV.** Quoted commas, newlines inside quotes, doubled quotes, CRLF,
blank and duplicated headers. Splitting on commas is wrong on the first
quoted address it meets, and wrong *silently* — rows of the wrong width that
everything downstream then reports confidently.

**CSV has no types.** A cell is text until something reads it as a number, so
`1,234`, `$99` and `50%` all summarise. But a column is only called numeric
when *every* value in it is: one `n/a` among the prices means maths would
quietly skip a row, and the shape says so instead.

**Nesting.** `issues.code` reaches through an object, and maps over an array
so a row carrying three codes answers for all three.

**Percentiles are nearest-rank.** Every number reported is one that actually
occurred, rather than an interpolation between two that did.

**Diffs are keyed.** Rows match on an identifier, not on position, so
reordering is not a change; `tolerance` ignores movement below a size, because
measured data is noisy and a diff reporting every digit of drift buries the
differences that mean something.

## Installation

```swift
.package(url: "https://github.com/arraypress/swift-peek-kit.git", from: "0.1.0")
```

## Licence

MIT.
