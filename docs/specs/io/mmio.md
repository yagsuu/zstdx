# IO MMIO register

Status: Approved.

`stdx.io.Mmio.Register(T)` is a typed volatile storage lane for memory-mapped
device registers. `stdx.io.Mmio.Window` is a byte-window value that produces
typed register pointers from runtime-computed offsets.

The two types cover the two shapes that appear in every MMIO consumer: fixed
register blocks expressed as an `extern struct` overlay, and register arrays or
offset-computed registers reached through a base pointer plus arithmetic.

Register access provides only compiler ordering. Hardware ordering against DMA
payloads or other MMIO accesses is caller-responsible and is provided by the
`stdx.barrier.mmio` and `stdx.barrier.dma` operations owned by
`docs/specs/barrier/dma.md`.

## Owned scope

This spec owns:

- `io.Mmio.Register(T)` typed volatile storage lane;
- `io.Mmio.Window` byte-window value type;
- allowed lane widths and endian composition rules;
- compile-time and runtime alignment enforcement;
- volatile `load`/`store` operations via Zig's `*volatile T` lowering;
- composition rules with `layout.Le`/`Be` and `stdx.barrier`;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- `io.VolatileCell` — non-MMIO single-value publish/observe primitives;
- `io.Mmio.Slice` — repeated same-type register arrays with a shared stride;
- `io.Mmio.Doorbell` — MMIO writes paired with a release fence;
- `io.PollUntil` — polling helpers with clock-driven timeouts;
- `io.RegisterField` / `io.RegisterFlags` — named bit-range accessors;
- read-modify-write helpers;
- concrete device register maps;
- PCI configuration access, MSI/MSI-X configuration, or IOMMU policy;
- DMA mapping or cache-maintenance policy;
- hardware ordering guarantees between operations on this type;
- endian conversion beyond composition with `layout.Le`/`Be`;
- root exports.

## Public namespace

MMIO primitives live under `stdx.io`:

```zig
stdx.io.Mmio
stdx.io.Mmio.Register
stdx.io.Mmio.Window
```

They are not root-promoted:

```zig
stdx.Mmio // not exported
stdx.io.Register // not exported
```

Source ownership:

```text
src/io.zig
src/io/mmio.zig
test/io/mmio_test.zig
```

`src/io.zig` re-exports:

```zig
pub const mmio = @import("io/mmio.zig");

pub const Mmio = mmio.Mmio;
```

`src/io.zig` is a thin facade. It contains no logic beyond re-exporting and
aliasing.

## Approved API

```zig
pub const Mmio = struct {
    pub fn Register(comptime T: type) type;

    pub const Window = struct {
        base: [*]align(min_align) volatile u8,
        len: usize,

        pub const min_align: usize = @alignOf(u64);
        pub const Error = error{ OutOfBounds, Misaligned };

        pub fn wrap(bytes: []align(min_align) volatile u8) Window;

        pub fn register(
            self: Window,
            comptime T: type,
            offset: usize,
        ) Error!*volatile Register(T);

        pub fn registerUnchecked(
            self: Window,
            comptime T: type,
            offset: usize,
        ) *volatile Register(T);
    };
};
```

Returned type from `Register(T)`:

```zig
pub const Self = extern struct {
    value: T align(@alignOf(T)),

    pub const Native = T;
    pub const width_bytes: comptime_int = @sizeOf(T);

    pub fn load(self: *const volatile Self) T;
    pub fn store(self: *volatile Self, value: T) void;
};
```

`Register(T)` is a factory. The returned type is an `extern struct` with a
single field, so it composes losslessly inside overlay `extern struct`s that
model fixed device register blocks.

`Window` is a byte-window value type. It owns nothing; it borrows the caller's
MMIO byte range.

## Type contract for `Register(T)`

`T` must be one of:

- `u8`, `u16`, `u32`, `u64`;
- `layout.Le(U)` or `layout.Be(U)` where `U` is one of `u8`, `u16`, `u32`, `u64`.

Every other `T` is a compile error.

Rejected `T` categories include:

- signed integers;
- `usize` and `isize`;
- integer widths not in the allowed set (e.g. `u24`, `u40`, `u128`);
- bools;
- floats;
- enums;
- packed structs;
- extern structs other than `Register(T)` itself;
- pointers, slices, optionals, error unions, unions;
- functions.

Non-native integer widths that a device register maps into a byte lane must
compose through an approved `T`. Example:

```zig
// A 24-bit little-endian register stored inside a 32-bit MMIO lane:
const RawReg = stdx.io.Mmio.Register(u32);
const value_24: u24 = @intCast(reg.load() & 0x00FF_FFFF);
```

Endian wrappers compose directly:

```zig
const CapReg = stdx.io.Mmio.Register(stdx.layout.Le(u64));
const cap = reg.load().native();
```

## Layout guarantees

For every allowed `T`:

```zig
@sizeOf(stdx.io.Mmio.Register(T)) == @sizeOf(T)
@alignOf(stdx.io.Mmio.Register(T)) == @alignOf(T)
```

The returned type is an `extern struct` with a single field named `value`. The
field's alignment is `@alignOf(T)`. Consumers may embed `Register(T)` inside an
`extern struct` overlay to model a fixed register block:

```zig
const NvmeRegs = extern struct {
    cap:    stdx.io.Mmio.Register(u64),  // offset 0x00
    vs:     stdx.io.Mmio.Register(u32),  // offset 0x08
    intms:  stdx.io.Mmio.Register(u32),  // offset 0x0C
    intmc:  stdx.io.Mmio.Register(u32),  // offset 0x10
    cc:     stdx.io.Mmio.Register(u32),  // offset 0x14
};
```

The `extern struct` layout rules give the overlay stable offsets; consumers
verify offsets with `@offsetOf` compile-time assertions in their own module.

## `load` and `store` semantics

`load(self: *const volatile Self) T` performs a single volatile load of the
underlying value at the natural width and alignment of `T` and returns it.

`store(self: *volatile Self, value: T) void` performs a single volatile store
of `value` at the natural width and alignment of `T`.

Both operations:

- lower through Zig's `*volatile T` load/store;
- emit exactly one memory access at the target ISA level for allowed `T`
  widths on architectures with matching native access widths;
- carry compiler ordering against other volatile accesses in the same
  translation unit;
- do not emit any ISA-level fence;
- do not synchronize with other CPUs, DMA agents, or other MMIO windows.

Callers pair `load`/`store` with `stdx.barrier.mmio.*` and
`stdx.barrier.dma.*` operations when hardware ordering matters.

## `Window.wrap` semantics

`Window.wrap(bytes)` constructs a `Window` over the caller-owned byte range.

The parameter is `[]align(min_align) volatile u8`. `min_align` is
`@alignOf(u64)`. Callers whose backing pages are not `min_align`-aligned must
narrow the type before calling `wrap` — passing a lesser-aligned slice is a
compile error, not a runtime error.

`wrap` performs no allocation, no copy, no validation of the underlying
memory, and no device access.

## `Window.register` semantics

`Window.register(T, offset) Error!*volatile Register(T)` returns a typed
pointer into the window at `offset`.

Required behavior:

- return `error.OutOfBounds` when `offset + @sizeOf(T) > self.len`;
- return `error.Misaligned` when
  `(@intFromPtr(self.base) + offset) % @alignOf(T) != 0`;
- return a `*volatile Register(T)` on success.

The returned pointer aliases `self.base + offset`. It is valid for the lifetime
of the underlying MMIO mapping. `Window` values are cheap to copy and do not
own the mapping.

## `Window.registerUnchecked` semantics

`Window.registerUnchecked(T, offset) *volatile Register(T)` returns the same
pointer as `register` without bounds or alignment checks.

Callers must have proven bounds and alignment through another mechanism, for
example a `switch` on a comptime-known offset or a prior validated computation.
In debug builds gated by `core.debug.checksEnabled`, the implementation asserts
the same bounds and alignment conditions that `register` returns as errors.

## Composition with barriers

MMIO ordering against DMA payloads and other MMIO accesses is not provided by
`Register` or `Window`. Consumers pair operations with `stdx.barrier`:

```zig
// Submission: build SQE in DMA-visible memory, then ring the doorbell.
build_sqe(&sqe);
stdx.barrier.mmio.release();
sq_tail_reg.store(new_tail);

// Poll a status register with acquire ordering after each load.
while (true) {
    const csts = regs.csts.load();
    stdx.barrier.mmio.acquire();
    if (csts_ready(csts)) break;
}
```

The barrier surface is owned by `docs/specs/barrier/dma.md`.

## Composition with endian wrappers

Device registers whose byte order differs from host native are wrapped:

```zig
const CapReg = stdx.io.Mmio.Register(stdx.layout.Le(u64));

// load returns layout.Le(u64); native() decodes to u64.
const cap = regs.cap.load().native();

// Encode host u32 before storing to a big-endian register.
const be_reg: *volatile stdx.io.Mmio.Register(stdx.layout.Be(u32)) = ...;
be_reg.store(stdx.layout.Be(u32).fromNative(host_value));
```

For x86_64 targets and little-endian device registers, wrapping through
`layout.Le` produces identical machine code to a native `u64` lane; the wrapper
is a byte-order documentation tool rather than a runtime cost.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `Register(T)` | never | never | comptime | none | type factory | validates `T` |
| `Register.load` | never | never | O(1) | none | caller-serialized per register | volatile load; compiler-ordered against other volatile ops |
| `Register.store` | never | never | O(1) | none | caller-serialized per register | volatile store; compiler-ordered against other volatile ops |
| `Window.wrap` | never | never | O(1) | none | value type | none |
| `Window.register` | never | never | O(1) | none | value type | none |
| `Window.registerUnchecked` | never | never | O(1) | none | value type | none |

MMIO primitives perform no heap allocation, sleeping, blocking, hidden
scheduler calls, I/O beyond the volatile access itself, target probing, or
hidden global access.

## Error behavior

- `Register.load` and `Register.store` are infallible.
- `Window.wrap` is infallible; alignment is enforced by the parameter type.
- `Window.register` returns `error.OutOfBounds` when the range exceeds the
  window and `error.Misaligned` when the offset breaks `@alignOf(T)`.
- `Window.registerUnchecked` is infallible in release builds; debug builds
  gated by `core.debug.checksEnabled` assert the same conditions.
- `Register(T)` with a disallowed `T` is a compile error.

## Implementation constraints

Implementation must:

- reject disallowed `T` categories at compile time with `@compileError`;
- define `Register(T)` as an `extern struct` with a single field named `value`
  of type `T align(@alignOf(T))`;
- lower `load` and `store` through `*volatile T` load and store, not through
  inline assembly;
- avoid emitting any ISA-level fence in `load` or `store`;
- avoid read-modify-write helpers;
- keep `Window` free of heap allocation and hidden state beyond `base` and
  `len`;
- reject non-`min_align`-aligned slices in `wrap` at compile time via the
  parameter type;
- avoid introducing dependencies on `stdx.arch.*` — MMIO uses only portable Zig
  volatile lowering;
- provide alignment and bounds checks in `register` in every optimize mode;
- provide the same checks in `registerUnchecked` only under
  `core.debug.checksEnabled`.

## Planned use

NVMe-class controller register blocks — CAP, VS, INTMS, INTMC, CC, CSTS, AQA,
ASQ, ACQ — use `Register(u64)` and `Register(u32)` as an overlay `extern
struct`, and `Window.register(u32, offset)` for the doorbell array at
`0x1000 + (2*queue + kind) * (4 << CAP.DSTRD)`.

Similar shapes appear in fixed-register blocks such as ACPI FADT/MADT,
PCI MSI-X tables, and UEFI runtime services offsets.

## Required tests

Tests use a `[128]u8 align(@alignOf(u64))` scratch buffer as the MMIO
substrate. Runtime semantics of MMIO on real device memory are not testable
from a host binary; these tests exercise the wrapper's compile-time and
run-time contracts.

### `Register(T)` layout

- `@sizeOf(Register(u8)) == 1` and `@alignOf(Register(u8)) == 1`;
- `@sizeOf(Register(u16)) == 2` and `@alignOf(Register(u16)) == 2`;
- `@sizeOf(Register(u32)) == 4` and `@alignOf(Register(u32)) == 4`;
- `@sizeOf(Register(u64)) == 8` and `@alignOf(Register(u64)) == 8`;
- `@sizeOf(Register(layout.Le(u32))) == 4`;
- an `extern struct` composed of `Register(u64)` at offset 0 and
  `Register(u32)` at offset 8 has `@offsetOf(.f0) == 0` and
  `@offsetOf(.f1) == 8`.

### `Register(T)` compile-error surface

- `Register(u7)` is a compile error;
- `Register(u24)` is a compile error;
- `Register(u40)` is a compile error;
- `Register(u128)` is a compile error;
- `Register(usize)` is a compile error;
- `Register(i32)` is a compile error;
- `Register(bool)` is a compile error;
- `Register(f32)` is a compile error;
- `Register([4]u8)` is a compile error;
- `Register(*u32)` is a compile error;
- `Register(?u32)` is a compile error.

### `load` and `store` round-trip

- Round-trip via a scratch buffer for `Register(u8)`, `Register(u16)`,
  `Register(u32)`, `Register(u64)` at aligned offsets;
- `store` followed by `load` returns the stored value;
- successive `store`s overwrite the value;
- distinct `Register` pointers at non-overlapping offsets do not alias.

### Endian composition

- `Register(layout.Le(u32)).store(layout.Le(u32).fromNative(0x1234_5678))`
  followed by a byte-wise inspection sees bytes `{0x78, 0x56, 0x34, 0x12}`;
- `Register(layout.Be(u32)).store(layout.Be(u32).fromNative(0x1234_5678))`
  sees bytes `{0x12, 0x34, 0x56, 0x78}`;
- the same round-trip holds on both little-endian and big-endian test targets.

### `Window.wrap`

- `wrap` returns a window with `len == bytes.len`;
- `wrap` accepts a properly aligned slice on every optimize mode.

### `Window.register`

- `register(u32, 0)` succeeds and returns a pointer aliasing `base`;
- `register(u32, len - 4)` succeeds;
- `register(u32, len - 3)` returns `error.OutOfBounds`;
- `register(u64, len - 8)` succeeds;
- `register(u64, len - 7)` returns `error.OutOfBounds`;
- `register(u32, 3)` returns `error.Misaligned` when `base` is 8-aligned;
- `register(u32, 4)` succeeds when `base` is 8-aligned;
- storing and loading through a pointer returned by `register` observes the
  same bytes as direct access to `base + offset`.

### `Window.registerUnchecked`

- returns a valid pointer for a bounds-checked and alignment-checked offset;
- debug-mode assertion fires for an out-of-bounds offset under
  `core.debug.checksEnabled`;
- debug-mode assertion fires for a misaligned offset under
  `core.debug.checksEnabled`.

### Overlay composition (compile-only)

- An `extern struct` embedding
  `Register(u64), Register(u32), Register(u32), Register(u32), Register(u32)`
  in that order produces field offsets 0, 8, 12, 16, 20 — matching the NVMe
  CAP/VS/INTMS/INTMC/CC layout.

## Open questions

None.
