# DMA scatter-gather

Status: Approved.

`stdx.dma.ScatterGather` is the family for describing a DMA transfer that
spans several device-visible ranges. It is the segment-list side of the DMA
substrate; `stdx.dma.Buffer(T)` is the contiguous-buffer side. The family
consists of one segment record, two storage-shaped segment lists (`Static` and
`Bounded`), and two matching builders that enforce uniform per-segment
alignment.

`ScatterGather` types do not perform DMA mapping, IOMMU translation, cache
maintenance, or descriptor emission. They own the segment metadata; the
consumer emits its own device descriptors from that metadata.

## Owned scope

This spec owns:

- `stdx.dma.ScatterGather.Segment`;
- `stdx.dma.ScatterGather.List.Static(N)`;
- `stdx.dma.ScatterGather.List.Bounded`;
- `stdx.dma.ScatterGather.Builder.Static(N, alignment)`;
- `stdx.dma.ScatterGather.Builder.Bounded(alignment)`;
- appending, iterating, and reading segments;
- total byte length across a segment list;
- uniform alignment validation of appended segments in `Builder` variants;
- capacity, invalidation, ordering, and full-capacity behavior;
- required tests.

This spec does not own:

- descriptor emission for a specific protocol (NVMe PRP or SGL, virtio
  descriptors, xHCI TRBs, and so on);
- non-uniform per-segment alignment or size rules (for example, NVMe PRP's
  "interior entries page-aligned, last entry unrestricted");
- allocation of the segments themselves or of the underlying DMA memory;
- IOMMU mapping, bounce buffering, or cache maintenance;
- barrier emission around segment publication;
- device-visible atomic segment-list updates.

## Public namespace

`ScatterGather` lives under `stdx.dma`:

```zig
stdx.dma.ScatterGather
```

It is not root-promoted:

```zig
stdx.ScatterGather // not exported
stdx.Sg            // not exported
```

Source ownership:

```text
src/dma.zig
src/dma/scatter_gather.zig
test/dma/scatter_gather_test.zig
```

`src/dma.zig` re-exports:

```zig
pub const scatter_gather = @import("dma/scatter_gather.zig");

pub const ScatterGather = struct {
    pub const Segment = scatter_gather.Segment;
    pub const List = scatter_gather.List;
    pub const Builder = scatter_gather.Builder;
};
```

## Approved API

```zig
pub const Segment = struct {
    addr: stdx.addr.DmaAddr,
    len_bytes: stdx.addr.DmaAddr.Raw,

    pub const Address = stdx.addr.DmaAddr;
    pub const Error = error{Overflow};

    pub fn init(addr: Address, len_bytes: Address.Raw) Error!Segment;
    pub fn fromBuffer(comptime T: type, buffer: stdx.dma.Buffer(T)) Segment;

    pub fn byteLen(self: Segment) Address.Raw;
    pub fn isEmpty(self: Segment) bool;

    pub fn endAddr(self: Segment) Error!Address;
    pub fn isAligned(self: Segment, alignment: Address.Raw) bool;

    pub fn assertValid(self: Segment) void;
};

pub const List = struct {
    pub fn Static(comptime capacity_segments: usize) type;
    pub const Bounded = struct { ... };
};

pub const Builder = struct {
    pub fn Static(comptime capacity_segments: usize, comptime alignment: Segment.Address.Raw) type;
    pub fn Bounded(comptime alignment: Segment.Address.Raw) type;
};
```

`Segment.Address.Raw` is `u64` — the width of `stdx.addr.DmaAddr`.

## `Segment` semantics

`Segment` is a value type. Copying a `Segment` copies both fields; no memory
is aliased or borrowed.

`init(addr, len_bytes)` returns a segment. It returns:

- `error.Overflow` when `addr.raw() + len_bytes` overflows `Address.Raw`.

`init` does not enforce alignment. Per-segment alignment is enforced by
`Builder` variants and by `Segment.isAligned`; the base type accepts any
`addr` value.

`fromBuffer(T, buffer)` returns:

```zig
Segment{
    .addr = buffer.dmaAddr(),
    .len_bytes = buffer.byteLen(),
}
```

`buffer.byteLen()` already returns `Address.Raw`, so descriptor-facing scatter
segments carry the same byte-length width as `stdx.addr.DmaAddr`. No `usize`
conversion is performed on the scatter-gather path.

`byteLen()` returns `self.len_bytes`.

`isEmpty()` returns `self.len_bytes == 0`.

`endAddr()` returns `self.addr + self.len_bytes` as `Address`. It returns
`error.Overflow` when `addr.raw() + len_bytes` overflows `Address.Raw`. For a
segment produced by `init` or `fromBuffer`, `endAddr()` cannot fail;
`endAddr` is fallible so that callers may operate on hand-constructed
segments without first re-validating.

`isAligned(alignment)` returns `true` when both `addr.raw()` and `len_bytes`
are multiples of `alignment`. Zero or non-power-of-two alignment returns
`false`. `alignment == 1` returns `true`.

`assertValid()` asserts that `addr.raw() + len_bytes` does not overflow
`Address.Raw`.

`Segment` is untyped by design. A segment describes a device-side descriptor
piece, not a host-side struct. Consumers that need typed host access reach
back to the source `Buffer(T)`.

## `List.Static(N)` semantics

`List.Static(capacity_segments)` is an inline fixed-capacity list of
segments.

Returned type:

```zig
pub const Self = struct {
    buffer: [capacity_segments]Segment = undefined,
    count: usize = 0,

    pub const Error = error{Full, OutOfBounds};
    pub const segment_capacity = capacity_segments;

    pub fn init() Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn asSlice(self: *Self) []Segment;
    pub fn asConstSlice(self: *const Self) []const Segment;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn append(self: *Self, segment: Segment) error{Full}!void;
    pub fn appendAssumeCapacity(self: *Self, segment: Segment) void;
    pub fn appendBuffer(self: *Self, comptime T: type, buffer: stdx.dma.Buffer(T)) error{Full}!void;

    pub fn at(self: *Self, index: usize) error{OutOfBounds}!*Segment;
    pub fn constAt(self: *const Self, index: usize) error{OutOfBounds}!*const Segment;

    pub fn totalByteLen(self: *const Self) error{Overflow}!Segment.Address.Raw;

    pub fn assertValid(self: *const Self) void;
};
```

`List.Static(0)` is a compile error. An empty `List.Bounded` buffer is valid
and produces an empty, full list.

Only `buffer[0..count]` is initialized list content. Field mutation must
preserve `count <= segment_capacity`.

`init()` is equivalent to `.{}`.

`append` writes at `buffer[count]` and increments `count`. It returns
`error.Full` and leaves the list unchanged when `isFull()`.

`appendAssumeCapacity` asserts that the list is not full.

`appendBuffer(T, buffer)` is convenience for
`append(Segment.fromBuffer(T, buffer))`. It returns `error.Full` on the same
condition as `append`.

`at(index)` returns `error.OutOfBounds` when `index >= count`.

`totalByteLen()` sums `segment.len_bytes` across `asConstSlice()`. It returns
`error.Overflow` when the sum overflows `Segment.Address.Raw`.

`clearRetainingCapacity()` sets `count` to zero and does not zero segment
memory.

`assertValid()` asserts `count <= segment_capacity` and calls
`Segment.assertValid` on each segment in `buffer[0..count]`.

There is no `insert`, `orderedRemove`, or `swapRemove`. Scatter-gather lists
are append-only under this spec; consumers that need edits reconstruct the
list.

## `List.Bounded` semantics

`List.Bounded` is a caller-storage-backed list of segments with runtime
capacity.

Type:

```zig
pub const Bounded = struct {
    buffer: []Segment,
    count: usize = 0,

    pub const Error = error{Full, OutOfBounds};

    pub fn wrap(buffer: []Segment) Bounded;

    pub fn len(self: *const Bounded) usize;
    pub fn capacity(self: *const Bounded) usize;
    pub fn remaining(self: *const Bounded) usize;
    pub fn isEmpty(self: *const Bounded) bool;
    pub fn isFull(self: *const Bounded) bool;

    pub fn asSlice(self: *Bounded) []Segment;
    pub fn asConstSlice(self: *const Bounded) []const Segment;

    pub fn clearRetainingCapacity(self: *Bounded) void;

    pub fn append(self: *Bounded, segment: Segment) error{Full}!void;
    pub fn appendAssumeCapacity(self: *Bounded, segment: Segment) void;
    pub fn appendBuffer(self: *Bounded, comptime T: type, buffer: stdx.dma.Buffer(T)) error{Full}!void;

    pub fn at(self: *Bounded, index: usize) error{OutOfBounds}!*Segment;
    pub fn constAt(self: *const Bounded, index: usize) error{OutOfBounds}!*const Segment;

    pub fn totalByteLen(self: *const Bounded) error{Overflow}!Segment.Address.Raw;

    pub fn assertValid(self: *const Bounded) void;
};
```

Semantics mirror `List.Static(N)` with two differences:

- `capacity()` returns `buffer.len` instead of `segment_capacity`;
- storage is caller-owned; moving the `Bounded` value does not move the
  segment storage. Do not embed a `Bounded` field pointing at another field
  of the same outer struct.

## `Builder.Static(N, alignment)` and `Builder.Bounded(alignment)` semantics

A `Builder` wraps a list and enforces uniform per-segment alignment on
append. It is a convenience for consumers whose protocol requires every
segment's `addr` and `len_bytes` to be multiples of a fixed comptime value.

`alignment` must be non-zero and a power of two, following `stdx.mem`
alignment rules. `alignment == 1` is valid and disables alignment
enforcement.

`Builder.Static(capacity_segments, alignment)`:

```zig
pub const Self = struct {
    list: List.Static(capacity_segments) = .{},

    pub const Error = error{Full, Misaligned};
    pub const segment_alignment = alignment;

    pub fn init() Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn asSlice(self: *Self) []Segment;
    pub fn asConstSlice(self: *const Self) []const Segment;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn append(self: *Self, segment: Segment) Error!void;
    pub fn appendBuffer(self: *Self, comptime T: type, buffer: stdx.dma.Buffer(T)) Error!void;

    pub fn finish(self: *Self) *const List.Static(capacity_segments);

    pub fn assertValid(self: *const Self) void;
};
```

`Builder.Bounded(alignment)`:

```zig
pub const Self = struct {
    list: List.Bounded,

    pub const Error = error{Full, Misaligned};
    pub const segment_alignment = alignment;

    pub fn wrap(buffer: []Segment) Self;

    pub fn len(self: *const Self) usize;
    pub fn capacity(self: *const Self) usize;
    pub fn remaining(self: *const Self) usize;
    pub fn isEmpty(self: *const Self) bool;
    pub fn isFull(self: *const Self) bool;

    pub fn asSlice(self: *Self) []Segment;
    pub fn asConstSlice(self: *const Self) []const Segment;

    pub fn clearRetainingCapacity(self: *Self) void;

    pub fn append(self: *Self, segment: Segment) Error!void;
    pub fn appendBuffer(self: *Self, comptime T: type, buffer: stdx.dma.Buffer(T)) Error!void;

    pub fn finish(self: *Self) *const List.Bounded;

    pub fn assertValid(self: *const Self) void;
};
```

Behavior:

- `append(segment)` returns `error.Misaligned` when `segment.isAligned(alignment)` is
  `false`. On `Misaligned`, the list is unchanged.
- `append(segment)` returns `error.Full` when the underlying list is full. On
  `Full`, the list is unchanged.
- `Misaligned` is checked before `Full`.
- `appendBuffer` calls `Segment.fromBuffer` and then `append`; the buffer
  path inherits `Misaligned` and `Full` semantics.
- `finish()` returns a const pointer to the underlying list for read-only
  iteration by the consumer. The builder value remains usable after
  `finish()`; the returned pointer is invalidated by subsequent mutating
  operations on the builder.
- `clearRetainingCapacity()` delegates to the underlying list.

Builders are the only place uniform alignment is enforced. Consumers with
non-uniform rules (NVMe PRP's interior/last split, ATA scatter-gather with
its 64K boundary rule) use the plain `List` variants and enforce their own
constraints at append sites.

## Ownership and lifetime

`Segment` copies freely. Segment lists own inline or borrowed storage as
documented; they never call destructors and hold no allocator.

Segment values are decoupled from their source `Buffer(T)`. Copying a
`Segment` out of a list does not extend the lifetime of the underlying host
memory or of any IOMMU mapping. Callers keep the source memory and mapping
alive across the whole DMA transaction.

## Invalidation and ordering

Segment lists are append-only; existing indexes and pointers into
`asSlice()` stay valid across `append` and `appendAssumeCapacity` until the
list value moves.

`clearRetainingCapacity()` invalidates all indexes, pointers, and slices
previously returned.

`finish()` returns a pointer into the builder's underlying list. That
pointer is invalidated by any subsequent `append`, `appendBuffer`,
`clearRetainingCapacity`, or move of the builder value.

Segment iteration order is `asConstSlice()` order — the order of insertion.
This spec does not own any reordering, coalescing, or sorting policy;
consumers that need those transformations operate on `asSlice()` themselves.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Segment.init` | never | never | O(1) | none | value type | none |
| `Segment.fromBuffer` | never | never | O(1) | none | value type | none |
| `Segment.byteLen` / `isEmpty` / `endAddr` / `isAligned` | never | never | O(1) | none | value type | none |
| `List.Static` / `Bounded` factories | never | never | comptime | none | type factory | none |
| `List.append` / `appendAssumeCapacity` / `appendBuffer` | never | never | O(1) | none | caller-owned value | appends last |
| `List.at` / `constAt` | never | never | O(1) | none | caller-owned value | none |
| `List.totalByteLen` | never | never | O(len) | none | caller-owned value | none |
| `List.clearRetainingCapacity` | never | never | O(1) | all segments | caller-owned value | empty |
| `Builder.append` / `appendBuffer` | never | never | O(1) | none | caller-owned value | appends last |
| `Builder.finish` | never | never | O(1) | none | caller-owned value | none |

All operations perform no heap allocation, waiting, hidden global access,
atomics, barriers, volatile access, target probing, syscalls, locks, or I/O.

## Error behavior

- `Segment.init` returns `error.Overflow` when the end address overflows;
- `Segment.endAddr` returns `error.Overflow` on the same condition;
- `List.append`, `appendAssumeCapacity`, and `appendBuffer` follow the
  approved List family error rules: `error.Full` on capacity exhaustion;
- `List.at` and `List.constAt` return `error.OutOfBounds` when
  `index >= count`;
- `List.totalByteLen` returns `error.Overflow` when the sum exceeds
  `Segment.Address.Raw`;
- `Builder.append` returns `error.Misaligned` before `error.Full`;
- invalid `alignment` in `Builder` factories is a compile error;
- corrupted `count` is a programmer error caught by `assertValid` where
  practical.

All error returns leave the list unchanged.

## Debug assertion behavior

`Segment.assertValid()` asserts `addr.raw() + len` does not overflow
`Address.Raw`.

`List.Static(N).assertValid()` and `List.Bounded.assertValid()` assert
capacity invariants and call `Segment.assertValid` for each initialized
segment.

`Builder.assertValid()` asserts the underlying list is valid and that every
segment in `asConstSlice()` satisfies `isAligned(alignment)`.

Public mutating operations may call `assertValid()` before and after mutation
when `core.checksEnabled(opts.safety)` requires runtime invariant checks.

## Implementation constraints

Implementation must:

- store only `addr` and `len` in `Segment`;
- store only inline segment storage plus `count` in `List.Static`;
- store only a borrowed segment slice plus `count` in `List.Bounded`;
- validate segment alignment in `Builder.append` before mutation;
- leave every list unchanged on error;
- never dereference `Segment.addr`;
- treat `List.Static(0)` and empty `List.Bounded` buffers as legal;
- treat `Builder.*` with `alignment == 1` as a legal no-op wrapper;
- avoid hidden globals, atomics, fences, volatile operations, target probes,
  and I/O.

## Usage

Direct list use, arbitrary per-segment alignment:

```zig
const stdx = @import("stdx");
const Sg = stdx.dma.ScatterGather;

var list = Sg.List.Static(8).init();
try list.appendBuffer(u8, header);
try list.appendBuffer(u8, body);
try list.appendBuffer(u8, trailer);

for (list.asConstSlice()) |seg| {
    descriptor.emit(seg.addr.raw(), seg.byteLen());
}
```

Uniform 4 KiB alignment via Builder:

```zig
const Builder = stdx.dma.ScatterGather.Builder.Static(64, 4096);
var b: Builder = .init();

try b.appendBuffer(u8, page_a); // ok if page_a is 4 KiB aligned in size and dma addr
try b.appendBuffer(u8, page_b); // Misaligned when page_b's dma addr or byteLen isn't a 4 KiB multiple

const chain = b.finish();
for (chain.asConstSlice()) |seg| {
    // emit descriptor
    _ = seg;
}
```

Caller-provided storage:

```zig
var storage: [16]Sg.Segment = undefined;
var list = Sg.List.Bounded.wrap(&storage);
try list.appendBuffer(u8, buffer);
```

## Required tests

Required for `Segment`, `List.Static(N)`, `List.Bounded`, and both `Builder`
variants (with at least `alignment == 1`, `alignment == 512`, and a page-size
alignment such as `4096`).

### Segment

- `init` succeeds for a zero-length segment;
- `init` returns `error.Overflow` when `addr + len_bytes` overflows;
- `fromBuffer` produces `addr == buffer.dmaAddr()` and
  `len_bytes == buffer.byteLen()`;
- `endAddr` returns `addr + len_bytes` for valid segments;
- `isAligned(1)` returns `true` for every valid segment;
- `isAligned(0)` returns `false`;
- `isAligned(alignment)` returns `true` iff both `addr` and `len_bytes` are
  multiples of `alignment`; non-power-of-two alignment returns `false`;
- `byteLen()` and `isEmpty()` reflect `len_bytes`.

### List

- `append` at capacity returns `error.Full` and leaves the list unchanged;
- `appendAssumeCapacity` mutates without checking;
- `appendBuffer` combines `Segment.fromBuffer` and `append`;
- `at` and `constAt` return `error.OutOfBounds` for `index >= count`;
- `totalByteLen` returns the sum as `Segment.Address.Raw` for valid lists;
- `totalByteLen` returns `error.Overflow` when the sum exceeds
  `Segment.Address.Raw`;
- `clearRetainingCapacity` resets `count` without touching capacity;
- `Static(0)` and `Bounded.wrap(&[_]Segment{})` are both empty and full.

### Builder

- `append` of an aligned segment succeeds;
- `append` of a misaligned segment returns `error.Misaligned` and leaves the
  list unchanged;
- `append` when full returns `error.Full`;
- misalignment is reported before fullness when both conditions hold;
- `appendBuffer` inherits both error paths;
- `alignment == 1` accepts every segment;
- `finish` exposes the wrapped list contents;
- non-power-of-two `alignment` and zero `alignment` are compile errors where
  practical.

## Open questions

None.
