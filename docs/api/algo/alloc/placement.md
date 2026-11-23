# `stdx.algo.alloc.placement`

Deterministic placement of an aligned allocation within caller-owned free
ranges. Selection does not reserve storage or modify the free-range collection.

## Requests and source ranges

`Range` is `stdx.ranges.Range(usize)`, with half-open `[start, end)` bounds.
Starts, lengths, and alignments use the same caller-defined units.

`Request.len` must be non-zero. `Request.alignment` defaults to `1` and must be
a non-zero power of two.

Each source range must have `start <= end`. Examining an inverted range fails
a `std.debug.assert` when assertions are enabled. Empty ranges, overlapping
ranges, and unsorted input are permitted. Source indices always refer to the
original slice order.

## Selection

`FirstFit.select()`, `BestFit.select()`, and `WorstFit.select()` accept a source
slice and request. Each examined source produces at most one candidate: the
lowest start at or above `source.start` aligned to `Request.alignment`, with
end `start + Request.len`. A candidate fits when its end is at most `source.end`.

| Operation | Selection policy |
| --- | --- |
| `FirstFit.select()` | Returns the first fitting candidate in slice order. |
| `BestFit.select()` | Examines all sources and selects the fitting candidate with the smallest total leftover. |
| `WorstFit.select()` | Examines all sources and selects the fitting candidate with the largest total leftover. |

Total leftover is the combined prefix and suffix length, including alignment
padding. Equal-leftover ties for `BestFit.select()` and `WorstFit.select()`
prefer the lowest aligned candidate start, then the lowest source index.

Use the returned `Selection` to reserve the candidate and retain the unused ranges:

| Field | Value |
| --- | --- |
| `Selection.index` | Selected source index |
| `Selection.range` | `[candidate_start, candidate_end)` |
| `Selection.prefix` | `[source.start, candidate_start)` |
| `Selection.suffix` | `[candidate_end, source.end)` |

## Errors and no fit

All three operations validate the request before examining sources, including
for an empty input slice:

1. Zero `Request.len` returns `error.InvalidRequest`, even if alignment is invalid.
2. Zero or non-power-of-two `Request.alignment` returns `error.InvalidAlignment`.

Alignment rounding or candidate-end calculation returns `error.Overflow`
before the fit comparison, even for empty or too-small sources. Any encountered
overflow ends the search, including after an earlier fit. `FirstFit.select()`
does not examine sources after its first fit.

`null` means no candidate fits, including an empty input slice with a valid request.

## Ownership and execution

`Selection` contains copied ranges and does not borrow the input. The caller manages reservation and allocation lifetime.
Keep input ranges immutable during a call. Each strategy takes O(n) worst-case
time and O(1) additional space without allocation or waiting.

## References

- [Placement selection](../../../../src/algo/alloc/placement.zig)
- [Range contract](../../core/range.md)
