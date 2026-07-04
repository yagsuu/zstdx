# DMA buffer

Status: Approved.

`stdx.dma.Buffer(T)` pairs a caller-owned host slice with the device-visible
address of the same memory as one value. It carries the host view (`[]T`) that
callers use to read and write, and the `DmaAddr` that the device consumes in a
descriptor. It never allocates, never maps, and never emits a barrier.

`Buffer(T)` is the atomic unit of DMA-visible memory in `stdx`. Non-contiguous
transfers compose several `Buffer` regions into a segment list; see
`docs/specs/dma/scatter-gather.md`.

## Owned scope

This spec owns:

- `stdx.dma.Buffer(T)`;
- pairing a caller-owned `[]T` with a `stdx.addr.DmaAddr`;
- alignment validation of the paired `DmaAddr` against `@alignOf(T)` and
  against optional caller-supplied stricter alignment;
- byte-length representability against the `DmaAddr` integer width;
- typed and byte accessors, mutable and const;
- element count, byte length, empty check;
- device-visible address of the base and of any element offset;
- validated sub-buffer construction inside the same contiguous region;
- debug invariant checks;
- required tests.

This spec does not own:

- allocation of the underlying host memory; the caller owns and provides it;
- how the paired `DmaAddr` is obtained — physical-address identity mapping,
  IOMMU IOVA allocation, bounce buffering, page pinning, and cache
  maintenance are all downstream policy;
- barrier emission around DMA-visible reads and writes; see
  `docs/specs/barrier/dma.md`;
- multi-segment or non-contiguous regions; see
  `docs/specs/dma/scatter-gather.md`;
- device-side notification such as doorbells or MMIO writes;
- ABI, wire, or descriptor layout for device data structures;
- concurrency between host and device, or across host threads;
- lifetime tracking beyond the caller's usual borrow rules on `[]T`.

## Public namespace

`Buffer` lives under `stdx.dma`:

```zig
stdx.dma.Buffer
```

It is not root-promoted:

```zig
stdx.Buffer // not exported
stdx.DmaBuffer // not exported
```

Source ownership:

```text
src/dma.zig
src/dma/buffer.zig
test/dma/buffer_test.zig
```

`src/dma.zig` re-exports:

```zig
pub const buffer = @import("dma/buffer.zig");

pub const Buffer = buffer.Buffer;
```

## Approved API

```zig
pub fn Buffer(comptime T: type) type;
```

`T` must be a runtime value type with `@sizeOf(T) > 0` and `@alignOf(T) > 0`.
Zero-sized element types are compile errors where practical.

Returned type:

```zig
pub const Self = struct {
    virt: []T,
    dma: stdx.addr.DmaAddr,

    pub const Item = T;
    pub const Address = stdx.addr.DmaAddr;

    pub const Error = error{
        Misaligned,
        Overflow,
        OutOfBounds,
    };

    pub const SubRange = struct {
        offset_items: usize,
        count_items: usize,
    };

    pub fn init(virt: []T, dma: Address) Error!Self;
    pub fn initAligned(virt: []T, dma: Address, alignment: Address.Raw) Error!Self;

    pub fn slice(self: Self) []T;
    pub fn constSlice(self: Self) []const T;
    pub fn bytes(self: Self) []u8;
    pub fn constBytes(self: Self) []const u8;

    pub fn len(self: Self) usize;
    pub fn byteLen(self: Self) Address.Raw;
    pub fn isEmpty(self: Self) bool;

    pub fn dmaAddr(self: Self) Address;
    pub fn dmaAddrAt(self: Self, offset_items: usize) Error!Address;

    pub fn sub(self: Self, range: SubRange) Error!Self;

    pub fn assertValid(self: Self) void;
};
```

`Self` above describes the returned type. Implementations do not need to
declare a public symbol named `Self`.

## Type and pairing contract

A `Buffer(T)` is a paired value:

- `virt` is a caller-owned `[]T`. Its element and byte layout come from
  the Zig slice type. The caller owns lifetime, aliasing, and any host-side
  synchronization for that memory.
- `dma` is the `stdx.addr.DmaAddr` at which the device sees the first byte
  of `virt`. Whether that address is a physical address, an IOMMU IOVA, or a
  bounce-buffer address is caller policy; `Buffer(T)` does not distinguish.

A valid `Buffer(T)` satisfies:

- `dma.raw()` is a multiple of `@alignOf(T)`;
- `virt.len * @sizeOf(T)` fits in `Address.Raw` without overflow;
- `dma.raw() + virt.len * @sizeOf(T)` does not overflow `Address.Raw`.

`Buffer(T)` does not require `virt.len > 0`. An empty buffer is a legal value
and is used to represent "no bytes at this device address."

`Buffer(T)` does not verify that the `virt` and `dma` sides refer to the same
underlying memory. The pairing is a caller assertion. Fabricated `DmaAddr`
values are allowed in tests and in identity-mapped host code.

## Construction

`init(virt, dma)` returns a `Buffer(T)` for the paired view.

`init` returns:

- `error.Misaligned` when `dma.raw()` is not a multiple of `@alignOf(T)`;
- `error.Overflow` when `virt.len * @sizeOf(T)` overflows `Address.Raw`;
- `error.Overflow` when `dma.raw() + virt.len * @sizeOf(T)` overflows
  `Address.Raw`.

`initAligned(virt, dma, alignment)` enforces a stricter alignment than
`@alignOf(T)`. It is meant for consumers whose device or protocol requires,
for example, page alignment on a `Buffer(u8)`. `alignment` follows
`stdx.mem` alignment rules: it must be non-zero and a power of two.

`initAligned` returns:

- `error.Misaligned` when `alignment` is zero, not a power of two, or does not
  divide `dma.raw()`;
- `error.Misaligned` when `dma.raw()` is not a multiple of `@alignOf(T)`;
- `error.Overflow` on the same size overflows as `init`.

`initAligned(virt, dma, @alignOf(T))` is equivalent to `init(virt, dma)`.
`initAligned(virt, dma, 1)` is equivalent to `init(virt, dma)` after the
`@alignOf(T)` check; it does not weaken any check.

Host-side alignment of `virt` is expressed at the call site through the Zig
slice type. Callers who require stricter host-side alignment declare
`[]align(N) T` and rely on the compiler to prove it.

## Accessors

`slice()` returns `virt`.

`constSlice()` returns `virt` as `[]const T`.

`bytes()` returns a `[]u8` view of `virt`. Its length equals `byteLen()`.

`constBytes()` returns `[]const u8` over the same range.

Byte accessors reinterpret element storage as bytes. They are safe for
`Buffer(u8)` and for element types with a defined byte layout. Callers that
use them on element types without a defined byte layout own that decision.

## Metadata

`len()` returns `virt.len`.

`byteLen()` returns `virt.len * @sizeOf(T)` as `Address.Raw`. `assertValid`
guarantees this multiplication does not overflow, so `byteLen()` cannot fail.
`Address.Raw` is the descriptor-facing length width for DMA primitives.
Scatter-gather segments preserve this value without converting through `usize`.

`isEmpty()` returns `virt.len == 0`.

## Device addresses

`dmaAddr()` returns `dma` — the device-visible address of the first byte of
`virt`.

`dmaAddrAt(offset_items)` returns the device-visible address at the item offset
inside `virt`.

`dmaAddrAt` returns:

- `error.OutOfBounds` when `offset_items > virt.len`.
  `offset_items == virt.len` is allowed and returns the one-past-the-end device
  address; callers use it to express `[base, end)` device ranges.

`dmaAddrAt(0)` equals `dmaAddr()`.

`dmaAddrAt` does not fail with `error.Overflow`: `assertValid` guarantees that
`dma.raw() + byteLen()` fits in `Address.Raw`, so any in-range `offset_items`
computation is safe.

## Sub-buffering

`sub(range)` returns a `Buffer(T)` for
`virt[range.offset_items..][0..range.count_items]` paired with
`dmaAddrAt(range.offset_items)`.

`sub` returns:

- `error.OutOfBounds` when `range.offset_items > virt.len` or
  `range.offset_items + range.count_items > virt.len`;
- `error.Overflow` when `range.offset_items + range.count_items` overflows
  `usize`.

`sub(.{ .offset_items = 0, .count_items = virt.len })` equals `self`
(value equality).

`sub(.{ .offset_items = offset, .count_items = 0 })` is valid; it returns an
empty buffer whose device address is `dmaAddrAt(offset)`. Empty sub-buffers at
`offset == virt.len` are useful as `[base, end)` cursors.

Sub-buffering inherits the caller's contiguity claim: if `(virt, dma)` was a
contiguous device-visible region, every `sub(range)` inside it is also
contiguous. `Buffer(T)` does not re-check contiguity; the caller established
it at `init`.

## Invalidation and ordering

`Buffer(T)` is a value type. Copying a `Buffer(T)` copies the slice pointer,
length, and `DmaAddr`; it does not copy the underlying memory.

Mutations to `virt` visible from the device happen through the caller's own
loads and stores against `slice()`/`bytes()`. `Buffer(T)` performs no memory
access on the buffered region.

Ordering between host stores and device reads (and between device stores and
host reads) is not owned by this spec. Consumers use
`stdx.barrier.dma.release`, `stdx.barrier.dma.acquire`, and
`stdx.barrier.dma.releaseAcquire` at the correct points in their protocol.
`Buffer(T)` emits no barrier of its own.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Buffer` | never | never | comptime | none | type factory | none |
| `init` | never | never | O(1) | none | value type | none |
| `initAligned` | never | never | O(1) | none | value type | none |
| `slice` | never | never | O(1) | none | value type | none |
| `constSlice` | never | never | O(1) | none | value type | none |
| `bytes` | never | never | O(1) | none | value type | none |
| `constBytes` | never | never | O(1) | none | value type | none |
| `len` | never | never | O(1) | none | value type | none |
| `byteLen` | never | never | O(1) | none | value type | none |
| `isEmpty` | never | never | O(1) | none | value type | none |
| `dmaAddr` | never | never | O(1) | none | value type | none |
| `dmaAddrAt` | never | never | O(1) | none | value type | none |
| `sub` | never | never | O(1) | none | value type | none |
| `assertValid` | never | never | O(1) | none | value type | none |

These operations perform no heap allocation, waiting, hidden global access,
atomics, barriers, volatile access, target probing, syscalls, locks, or I/O.

## Error behavior

- `init` and `initAligned` return `error.Misaligned` when the `DmaAddr` or the
  extra alignment fails validity;
- `init` and `initAligned` return `error.Overflow` when byte length or the
  end address overflows `Address.Raw`;
- `dmaAddrAt` returns `error.OutOfBounds` when `offset_items > virt.len`;
- `sub` returns `error.OutOfBounds` when the requested window escapes the
  buffer;
- `sub` returns `error.Overflow` when `offset_items + count_items` overflows
  `usize`;
- invalid `T` categories are compile errors where practical.

All error returns leave the input value unchanged.

## Debug assertion behavior

`assertValid()` asserts:

- `dma.raw()` is a multiple of `@alignOf(T)`;
- `virt.len * @sizeOf(T)` does not overflow `Address.Raw`;
- `dma.raw() + virt.len * @sizeOf(T)` does not overflow `Address.Raw`.

Public accessors call `assertValid()` before use when
`core.checksEnabled(opts.safety)` requires runtime invariant checks.

## Implementation constraints

Implementation must:

- store only the `[]T` and the `DmaAddr` in `Self`;
- never store an allocator, mapping handle, backend, or policy flag;
- validate alignment and byte-length representability inside `init` and
  `initAligned` before returning a value;
- never dereference `dma`;
- never touch the memory behind `virt` beyond the accessor return value;
- avoid loops in `init`, `initAligned`, `sub`, `dmaAddrAt`, and the
  metadata methods;
- treat `virt.len == 0` as a legal input on every entry point;
- avoid hidden globals, atomics, fences, volatile operations, target probes,
  and I/O.

## Usage

Contiguous descriptor payload:

```zig
const stdx = @import("stdx");

// Caller provides host memory and its device address.
var payload_backing: [4096]u8 align(4096) = undefined;
const dma_addr = stdx.addr.DmaAddr.fromInt(@intFromPtr(&payload_backing));

var payload = try stdx.dma.Buffer(u8).initAligned(&payload_backing, dma_addr, 4096);

// Fill from the host side.
@memset(payload.slice(), 0);

// Point a device descriptor at it.
descriptor.addr = payload.dmaAddr().raw();
descriptor.len = @intCast(payload.byteLen());

stdx.barrier.dma.release();
doorbell.ring();
```

Typed queue entry array:

```zig
var entries: [64]Sqe = undefined;
const entries_dma = stdx.addr.DmaAddr.fromInt(@intFromPtr(&entries));
var sq = try stdx.dma.Buffer(Sqe).init(&entries, entries_dma);

// Publish the tail entry only.
const tail = try sq.dmaAddrAt(current_tail);
_ = tail;
```

IOMMU-mapped region:

```zig
const mapping = try iommu.map(host_slice);   // caller-owned policy
const iova = stdx.addr.DmaAddr.fromInt(mapping.iova);
var buf = try stdx.dma.Buffer(u8).init(host_slice, iova);
_ = buf;
```

## Required tests

Required for at least `Buffer(u8)`, `Buffer(u32)`, and a `Buffer(WireEntry)`
over a small `extern struct`.

### Construction

- `init` succeeds for a properly aligned empty slice;
- `init` succeeds for a properly aligned non-empty slice;
- `init` returns `error.Misaligned` when `dma.raw()` is not a multiple of
  `@alignOf(T)`;
- `init` returns `error.Overflow` at the top of `Address.Raw` byte length;
- `initAligned` returns `error.Misaligned` for `alignment == 0`;
- `initAligned` returns `error.Misaligned` for non-power-of-two `alignment`;
- `initAligned(virt, dma, @alignOf(T))` matches `init(virt, dma)`.

### Accessors

- `slice`, `constSlice`, `bytes`, `constBytes` return the expected views;
- `bytes().len` equals `byteLen()`;
- `len`, `byteLen`, `isEmpty` match the underlying slice.

### Device addresses

- `dmaAddr()` equals the paired `DmaAddr`;
- `dmaAddrAt(0)` equals `dmaAddr()`;
- `dmaAddrAt(len())` returns the one-past-the-end device address;
- `dmaAddrAt(len() + 1)` returns `error.OutOfBounds`;
- element-typed buffers compute per-element offsets by `@sizeOf(T)`.

### Sub-buffering

- `sub(.{ .offset_items = 0, .count_items = len() })` is value-equal to the
  source;
- `sub(.{ .offset_items = offset, .count_items = count })` narrows both
  `virt` and `dma`;
- `sub(.{ .offset_items = len(), .count_items = 0 })` is a valid empty
  cursor at the end;
- out-of-range windows return `error.OutOfBounds`;
- `offset_items + count_items` overflow returns `error.Overflow`.

### Debug behavior

- `assertValid()` accepts every value returned by `init` and `initAligned`;
- a hand-constructed misaligned value trips `assertValid` where checks are
  enabled.

## Open questions

None.
