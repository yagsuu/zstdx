# DMA buffer

Status: Approved.

`stdx.dma.Buffer(T)` pairs a caller-owned contiguous host slice with the device-visible address of its first byte. The value provides typed and byte views of the slice and device addresses for the complete range and its subranges.

## What this spec is

This spec defines `stdx.dma.Buffer(T)`, its construction, address-range validation, typed and byte accessors, sub-buffer construction, debug invariants, and required tests.

## What this spec is not

This spec does not define:

- allocation, pinning, physical-address identity mapping, IOMMU IOVA allocation, bounce buffering, or cache maintenance for the host memory;
- host-device or host-host synchronization, or DMA barriers; `docs/specs/barrier/dma.md` defines DMA barriers;
- non-contiguous DMA regions; `docs/specs/dma/scatter_gather.md` defines scatter-gather metadata;
- device notification, descriptor layout, ABI layout, or wire layout; or
- lifetime tracking beyond the caller's Zig borrow and ownership rules.

## Terminology

- **host slice:** The caller-owned `[]T` stored in `virt`.
- **device-visible address:** The `stdx.addr.DMAAddr` stored in `dma`; it names the first byte of `virt` in the device address domain selected by the caller.
- **paired region:** The host slice and device-visible address supplied to `init` or `initAligned`. The caller asserts that they identify the same contiguous device-visible memory.

## Public namespace and source ownership

The public import path is `stdx.dma.Buffer`.

The implementation is `src/dma/buffer.zig`. `src/dma.zig` imports that file as `buffer` and re-exports `buffer.Buffer`. The required tests are in `test/dma/buffer_test.zig`.

## Cross-spec relationships

`Buffer(T)` depends on `stdx.addr.DMAAddr` for device addresses. A caller composes multiple `Buffer` regions into `stdx.dma.ScatterGather` segments; this type does not own that composition. A caller uses `stdx.barrier.dma.release`, `stdx.barrier.dma.acquire`, or `stdx.barrier.dma.releaseAcquire` when its DMA protocol requires host-device ordering.

## Data structures and representation

`Buffer(T)` stores a `[]T` in `virt` and a `DmaAddr` in `dma`. Copying a `Buffer(T)` copies the slice pointer, slice length, and address; it does not copy the underlying memory.

## Global invariants

A valid `Buffer(T)` satisfies all of these conditions:

- `dma.raw()` is a multiple of `@alignOf(T)`.
- `virt.len` converts to `Address.Raw`, and `virt.len * @sizeOf(T)` does not overflow `Address.Raw`.
- `dma.raw() + virt.len * @sizeOf(T)` does not overflow `Address.Raw`.

The caller owns the host slice lifetime, host-memory aliasing, mapping lifetime, cache maintenance, and synchronization. `Buffer(T)` does not verify that `virt` and `dma` identify the same memory. Empty buffers are valid and represent zero bytes at `dma`.

## API

```zig
pub fn Buffer(comptime T: type) type;
```

`T` MUST have nonzero size. `Buffer(T)` is a compile error for a zero-sized element type. The returned type has this public surface:

```zig
pub const Self = struct {
    virt: []T,
    dma: stdx.addr.DMAAddr,

    pub const Item = T;
    pub const Address = stdx.addr.DMAAddr;

    pub const InitError = error{ Misaligned, Overflow };
    pub const OffsetError = error{OutOfBounds};
    pub const SubError = error{ Overflow, OutOfBounds };
    pub const Error = InitError || OffsetError || SubError;

    pub const SubRange = struct {
        offset_items: usize,
        count_items: usize,
    };

    pub fn init(virt: []T, dma: Address) InitError!Self;
    pub fn initAligned(virt: []T, dma: Address, alignment: Address.Raw) InitError!Self;

    pub fn slice(self: Self) []T;
    pub fn constSlice(self: Self) []const T;
    pub fn bytes(self: Self) []u8;
    pub fn constBytes(self: Self) []const u8;

    pub fn len(self: Self) usize;
    pub fn byteLen(self: Self) Address.Raw;
    pub fn isEmpty(self: Self) bool;

    pub fn dmaAddr(self: Self) Address;
    pub fn dmaAddrAt(self: Self, offset_items: usize) OffsetError!Address;
    pub fn sub(self: Self, range: SubRange) SubError!Self;
    pub fn assertValid(self: Self) void;
};
```

`Self` in this snippet denotes the type returned by `Buffer(T)`; it is not a public declaration. `SubRange` fields are element counts, not byte counts.

## Construction

`init(virt, dma)` validates the global invariants and returns the paired region. It returns `error.Misaligned` if `dma.raw()` is not a multiple of `@alignOf(T)`. It returns `error.Overflow` if the byte length or end address overflows `Address.Raw`.

`initAligned(virt, dma, alignment)` applies the same validation and requires `dma.raw()` to be a multiple of both `@alignOf(T)` and `alignment`. `alignment` MUST be nonzero and a power of two. It returns `error.Misaligned` for an invalid or unsatisfied alignment and `error.Overflow` for the same byte-length or end-address overflows as `init`.

`initAligned(virt, dma, @alignOf(T))` has the same result as `init(virt, dma)`. An `alignment` of `1` does not weaken the `@alignOf(T)` requirement. The Zig slice type determines host-side alignment; callers that require stricter host alignment MUST provide a suitably aligned slice.

Neither constructor allocates, waits, accesses `virt` memory, dereferences `dma`, emits a barrier, or changes caller-owned memory.

## Accessors and addresses

`slice()` returns `virt`. `constSlice()` returns `virt` as `[]const T`. `bytes()` and `constBytes()` return mutable and const byte views of the same range; each byte-view length equals `byteLen()`. A caller that uses a byte view for an element type without a defined byte layout owns that interpretation.

`len()` returns `virt.len`. `byteLen()` returns `virt.len * @sizeOf(T)` as `Address.Raw`. `isEmpty()` returns `virt.len == 0`.

`dmaAddr()` returns the paired base address. `dmaAddrAt(offset_items)` returns the address at the specified element offset. It returns `error.OutOfBounds` only when `offset_items > virt.len`; `offset_items == virt.len` is valid and returns the one-past-the-end address. `dmaAddrAt(0)` equals `dmaAddr()`. The global invariants guarantee that an in-range address calculation does not overflow.

These operations allocate never, wait never, emit no barrier, and perform no memory access except the caller's subsequent use of a returned slice.

## Sub-buffering

`sub(range)` returns the paired region for `virt[range.offset_items..][0..range.count_items]` and `dmaAddrAt(range.offset_items)`. It returns `error.Overflow` if `range.offset_items + range.count_items` overflows `usize`. It returns `error.OutOfBounds` if the resulting end exceeds `virt.len`. On either error, `self` and the caller-owned storage are unchanged.

`sub(.{ .offset_items = 0, .count_items = virt.len })` is value-equal to `self`. `sub(.{ .offset_items = offset, .count_items = 0 })` is valid for every `offset <= virt.len`; it returns an empty buffer at the corresponding device address.

The returned value borrows the same host memory and inherits the caller's contiguity assertion. It is valid only while the host slice and its mapping remain valid. The operation allocates never, waits never, and emits no barrier.

## Synchronization and invalidation

`Buffer(T)` does not synchronize host threads or host and device access. The caller MUST prevent conflicting host accesses and MUST use the DMA barrier required by its protocol before device-visible publication or host consumption. `Buffer(T)` emits no barrier, uses no atomics, and accesses no hidden global state.

Copies share the same host memory but do not invalidate one another. No `Buffer(T)` operation invalidates a host slice, byte view, or a copied `Buffer(T)`. A returned slice or byte view becomes invalid when the caller ends the lifetime of the underlying host memory or mapping.

## Implementation constraints

The implementation MUST store only the host slice and device-visible address. It MUST validate construction before it returns a value. It MUST NOT store an allocator, mapping handle, backend, or policy flag. It MUST NOT dereference `dma`, allocate, wait, lock, perform I/O, probe the target, use volatile access, emit a fence or barrier, or use atomics.

`init`, `initAligned`, `sub`, `dmaAddrAt`, and metadata accessors MUST execute in $O(1)$ time. `assertValid` MUST check the global invariants when assertions are enabled.

## Testing

Tests MUST construct `Buffer(u8)`, `Buffer(u32)`, and a buffer over a small `extern struct`. Construction tests MUST prove acceptance of aligned empty and non-empty slices and rejection of misaligned addresses, invalid extra alignment, byte-length overflow, and end-address overflow. These tests prove that the device address range and type alignment are validated before a value is returned.

Accessor tests MUST prove that typed and byte views refer to the supplied slice, that byte-view length equals `byteLen()`, and that metadata matches the slice. Address tests MUST prove base equality, element-size scaling, the valid one-past-end address, and rejection of larger offsets. These tests prove that host and device offsets remain paired.

Sub-buffer tests MUST prove full-range value equality, narrowed host and device ranges, valid empty end cursors, out-of-bounds rejection, and `usize` addition overflow. Assertion tests MUST prove that values returned by construction satisfy `assertValid`; where runtime checks are enabled, a hand-constructed invalid value MUST trip the applicable assertion. These tests cover the representation boundaries and invariant enforcement without requiring a DMA device.
