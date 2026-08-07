# IO MMIO register

Status: Approved.

`stdx.io.MMIO.Register(T)` provides typed volatile access to one memory-mapped register lane. `stdx.io.MMIO.Window` borrows an MMIO byte range and produces typed register pointers at checked offsets.

## What this spec is

This spec defines the `stdx.io.MMIO` namespace, supported register-lane types, register representation, volatile access, borrowed-window lifetime, bounds and alignment checks, compiler ordering, barrier composition, and required verification.

## What this spec is not

This spec does not define device register maps, register-field policy, read-modify-write helpers, PCI configuration, DMA mapping, cache maintenance, or hardware ordering. `docs/specs/barrier/dma.md` owns the barrier operations that callers use when hardware ordering is required. This spec does not promote MMIO declarations to `stdx`.

## Terminology

- **Register lane:** One `Register(T)` object accessed at the width and alignment of `T`.
- **Window:** A non-owning `Window(min_align_bytes)` value over a caller-owned MMIO mapping.
- **Volatile access:** A Zig load or store through a `*volatile T` access path.

## Public namespace and source ownership

The public namespace is `stdx.io.MMIO`, with `stdx.io.mmio` as the module facade.

```text
src/io.zig
src/io/mmio.zig
test/io/mmio_test.zig
```

`src/io.zig` re-exports `mmio` and `MMIO`. The facade contains no implementation logic.

## Cross-spec relationships

`Register(T)` accepts the endian wrappers defined by `docs/specs/layout/endian.md`. `Register.load` and `Register.store` do not provide hardware ordering. A caller that requires ordering between MMIO, DMA-visible memory, or other MMIO operations MUST use the applicable operation from `docs/specs/barrier/dma.md`.

## Data structures and representation

`Register(T)` returns an `extern struct` with exactly one field:

```zig
pub const Self = extern struct {
    value: T align(@alignOf(T)),

    pub const Native = T;
    pub const width_bytes: comptime_int = @sizeOf(T);

    pub fn load(self: *const volatile Self) T;
    pub fn store(self: *volatile Self, value: T) void;
};
```

For every accepted `T`:

```zig
@sizeOf(stdx.io.MMIO.Register(T)) == @sizeOf(T)
@alignOf(stdx.io.MMIO.Register(T)) == @alignOf(T)
```

`Window(min_align_bytes)` returns a value type with a `[*]align(min_align) volatile u8` base pointer and a `usize` byte length. It owns neither the mapping nor its lifetime. Copying a `Window` does not copy mapping storage or extend mapping lifetime.

## Global invariants

- MMIO primitives MUST NOT allocate, lock, sleep, block, call a scheduler, probe a target, or access hidden global state.
- `Register.load` and `Register.store` are the only operations in this API that access the mapped device memory.
- A pointer returned by `Window.register`, `Window.field`, or `Window.registerUnchecked` aliases `base + offset` and remains valid only while the caller keeps the underlying mapping valid.
- The caller MUST serialize conflicting accesses to a register. This API provides no CPU-to-CPU, DMA-agent, or device synchronization.
- All checked window failures occur before pointer creation. A failed checked operation does not mutate the window or mapped memory.

## API

```zig
pub const MMIO = struct {
    pub const default_align: usize = @alignOf(u64);

    pub fn Register(comptime T: type) type;
    pub fn Window(comptime min_align_bytes: usize) type;

    pub const Window64 = Window(@alignOf(u64));
    pub const Window32 = Window(@alignOf(u32));
};
```

`MMIO.default_align` equals `@alignOf(u64)`. `MMIO.Window64` equals `MMIO.Window(@alignOf(u64))`. `MMIO.Window32` equals `MMIO.Window(@alignOf(u32))`.

### `Register(T)`

`T` MUST be one of the following:

- `u8`, `u16`, `u32`, or `u64`;
- `layout.Le(U)` or `layout.Be(U)`, where `U` is one of those unsigned integer types; or
- a `packed struct(uN)` whose backing integer is `u8`, `u16`, `u32`, or `u64`.

Any other `T` MUST produce `@compileError`. This includes signed integers, pointer-sized integers, unsupported integer widths, booleans, floating-point values, arrays, pointers, optionals, error unions, functions, unions, enums, unpacked structs, and packed structs with any other backing integer.

`load` performs one volatile load of `T`. `store` performs one volatile store of `value`. Both operations use the natural width and alignment of `T`.

The operations are compiler-ordered against other volatile accesses in the same translation unit. They MUST NOT emit an ISA fence. They do not order hardware access, synchronize CPUs, synchronize DMA agents, or provide atomic read-modify-write behavior.

For endian-wrapper lanes, `load` returns the wrapper type and `store` accepts the wrapper type. The caller uses the wrapper API to convert between the device representation and native values. Packed-struct bit layout is the Zig packed-struct representation; this spec does not assign device bit meanings.

### `Window(min_align_bytes)`

`min_align_bytes` MUST be a non-zero power of two. Any other value MUST produce `@compileError`.

The returned type provides:

```zig
pub const Self = struct {
    base: [*]align(min_align) volatile u8,
    len: usize,

    pub const min_align: usize = min_align_bytes;
    pub const Error = error{ OutOfBounds, Misaligned };

    pub fn wrap(bytes: []align(min_align) volatile u8) Self;
    pub fn byteLen(self: Self) usize;
    pub fn register(self: Self, comptime T: type, offset: usize) Error!*volatile Register(T);
    pub fn field(
        self: Self,
        comptime Layout: type,
        comptime field_name: []const u8,
    ) Error!*volatile Register(@FieldType(Layout, field_name));
    pub fn registerUnchecked(
        self: Self,
        comptime T: type,
        offset: usize,
    ) *volatile Register(T);
};
```

#### `wrap`

`wrap` borrows `bytes` without allocation, copying, validation, or device access. The parameter alignment enforces the window's minimum alignment at compile time. A caller MUST provide a slice whose declared alignment is at least `min_align`; a lesser-aligned slice does not type-check.

#### `byteLen`

`byteLen` returns the borrowed byte extent unchanged.

#### `register`

`register(T, offset)` accepts only a `T` accepted by `Register(T)`. It also requires `@alignOf(T) <= min_align_bytes`; an over-aligned lane is rejected at compile time.

The operation MUST return `error.OutOfBounds` when `@sizeOf(T) > self.len` or `offset > self.len - @sizeOf(T)`. The second check MUST occur only after the first check, so no `usize` addition or subtraction overflows.

The operation MUST return `error.Misaligned` when `(@intFromPtr(self.base) + offset) % @alignOf(T) != 0`. Otherwise, it returns `*volatile Register(T)` at `base + offset`.

#### `field`

`field(Layout, field_name)` treats `Layout` as an overlay anchored at the window base and delegates its runtime checks to `register`. `Layout` MUST have `field_name`. The field type MUST be accepted by `Register`. The operation uses `@offsetOf(Layout, field_name)` as the offset and `@FieldType(Layout, field_name)` as `T`.

At compile time, the operation MUST reject a missing field and a field whose `@offsetOf` plus size exceeds `@sizeOf(Layout)`. The operation otherwise has the same bounds, alignment, aliasing, lifetime, and error contract as `register`.

#### `registerUnchecked`

`registerUnchecked(T, offset)` returns the same pointer that a successful `register(T, offset)` returns. The caller MUST establish the accepted type, bounds, and address alignment before the call.

When `stdx.core.debug.checksEnabled(.build_mode)` is true, the operation asserts the same bounds and alignment conditions enforced by `register`. When the check is false, it performs unchecked pointer arithmetic. A caller MUST NOT rely on debug assertions for release-mode validation.

## Implementation constraints

The implementation MUST use Zig volatile lowering for `load` and `store`; it MUST NOT use inline assembly. It MUST preserve the `Register(T)` representation and the checked-operation order stated above. `Window` state is limited to its base pointer and length. `field` performs its layout checks at compile time and delegates all runtime validation to `register`.

## Testing

Host tests use aligned ordinary byte buffers as a model of mapped storage. They verify wrapper representation, pointer arithmetic, byte representation, and volatile load/store behavior. They do not prove device side effects, bus transactions, ISA instruction counts, or hardware ordering; those properties require target-specific inspection and hardware validation.

Compile-fail checks MUST instantiate rejected register types, invalid window alignments, over-aligned window lanes, missing fields, and invalid field layouts. Each check proves the API rejects an invalid compile-time shape; it cannot exercise a runtime error path.

Boundary tests MUST cover the first valid offset, the last offset that fits exactly, the first offset that exceeds the window, and an extreme `usize` offset. These tests prove the subtraction-based bounds check prevents overflow before address arithmetic. Alignment tests MUST cover aligned and misaligned runtime addresses and the declared-alignment requirement of `wrap`.

Representation tests MUST verify each supported lane width, endian-wrapper bytes, packed-struct lanes, and offsets in an `extern struct` overlay. They prove the public layout and host-model byte representation, not a device protocol.

State and error tests MUST verify that `register` and `field` return `error.OutOfBounds` and `error.Misaligned` as applicable, and that a successful returned pointer aliases the model buffer. Debug-mode tests MUST verify the checked `registerUnchecked` path for valid input and, where the test harness can isolate a trap, invalid input. A normal Zig unit-test process cannot continue after an assertion trap, so it cannot prove post-trap behavior.
