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

## Requirements

- Zig **0.16.0 or later**.
- No external dependencies. Freestanding targets supported.
- Hardware-specific APIs require a compatible target.

## Quick start

Add `zstdx` to your build configuration, then import its module:

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

## Public API

Import `stdx` to access the public namespaces.

| Namespace | Provides |
| --- | --- |
| `stdx.core` | Debug checks, options, and type traits |
| `stdx.addr` | Physical and virtual address types |
| `stdx.bits` | Bit operations and bitfields |
| `stdx.bytes` | Byte access and encoding |
| `stdx.layout` | Binary layouts and layout assertions |
| `stdx.ranges` | Range types and range-based structures |
| `stdx.mem` | Memory operations and allocators |
| `stdx.collections` | Non-intrusive collections |
| `stdx.intrusive` | Intrusive lists, queues, stacks, and heaps |
| `stdx.algo` | Algorithms over caller-provided storage |
| `stdx.graph` | Forest structures |
| `stdx.sync` | Locks and synchronization primitives |
| `stdx.concurrent` | Concurrent queues and reclamation mechanisms |
| `stdx.barrier` | Memory ordering and barriers |
| `stdx.arch` | Architecture-specific instructions and hardware definitions |
| `stdx.io` | Memory-mapped I/O |
| `stdx.dma` | DMA buffers and scatter/gather structures |
| `stdx.cpu` | Per-CPU storage and access |
| `stdx.dispatch` | Delegates, closures, and vtable-based interfaces |
| `stdx.time` | Time types and operations |
| `stdx.tags` | Tag allocation |
| `stdx.diag` | Diagnostics |

## Build and test

Run the default suite:

```sh
zig build test
```

## Usage examples

### Arena-backed workspace

```zig
const std = @import("std");

const stdx = @import("stdx");

const Arena = stdx.mem.alloc.Arena.Bounded;

fn checksumBatch(arena: *Arena, frames: []const []const u8) !u64 {
    const checkpoint = arena.mark();
    defer arena.restore(checkpoint);

    var checksum: u64 = 0;
    for (frames) |frame| {
        const buffer = try arena.allocBytes(frame.len / 2);
        const decoded = try std.fmt.hexToBytes(buffer, frame);
        checksum = std.hash.Wyhash.hash(checksum, decoded);
    }

    return checksum;
}

var storage: [4096]u8 = undefined;
var arena = Arena.wrap(&storage);
const checksum = try checksumBatch(&arena, &.{ "48656c6c6f", "20776f726c64" });
```

### Typed register update

```zig
const stdx = @import("stdx");

const Mode = enum(u2) { polling, interrupt, _ };
const Control = stdx.bits.BitField(u32, .{
    .enabled = bool,
    .mode = Mode,
    .burst = .{ .offset = 8, .type = u4 },
});

fn configureDevice(registers: stdx.io.Mmio.Window) !void {
    // Ordinary read/write configuration register.
    const control = try registers.regMut(Control.Word, 0x10);
    const updated = Control.replace(control.load(), .{
        .enabled = true,
        .mode = .interrupt,
        .burst = 8,
    });
    control.store(updated);
}
```

### Dispatch

`stdx.dispatch` provides callbacks and interfaces for caller-defined types.

- **`Delegate(Fn)`** binds a callback to an existing instance.
- **`Closure(Fn, capacity)`** stores a copy of the callback's state inline and exposes it through `delegateMut()`.
- **`Interface(Contract)`** generates a vtable that binds a provider's methods to a caller-defined interface.

#### Queued jobs

```zig
const std = @import("std");

const stdx = @import("stdx");

const Worker = struct {
    input: []const u8,
    checksum: u64 = 0,

    pub fn run(self: *Worker) void {
        self.checksum = std.hash.Wyhash.hash(0, self.input);
    }
};

const Run = stdx.dispatch.Delegate(fn () void);
const Job = struct {
    node: stdx.intrusive.List.SinglyLinkedNode = .{},
    run: Run,
};

var worker: Worker = .{ .input = "payload" };
var job: Job = .{ .run = Run.bind(Worker, &worker, &Worker.run) };

var queue = stdx.intrusive.Queue(Job, "node").init();
defer queue.clear();

queue.pushBack(&job);

while (queue.popFront()) |next| {
    next.run.call();
}
```

#### Output backend

```zig
const Writer = struct {
    instance: *anyopaque,
    vtable: *const Vtable,

    pub const Error = error{ NoSpace, WriteFailed };
    pub const Vtable = struct {
        write: *const fn (*anyopaque, []const u8) Error!void,
        flush: *const fn (*anyopaque) Error!void,
    };

    pub fn write(self: Writer, bytes: []const u8) Error!void {
        return self.vtable.write(self.instance, bytes);
    }

    pub fn flush(self: Writer) Error!void {
        return self.vtable.flush(self.instance);
    }
};

const writer = stdx.dispatch.Interface(Writer).bind(&buffered);
try writer.write("ready\n");
try writer.flush();
```

## Documentation

See [`docs/specs/`](docs/specs/) for public API contracts and
[`docs/guidelines/`](docs/guidelines/) for project conventions.
