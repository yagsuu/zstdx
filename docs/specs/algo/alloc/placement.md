# Allocation placement algorithms

Status: Approved.

`stdx.algo.alloc.placement` selects deterministic allocation ranges from caller-owned free ranges.

## What this spec is

This spec defines:

- `Range`, `Error`, `Request`, and `Selection`;
- `FirstFit`, `BestFit`, and `WorstFit`;
- alignment, overflow, no-fit, partition, and tie-break behavior;
- allocation, mutation, waiting, concurrency, lifetime, and complexity behavior;
- required verification methods.

## What this spec is not

This spec does not define:

- free-range storage or mutation;
- allocation lifetime;
- allocator exhaustion errors;
- randomized, rotating, next-fit, hint-based, or weighted placement;
- synchronization or memory ordering;
- buddy block arithmetic.

## Terminology

- **unit:** A caller-defined fixed-size allocation resource.
- **source range:** An element of `free_ranges`.
- **candidate:** The aligned allocation range derived from a source range and request.
- **leftover:** The combined length of a candidate's prefix and suffix.

## Public namespace and source ownership

Public declarations:

```zig
stdx.algo.alloc.placement.Range
stdx.algo.alloc.placement.Error
stdx.algo.alloc.placement.Request
stdx.algo.alloc.placement.Selection
stdx.algo.alloc.placement.FirstFit
stdx.algo.alloc.placement.BestFit
stdx.algo.alloc.placement.WorstFit
```

Source files:

```text
src/algo.zig
src/algo/alloc.zig
src/algo/alloc/placement.zig
```

Required test file:

```text
test/algo/alloc/placement_test.zig
```

## Cross-spec relationships

`Range` MUST equal `stdx.core.Range(usize)`. This specification uses its half-open range contract.

## Data structures and representation

All starts, lengths, and alignments use caller-defined units. This API MUST NOT convert units to bytes.

A source range and each `Selection` range use half-open `[start, end)` semantics.

## Global invariants

- A selection operation MUST NOT mutate `free_ranges`.
- A non-null `Selection` MUST identify its source range with `Selection.index`.
- `Selection.prefix`, `Selection.range`, and `Selection.suffix` MUST exactly partition the selected source range.
- A selection operation MUST return `null` when no candidate fits.
- A selection operation MUST NOT allocate, free, wait, access hidden mutable state, issue syscalls, perform atomic or volatile access, or issue barriers.

## API

```zig
pub const Range = stdx.core.Range(usize);

pub const Error = error{
    InvalidRequest,
    InvalidAlignment,
    Overflow,
};

pub const Request = struct {
    len: usize,
    alignment: usize = 1,
};

pub const Selection = struct {
    index: usize,
    range: Range,
    prefix: Range,
    suffix: Range,
};

pub const FirstFit = struct {
    pub fn select(free_ranges: []const Range, request: Request) Error!?Selection;
};

pub const BestFit = struct {
    pub fn select(free_ranges: []const Range, request: Request) Error!?Selection;
};

pub const WorstFit = struct {
    pub fn select(free_ranges: []const Range, request: Request) Error!?Selection;
};
```

## Request and source-range contract

`Request.len` MUST be non-zero.

`Request.alignment` MUST be a non-zero power of two. Its default value MUST be `1`.

The caller MUST provide valid, non-empty, non-overlapping source ranges sorted by ascending `start`. Every source range and `request` MUST use the same unit domain.

The implementation MAY assert the source-range preconditions in checked modes.

## Selection contract

For each source range, a selection operation MUST calculate:

```zig
candidate_start = alignUp(source.start, request.alignment)
candidate_end = candidate_start + request.len
```

A candidate fits when `candidate_end <= source.end`.

Each strategy MUST place its selected candidate at the lowest aligned start in its source range.

`FirstFit.select` MUST scan source ranges in slice order and return the first fitting candidate.

`BestFit.select` MUST return the fitting candidate with the smallest leftover.

`WorstFit.select` MUST return the fitting candidate with the largest leftover.

`BestFit.select` and `WorstFit.select` MUST break equal-leftover ties by the lowest `Selection.range.start`, then by the lowest `Selection.index`.

For a selected source range, the returned ranges MUST be:

```text
prefix: [source.start, Selection.range.start)
range:  [Selection.range.start, Selection.range.end)
suffix: [Selection.range.end, source.end)
```

### Errors and fault behavior

A selection operation MUST return `error.InvalidRequest` when `request.len == 0`.

A selection operation MUST return `error.InvalidAlignment` when `request.alignment` is zero or is not a power of two.

A selection operation MUST return `error.Overflow` when alignment rounding or `candidate_start + request.len` is not representable in `usize`.

A selection operation MUST return `null` when no candidate fits. No-fit MUST NOT be reported as an error.

### Ownership, lifetime, and invalidation

A returned `Selection` MUST contain values only. It MUST NOT borrow from or invalidate `free_ranges`.

### Concurrency effects

Concurrent calls are valid when each caller keeps its input slice immutable for the duration of the call.

### Complexity and progress

Each selection operation MUST complete in O(`free_ranges.len`) time and O(1) additional space. It MUST NOT wait.

## Implementation constraints

The implementation MUST use checked arithmetic for alignment rounding and candidate ends.

The implementation MUST preserve the documented strategy and tie-break rules.

The implementation MUST preserve `free_ranges` on every return path.

## Testing

Public-API tests MUST compare returned selections, errors, and input snapshots. This method verifies observable behavior without depending on private helpers.

Boundary tests MUST exercise invalid requests, invalid alignments, aligned and misaligned starts, arithmetic overflow, empty input, and no-fit input. These cases verify error and null-result boundaries.

Partition tests MUST compare every returned range boundary with the source range and MUST include empty-prefix, empty-suffix, and exact-fit results. These tests prove the partition invariant.

Strategy tests MUST construct inputs that distinguish source order, smallest leftover, largest leftover, and each reachable tie-break. These tests prove deterministic placement.

Model tests MUST compare each strategy with an independent reference scan over small valid range lists. The model MUST vary alignment, fragmentation, range count, and fit outcomes to verify combined behavior beyond individual examples.
