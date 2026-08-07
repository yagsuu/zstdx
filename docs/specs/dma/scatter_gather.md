# DMA scatter-gather

Status: Approved.

`stdx.dma.ScatterGather` defines device-address segments, fixed-capacity and caller-storage-backed segment lists, and builders that require uniform segment alignment. A consumer reads the resulting metadata to emit its own DMA descriptors.

## What this spec is

This spec defines `stdx.dma.ScatterGather.Segment`, `List.Static`, `List.Bounded`, `Builder.Static`, and `Builder.Bounded`; their storage, capacity, append, iteration, byte-total, alignment, ownership, invalidation, and required-test contracts.

## What this spec is not

This spec does not define:

- DMA mapping, IOMMU translation, bounce buffering, cache maintenance, or allocation of DMA memory;
- descriptor emission or the ABI and wire layout of a device-specific descriptor;
- DMA barriers, device notification, or device-visible atomic updates;
- non-uniform segment rules, including protocol-specific interior and final segment rules; or
- ownership or lifetime extension of a source `Buffer(T)`, host memory, or mapping.

## Terminology

- **segment:** An untyped half-open device-address byte range `[addr, addr + len_bytes)`.
- **list content:** The initialized segment prefix `buffer[0..count]`.
- **capacity:** The number of segments that a list can contain.
- **uniform alignment:** A single power-of-two alignment that divides every appended segment address and byte length.

## Public namespace and source ownership

The public import path is `stdx.dma.ScatterGather`.

The implementation is `src/dma/scatter_gather.zig`. `src/dma.zig` imports that file as `scatter_gather` and exposes its `Segment`, `List`, and `Builder` declarations through `stdx.dma.ScatterGather`. The required tests are in `test/dma/scatter_gather_test.zig`.

## Cross-spec relationships

`Segment.fromBuffer` composes with `stdx.dma.Buffer(T)` and preserves its device address and byte length. This spec uses `stdx.addr.DMAAddr` for device addresses. A caller supplies mapping, cache, lifetime, and barrier behavior; `docs/specs/barrier/dma.md` defines DMA barriers.

## Data structures and representation

`Segment` contains a `DmaAddr` and an `Address.Raw` byte length. `List.Static(N)` owns inline segment storage and a count. `List.Bounded` borrows a `[]Segment` and stores a count. A builder wraps the corresponding list. The field names, field order, ABI layout, and wire layout are not guaranteed.

`Segment.Address.Raw` is `u64`, the width of `stdx.addr.DMAAddr`. Segment lists and `Segment.fromBuffer` preserve descriptor-facing byte lengths as this type and do not convert them through `usize`.

## Global invariants

A valid segment satisfies `addr.raw() + len_bytes` without overflow in `Address.Raw`.

A valid list satisfies `count <= capacity`, and every segment in list content is valid. `List.Static(N)` requires `N > 0` at compile time. `List.Bounded.wrap` accepts an empty backing slice; that list is empty and full. Only list content is initialized list data.

List order is insertion order. The list API does not insert, remove, reorder, coalesce, or sort segments. A caller that needs those transformations MUST perform them outside this API.

## API

```zig
pub const Segment = struct {
    pub const Address = stdx.addr.DMAAddr;
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

`List.Static(capacity_segments)` returns this type:

```zig
pub const Self = struct {
    pub const Error = error{ Full, OutOfBounds };
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

`List.Bounded` has this public surface:

```zig
pub const Bounded = struct {
    pub const Error = error{ Full, OutOfBounds };

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

`Builder.Static` returns this type; `Builder.Bounded` has the same operations except it provides `wrap(buffer: []Segment) Self` instead of `init()` and `finish()` returns `*const List.Bounded`:

```zig
pub const Self = struct {
    pub const Error = error{ Full, Misaligned };
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

## Segment contract

`Segment` is a value type. Copying it copies its address and length and borrows no host memory.

`Segment.init(addr, len_bytes)` returns a valid segment. It returns `error.Overflow` when `addr.raw() + len_bytes` overflows `Address.Raw`. It does not enforce alignment. `Segment.fromBuffer(T, buffer)` returns a segment whose address equals `buffer.dmaAddr()` and whose length equals `buffer.byteLen()`.

`byteLen()` returns `len_bytes`. `isEmpty()` returns `len_bytes == 0`. `endAddr()` returns the one-past-end address or `error.Overflow` when the range overflows; it cannot fail for a segment returned by `init` or `fromBuffer`. `isAligned(alignment)` returns true exactly when `alignment` is a nonzero power of two and both address and byte length are multiples of it. `isAligned(1)` returns true for every segment. `assertValid()` asserts the segment invariant.

Segment operations allocate never, wait never, dereference no device address, emit no barrier, and execute in $O(1)$ time.

## List contract

`append(segment)` appends at `count` and increments `count`. When the list is full, it returns `error.Full` and leaves the list unchanged. `appendAssumeCapacity(segment)` asserts that the list is not full, then appends the segment. `appendBuffer(T, buffer)` appends `Segment.fromBuffer(T, buffer)` and has the same `error.Full` behavior as `append`.

`asSlice()` and `asConstSlice()` return list content. `at(index)` and `constAt(index)` return a pointer to the specified segment and return `error.OutOfBounds` when `index >= count`. `len`, `capacity`, `remaining`, `isEmpty`, and `isFull` report the current list state. `totalByteLen()` sums list-content byte lengths in insertion order and returns `error.Overflow` if the sum overflows `Segment.Address.Raw`.

`clearRetainingCapacity()` sets `count` to zero and does not overwrite backing segment memory. It invalidates all indexes, pointers, and slices previously returned from the list. `append`, `appendAssumeCapacity`, and `appendBuffer` preserve pointers, indexes, and slices to existing list content until the list value moves. Moving a `List.Bounded` value does not move its borrowed storage. A `Bounded` value MUST NOT borrow a field of the same outer struct that contains the `Bounded` value.

List operations allocate never, wait never, use no allocator, and emit no barrier. `append`, accessors, and metadata operations execute in $O(1)$ time. `totalByteLen` executes in $O(len)$ time. Lists do not call destructors.

## Builder contract

`Builder.Static(capacity_segments, alignment)` requires `capacity_segments > 0`, `alignment != 0`, and a power-of-two `alignment` at compile time. `Builder.Bounded(alignment)` has the same alignment requirement and accepts empty backing storage. `alignment == 1` is valid and accepts every segment.

`append(segment)` first checks `segment.isAligned(alignment)`. If that check fails, it returns `error.Misaligned` and leaves the builder unchanged, even when the underlying list is full. Otherwise it appends the segment or returns `error.Full` if the underlying list is full, leaving the builder unchanged. `appendBuffer` constructs a segment with `Segment.fromBuffer` and has the same behavior.

`finish()` returns a const pointer to the underlying list. The builder remains usable. Any subsequent `append`, `appendBuffer`, `clearRetainingCapacity`, or move of the builder invalidates the returned pointer. `clearRetainingCapacity` has the list clearing and invalidation behavior. Builders allocate never, wait never, emit no barrier, and execute their operations in $O(1)$ time.

## Ownership and synchronization

Segments do not retain a source `Buffer(T)`, host slice, mapping, or allocation. The caller MUST keep the source host memory and address mapping valid for the entire DMA transaction. This spec does not synchronize host threads or host and device access. The caller MUST provide external synchronization and the DMA barriers required by its protocol.

No operation accesses hidden global state, uses atomics, locks, volatile access, target probing, syscalls, or I/O.

## Implementation constraints

The implementation MUST store only an address and byte length in `Segment`; inline storage and count in `List.Static`; and a borrowed segment slice and count in `List.Bounded`. It MUST validate builder alignment before list mutation and MUST leave lists unchanged on returned errors. It MUST NOT allocate, dereference `Segment.addr`, or store an allocator, mapping handle, device backend, or synchronization policy.

`Segment.assertValid`, list `assertValid`, and builder `assertValid` MUST check their respective global invariants when assertions are enabled. A builder assertion MUST also check uniform alignment of list content.

## Testing

Segment tests MUST prove zero-length and non-empty construction, end-address overflow rejection, `fromBuffer` address-and-length preservation, one-past-end calculation, byte length and emptiness, and alignment boundaries. Alignment tests MUST cover alignment `1`, zero, non-power-of-two values, aligned values, and address or length misalignment. These tests prove segment range and alignment semantics independently of a DMA device.

List tests MUST exercise both `Static` and `Bounded` storage with the same observable sequence: append to capacity, reject a further append without mutation, access valid and invalid indexes, compute a byte total, overflow that total, and clear while retaining capacity. Tests MUST also prove empty bounded storage is empty and full, `Static(0)` is a compile error, `appendBuffer` preserves the source buffer segment, and `appendAssumeCapacity` appends when its precondition holds. These tests prove capacity, ownership, error, and representation boundaries.

Builder tests MUST cover both storage forms and alignment `1`, `512`, and a page-size alignment. They MUST prove aligned append, misaligned rejection without mutation, full rejection, misalignment precedence over fullness, `appendBuffer` error propagation, `finish` contents, and compile-time rejection of zero or non-power-of-two alignment. These tests prove that builders enforce uniform alignment before capacity mutation.
