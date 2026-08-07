# Panic-safe ring log

Status: Approved.

`stdx.diag.PanicLog` is a static byte-ring sink for panic and NMI writers. A writer publishes one length-prefixed byte message or drops on contention. One reader drains published payloads to a `*std.Io.Writer` without blocking writers.

## What this spec is

This specification defines `stdx.diag.PanicLog`, its static byte ring, message format, writer seat, overwrite and drop accounting, single-reader drain and resynchronization, atomic publication, execution-context safety, validation, and required verification.

## What this spec is not

This specification does not define payload formatting, severity, filtering, structured payloads, timestamps, persistence, rotation, mirroring, `std.log` integration, multiple readers, writer iteration, per-frame reader introspection, cross-CPU flush ordering, or a `Bounded` variant. A caller that requires cross-CPU cache maintenance composes with `stdx.barrier.*`. `docs/specs/diag/diagnostic.md` defines scoped error context, not panic-safe logging.

## Public namespace and source ownership

The public names are `stdx.diag.PanicLog`, `stdx.diag.PanicLog.Static`, and `stdx.diag.PanicLog.DrainState`.

The implementation is `src/diag/panic_log.zig`. The required tests are in `test/diag/panic_log_test.zig`. `src/diag.zig` is a thin facade that re-exports `PanicLog`.

## Data structures and representation

`PanicLog.Static(capacity_bytes)` returns a type with inline byte storage, a cache-padded `head`, and atomic `tail`, `seat`, `seq`, and `dropped_seq` fields. The public field layout is not guaranteed.

The byte ring stores variable-size, byte-packed frames with no inter-frame padding. `head` and `tail` are monotonic byte positions; their byte offsets are each position modulo `capacity_bytes`. A frame may wrap across the end of the byte array.

Each frame has exactly this little-endian representation:

```text
offset 0: u32 len       payload length in bytes
offset 4: u32 seq_low   low 32 bits of the frame sequence
offset 8: bytes         exactly len payload bytes
```

`header_bytes` is `8`. The implementation stores both header fields with `stdx.layout.Le(u32)` so a memory dump has the same byte order on every host. `DrainState.next_seq` identifies the next sequence to drain; `DrainState.dropped_snapshot` records the last observed drop count.

## Global invariants

- `capacity_bytes` MUST be at least `2 * header_bytes` and no greater than `std.math.maxInt(u32)`; invalid capacity is a compile error.
- `header_bytes` is `8`, `capacity_bytes_const` equals the factory argument, and `max_payload_bytes` is `capacity_bytes - header_bytes`.
- A stored frame has `len` in `1 .. max_payload_bytes`.
- `seq` increases once for each successful `write`.
- `dropped_seq` increases once for each `WriterBusy` result and once for each whole frame overwritten for capacity.
- Writers overwrite only whole frames. The ring never exposes a partial published frame.
- At most one writer holds the seat. The reader is one logical instance.
- `PanicLog` owns all ring storage and performs no heap allocation.

## API

```zig
pub const PanicLog = struct {
    pub fn Static(comptime capacity_bytes: usize) type;

    pub const DrainState = struct {
        next_seq: u64 = 1,
        dropped_snapshot: u64 = 0,

        pub fn init() DrainState;
    };
};
```

`Static(capacity_bytes)` returns a type with:

```zig
pub const Error = error{
    WriterBusy,
    PayloadTooLarge,
    EmptyPayload,
};

pub const header_bytes: usize = 8;
pub const capacity_bytes_const: usize = capacity_bytes;
pub const max_payload_bytes: usize = capacity_bytes - header_bytes;

pub fn init() Self;
pub fn clear(self: *Self) void;
pub fn write(self: *Self, payload: []const u8) Error!void;
pub fn drain(self: *Self, reader_state: *DrainState, sink: *std.Io.Writer) std.Io.Writer.Error!void;
pub fn dropped(self: *const Self) u64;
pub fn published(self: *const Self) u64;
pub fn isSeated(self: *const Self) bool;
pub fn isValid(self: *const Self) bool;
pub fn assertValid(self: *const Self) void;
```

There is no formatting parameter, timestamp field, `Bounded` variant, writer iterator, or per-frame reader introspection.

## Operations

### `init` and `clear`

`init()` creates an empty ring with zeroed storage, `head`, `tail`, `seq`, and `dropped_seq` equal to zero, and a free seat.

`clear()` resets the same state and zeroes byte storage. A caller MUST call `clear()` only when no writer holds the seat and no reader is draining. `clear()` does not allocate or release the inline storage.

### `write`

`write(payload)` MUST return `error.EmptyPayload` without state change when `payload.len == 0`. It MUST return `error.PayloadTooLarge` without state change when `payload.len > max_payload_bytes`.

For an otherwise valid payload, `write` attempts exactly one `cmpxchgStrong(seat, 0, 1, .acquire, .monotonic)`. If acquisition fails, it MUST increment `dropped_seq` with release ordering and return `error.WriterBusy`.

While holding the seat, the writer MUST:

1. Compute `needed = header_bytes + payload.len`.
2. Evict oldest frames until the free byte capacity is at least `needed`. For each eviction, it advances `tail` by that complete frame length and increments `dropped_seq` with release ordering.
3. Compute the next sequence value.
4. Write the header and payload at `head`, wrapping when necessary.
5. Release-publish the advanced `head` and the new `seq`.
6. Release the seat.

The writer never spins, waits, yields, allocates, invokes a callback, calls a scheduler, or calls a syscall. A writer that terminates after acquiring the seat and before releasing it leaves the ring seated; recovery is outside this contract.

### `drain`

Only one logical reader MAY call `drain` for a `PanicLog` at one time. `drain` does not block writers, allocate, acquire the writer seat, or change the ring. It emits payload bytes only, without headers.

The reader acquire-loads `seq` and `dropped_seq`. If `dropped_seq` differs from `reader_state.dropped_snapshot`, it MUST write one drop marker, update `dropped_snapshot`, set `next_seq` to the oldest surviving sequence, and restart its drain iteration. The marker is exactly:

```text
... N messages dropped ...\n
```

`N` is the decimal difference between the observed and saved drop counts.

When no unobserved drop exists, the reader returns if `next_seq > seq`. Otherwise it finds the frame for `next_seq` by traversing from `tail`, reads its length, emits its payload with wrap handling, and advances `next_seq`. If `dropped_seq` advances during this work, the reader discards the current traversal state and resynchronizes through the drop-marker path.

The oldest surviving sequence is reconstructed from the stored `seq_low` and a current `seq` snapshot. This is unambiguous because `capacity_bytes <= std.math.maxInt(u32)` bounds the number of live frames below `2^32`.

`drain` propagates sink errors unchanged. A sink error can leave `DrainState` at its last completed transition; a caller can retry with the same state.

### Queries and validation

`dropped()`, `published()`, and `isSeated()` perform acquire loads and do not allocate or wait. `published()` reports successful writes. `dropped()` reports both contention drops and whole-frame overwrite drops.

`isValid()` checks the structural invariants and returns a boolean. `assertValid()` asserts `isValid()`. Neither operation is safe while a writer races with it; the caller MUST quiesce the ring before validation.

## Atomic publication and execution contexts

The successful seat CAS is acquire, and releasing the seat is release. The writer release-stores `tail` after an eviction, `head` after it copies a complete frame, `seq` after it publishes the new sequence, and `dropped_seq` after a drop. The reader uses acquire loads for those published values. The release store to `head` and its acquire observation prevent a reader from observing a frame before the writer copies its header and payload.

The writer is safe from IRQ, NMI, MCE, and nested interrupt preemption. A nested or concurrent writer that finds the seat held returns `error.WriterBusy` and accounts for the drop. The single-attempt seat acquisition prevents writer byte interleaving and avoids waiting in panic contexts. The reader is not NMI-safe. A caller MUST NOT drain from an interrupt or panic context that can preempt a writer.

Cross-CPU cache-maintenance and flush ordering are outside this type; a caller that requires them MUST use the applicable `stdx.barrier.*` composition.

## Implementation constraints

The implementation MUST use inline storage, the fixed frame header, whole-frame eviction, and single-attempt seat acquisition. It MUST release-publish a completed frame before a reader can emit its payload. It MUST preserve a coherent reader state by detecting a concurrent `dropped_seq` advance and resynchronizing before further traversal.

## Testing

Tests MUST verify the frame representation: compile-time capacity boundaries, public constants, little-endian header bytes, payload length boundaries, non-power-of-two capacity, wrapping, and cache-padding size and alignment constraints. These tests prove the fixed dump format and static-storage contract.

Tests MUST verify normal and failure writes: sequential payload order, an exact maximum payload, empty and oversized payload rejection without state change, contention rejection with one counted drop, and whole-frame overwrite with the oldest frame removed. These boundary and failure tests prove that truncation occurs only at message boundaries and that counters distinguish publication from drops.

Tests MUST drain sequential frames, verify the exact drop marker and reader-state transitions, and simulate a `dropped_seq` advance while draining. The resynchronization test MUST confirm that the reader emits the marker and restarts at the oldest surviving frame after concurrent overwrite accounting changes.

Tests MUST validate fresh, exercised, and intentionally corrupted ring states. They MUST confirm that invalid head and drop-counter states fail validation. These tests prove that `isValid` and `assertValid` detect structural corruption when the caller has quiesced the ring.

Concurrency tests MUST force seat contention, model NMI preemption while a writer holds the seat, and run concurrent writers while periodically draining. They MUST verify that each writer attempt either publishes or returns `error.WriterBusy`, that `dropped()` includes all observed busy drops plus any overwrite drops, and that draining does not block writers. These methods prove the no-wait writer and concurrent-publication contract without requiring a timing assumption.
