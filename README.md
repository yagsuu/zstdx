# zstdx

## Overview

`zstdx` provides domain-neutral primitives for freestanding systems code.

## Features

- **Types and layout:** addresses, pages, frames, ranges, durations, bit
  operations, alignment, endian values, and byte access.
- **Storage and collections:** inline `Static` storage, caller-provided
  `Bounded` storage, allocator-backed arenas, slab allocators, caches, and
  intrusive containers.
- **Synchronization and concurrency:** atomic cells, spin locks, one-time
  initialization, latches, rendezvous, signals, and SPSC/MPSC rings.
- **Hardware-facing primitives:** barriers, MMIO, x86_64 instruction and
  register wrappers, DMA buffers, and scatter/gather lists.
- **Time:** monotonic clocks, deadlines, backoff, rate counters, deadline
  queues, and timer wheels.

## Requirements and platform support

| Item | Support |
| --- | --- |
| Zig | `0.16.0` or later |
| Package | `zstdx` |
| Public module | `stdx` |
| Dependencies | None |
| Runtime | No OS services, heap, or threading runtime required. |
| Architecture | Generic APIs are target-neutral. `stdx.arch` APIs are target-gated. |

## Quick start

Add `zstdx` to your build configuration, then import its module as `stdx`:

```zig
const zstdx = b.dependency("zstdx", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("stdx", zstdx.module("stdx"));
```

```zig
const stdx = @import("stdx");
```

## Common workflows

### Caller-provided FIFO storage

`stdx.collections.Ring.Bounded` is a FIFO around caller provided storage.
Concurrent SPSC and MPSC queues are under `stdx.concurrent`.

```zig
const stdx = @import("stdx");

var storage: [64]u32 = undefined;
var queue = stdx.collections.Ring.Bounded(u32).wrap(&storage);
try queue.pushBack(42);
```

### Strong address types

```zig
const stdx = @import("stdx");

const base = stdx.addr.PhysAddr.fromInt(0x1000);
const aligned = try base.alignUp(4096);
_ = aligned;
```

### Spin locks

`RawSpinLock` provides mutual exclusion by spinning. It does not yield, sleep,
or allocate.

```zig
const stdx = @import("stdx");

var lock = stdx.sync.RawSpinLock.init();
lock.acquire();
defer lock.release();
```

### Delegates, closures, and interfaces

`stdx.dispatch.Delegate(Fn)` borrows a context and calls a function with signature
`Fn`. Use `wrap(&function)` for a free function, `bind(State, &state, &State.run)`
for a context function, or `bindMethod(State, &state, "run")` for a public method.
The bound function takes `*State` before the exact parameters of `Fn` and returns
the exact return type of `Fn`.

Use `call()` for no arguments, `call(value)` for one argument, and
`call(.{ first, second })` for multiple arguments. `callArgs(tuple)` always takes
an argument tuple. Keep the borrowed context alive while a delegate uses it.

`stdx.dispatch.Closure(Fn, capacity_bytes)` stores a copy of its state inline:

```zig
const stdx = @import("stdx");

const Counter = struct {
    value: usize,

    pub fn add(self: *@This(), amount: usize) usize {
        self.value += amount;
        return self.value;
    }
};

test "delegate and closure" {
    var counter: Counter = .{ .value = 0 };
    const delegate = stdx.dispatch.Delegate(fn (usize) usize)
        .bind(Counter, &counter, &Counter.add);
    _ = delegate.call(1);

    var closure = stdx.dispatch.Closure(fn (usize) usize, @sizeOf(Counter))
        .init(Counter, counter, &Counter.add);
    _ = closure.delegateMut().call(2);
}
```

Closure state must fit the capacity and must not require alignment greater than
`@alignOf(usize)`. Keep the closure alive and at a fixed address while a delegate
borrows its state. Resources referenced by the stored state remain caller-managed.

`stdx.dispatch.Interface(Contract).bind(&provider)` constructs a borrowed contract
without allocation. The contract declares `instance: *anyopaque` or
`instance: *const anyopaque`, `vtable: *const Vtable`, and a public `Vtable` struct.
Each vtable field is a required function pointer. Its first parameter is an
erased receiver; zero through three explicit operation arguments follow.
The provider supplies a public method with the same name as each vtable field.
Trailing parameter types and return types must match exactly. Operations use the
default Zig calling convention.

```zig
const stdx = @import("stdx");

const Reader = struct {
    instance: *const anyopaque,
    vtable: *const Vtable,

    pub const Vtable = struct {
        read: *const fn (*const anyopaque) usize,
    };

    pub fn read(self: @This()) usize {
        return self.vtable.read(self.instance);
    }
};

const Value = struct {
    value: usize,

    pub fn read(self: *const @This()) usize {
        return self.value;
    }
};

test "const interface" {
    const value: Value = .{ .value = 42 };
    const reader = stdx.dispatch.Interface(Reader).bind(&value);
    _ = reader.read();
}
```

A const contract requires const erased receivers and const provider receivers.
A mutable contract accepts only a mutable provider pointer. Its operations may
use mutable or const erased receivers; a const erased receiver requires a const
provider receiver. Keep the provider alive and at a fixed address while a
contract borrows it.

## Public API

The public facade is `src/stdx.zig`. It re-exports these namespaces:

| Namespace | Purpose |
| --- | --- |
| `stdx.core` | Debug checks, options, traits, and shared range primitives |
| `stdx.bits`, `stdx.layout`, `stdx.bytes` | Bit operations, layout helpers, and byte access |
| `stdx.addr`, `stdx.ranges`, `stdx.graph` | Strong address types, range structures, and forests |
| `stdx.mem`, `stdx.collections`, `stdx.intrusive`, `stdx.algo` | Memory mechanisms, collections, intrusive structures, and algorithms |
| `stdx.sync`, `stdx.concurrent`, `stdx.barrier` | Synchronization, concurrent structures, and ordering primitives |
| `stdx.arch`, `stdx.io`, `stdx.dma`, `stdx.cpu` | Target wrappers, MMIO, DMA data structures, and per-CPU substrate |
| `stdx.time`, `stdx.tags`, `stdx.dispatch`, `stdx.diag` | Time, tag allocation, delegates and interfaces, and diagnostics |

## Build and test

Run the default suite:

```sh
zig build test
```

Check Zig source format:

```sh
zig fmt --check build.zig src test
```

The default suite runs host tests, supported-target compile fixtures, and
fixtures that reject selected invalid API uses. It requires no external tools.

## Documentation

See [`docs/specs/`](docs/specs/) for public API contracts and
[`docs/guidelines/`](docs/guidelines/) for project conventions.
