# Architecture

Status: Approved.

`zstdx` follows a sibling-package layout: one public package facade, thin domain facade files, implementation directories per domain, and a mirrored `test/` tree aggregated by `test/all.zig`.

## Repository shape

Approved top-level shape:

```text
zstdx/
  build.zig
  build.zig.zon
  README.md

  docs/
    specs/
    planning/
    guidelines/
    project-decisions.md

  src/
    stdx.zig

    core.zig
    core/

    bits.zig
    bits/

    addr.zig
    addr/

    layout.zig
    layout/

    bytes.zig
    bytes/

    mem.zig
    mem/

    collections.zig
    collections/

    intrusive.zig
    intrusive/

    ranges.zig
    ranges/

    heaps.zig
    heaps/

    barrier.zig
    barrier/

    arch.zig
    arch/

    sync.zig
    sync/

    concurrent.zig
    concurrent/

    io.zig
    io/

    rings.zig
    rings/

    tags.zig
    tags/

    sg.zig
    sg/

    time.zig
    time/

    algo.zig
    algo/

    diag.zig
    diag/

  test/
    all.zig
```

This tree is an ownership map, not permission to create empty scaffolding. Files and directories land only when required by an approved owning spec and implementation slice.

## Public package facade

`src/stdx.zig` is the public package facade and build module root.

```zig
//! Public stdx facade. Spec: docs/specs/root-exports.md.

pub const core = @import("core.zig");
pub const bits = @import("bits.zig");
pub const addr = @import("addr.zig");
pub const layout = @import("layout.zig");
pub const bytes = @import("bytes.zig");
pub const mem = @import("mem.zig");
pub const collections = @import("collections.zig");
pub const intrusive = @import("intrusive.zig");
```

`src/stdx.zig` may promote flagship families after `docs/specs/root-exports.md` approves the exact surface:

```zig
pub const List = collections.List;
pub const Ring = collections.Ring;
```

## Domain facade pattern

Each domain uses a facade file plus an implementation directory:

```text
src/bits.zig
src/bits/*.zig

src/mem.zig
src/mem/*.zig
```

Domain facades are thin. They may:

- import implementation files;
- re-export approved public types, functions, constants, and submodules;
- provide short aliases to declarations owned by implementation files.

Domain facades must not:

- allocate;
- validate input;
- synchronize;
- target-probe;
- select platform policy;
- implement algorithms;
- hide dependencies behind wrapper layers.

Example facade shape:

```zig
//! Bit primitives. Specs: docs/specs/bits/power-of-two.md and docs/specs/bits/bitflags.md.

pub const power_of_two = @import("bits/power_of_two.zig");
pub const BitFlags = @import("bits/bit_flags.zig").BitFlags;
pub const BitSet = @import("bits/set.zig").BitSet;

pub const isPowerOfTwo = power_of_two.isPowerOfTwo;
pub const nextPowerOfTwo = power_of_two.nextPowerOfTwo;
```

Ordinary domain facades are not named `root.zig`. Use `src/<domain>.zig`.

## First-slice source tree

Only this source tree is eligible before more specs land:

```text
src/
  stdx.zig

  core.zig
  core/
    options.zig
    range.zig
    debug.zig

  bits.zig
  bits/
    power_of_two.zig
    set.zig

  addr.zig
  addr/
    address.zig
    pages.zig

  ranges.zig
  ranges/
    set.zig
    map.zig

  layout.zig
  layout/
    endian.zig

  bytes.zig
  bytes/
    cursor.zig
    unaligned.zig
    access.zig

  mem.zig
  mem/
    arena.zig
    alignment.zig
    pool.zig

  collections.zig
  collections/
    list.zig
    ring.zig

  intrusive.zig
  intrusive/
    list.zig
    queue.zig
    stack.zig
```

Corresponding first-slice test tree:

```text
test/
  all.zig

  core/
    options_test.zig
    range_test.zig
    debug_test.zig

  bits/
    power_of_two_test.zig
    set_test.zig

  addr/
    address_test.zig
    pages_test.zig

  ranges/
    set_test.zig
    map_test.zig

  layout/
    endian_test.zig

  bytes/
    cursor_test.zig
    unaligned_test.zig
    access_test.zig

  mem/
    arena_test.zig
    alignment_test.zig
    pool_test.zig

  collections/
    list_test.zig
    ring_test.zig

  intrusive/
    list_test.zig
    queue_test.zig
    stack_test.zig
```

## File responsibility

Each `.zig` file owns one concept or one type family. Split by sub-concern only when an owning spec requires it.

Approved examples:

```text
bits/power_of_two.zig    isPowerOfTwo, nextPowerOfTwo
bits/bit_flags.zig       BitFlags
mem/alignment.zig        alignUp, alignDown, isAligned
bits/set.zig             BitSet family
addr/address.zig         Address, PhysAddr, VirtAddr
collections/list.zig     List family: Static, Bounded, later Managed/Unmanaged
collections/ring.zig     Ring family
intrusive/list.zig       intrusive.List.SinglyLinked, intrusive.List.DoublyLinked, node mechanics
intrusive/queue.zig      intrusive.Queue
intrusive/stack.zig      intrusive.Stack
```

Avoid premature splits:

```text
collections/static_list.zig
collections/bounded_list.zig
```

Disallowed file names:

```text
utils.zig
helpers.zig
common.zig
misc.zig
```

A file named `manager.zig` is allowed only when the approved spec owns a public concept named `Manager`.

## Layering

Approved dependency direction:

```text
stdx.zig
  -> domain facades

facades
  -> implementation files in the same domain

primitive/domain implementations
  -> core, bits, addr, layout, bytes as needed
  -> other approved primitive domains only when the owning spec names the dependency and the graph remains acyclic

bytes
  -> layout, core

layout
  -> core, bits

addr
  -> core, bits

bits
  -> core

barrier
  -> core, arch

arch
  -> core only
```

Hard rules:

- `core` imports only `std` and `builtin`.
- `arch` does not import `barrier`; `barrier` imports `arch`.
- `layout` does not import `bytes`; `bytes` may import `layout`.
- Generic modules do not target-probe directly.
- Facades contain no logic beyond re-exporting and aliasing.
- Implementation modules import each other directly when the owning specs allow the dependency.
- Cross-domain primitive imports are allowed only when the importing spec names
  the dependency and the dependency graph remains acyclic.

## Architecture isolation

Architecture-specific code lives only under `src/arch/` and is surfaced through `src/arch.zig`.

Approved architecture namespaces:

```zig
stdx.arch.x86_64
stdx.arch.aarch64
stdx.arch.riscv
```

`stdx.arch.x86` is not an approved namespace; the x86_64 architecture spec
owns the `stdx.arch.x86_64` namespace. Add 32-bit x86 only when an owning spec
approves it.

Architecture-specific code must:

- be target-gated;
- compile out or expose unsupported behavior on unsupported targets as specified by its owning spec;
- keep inline assembly out of generic modules;
- document instruction and feature requirements in its owning spec.

Generic modules must not perform architecture or target probing directly.

## Build shape

`build.zig` creates a public module named `stdx` from `src/stdx.zig`.

```zig
const stdx_mod = b.createModule(.{
    .root_source_file = b.path("src/stdx.zig"),
    .target = target,
    .optimize = optimize,
});
```

The default test module imports `stdx`:

```zig
const test_mod = b.createModule(.{
    .root_source_file = b.path("test/all.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{.{ .name = "stdx", .module = stdx_mod }},
});
```

Default command:

```text
zig build test
```

Examples, tools, integration steps, and target-specific build steps are added only when an approved spec or real consumer requires them.

## Test aggregation

`test/all.zig` aggregates tests with comptime imports:

```zig
comptime {
    _ = @import("bits/power_of_two_test.zig");
    _ = @import("bits/bit_flags_test.zig");
    _ = @import("mem/alignment_test.zig");
}
```

Test directories mirror source domains. Unit tests for local pure logic may also live in the source file they test; multi-module, model, stress, and fixture-driven tests live under `test/`.

## Std usage

Approved in library primitives:

- `std.mem.Allocator`;
- portable compile-time reflection;
- portable builtins such as `@sizeOf`, `@alignOf`, `@bitSizeOf`, atomics, and byte swaps.

Approved in tests:

- `std.testing`;
- test-only allocators and failure allocators.

Not approved without an owning spec:

- OS syscalls;
- thread parking;
- file IO in library primitives;
- environment access;
- hidden timers;
- platform probing.

## Source creation gate

A source file may land only when all are true:

1. an approved owning spec exists;
2. the file's module header cites that spec;
3. the file owns one concept or type family;
4. tests required by the owning spec land with the implementation slice;
5. the dependency direction follows this architecture spec.
