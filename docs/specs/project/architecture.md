# Architecture

Status: Approved.

`zstdx` uses one public package facade, thin domain facades, domain implementation directories, and a mirrored `test/` tree aggregated by `test/all.zig`.

## What this spec is

This spec defines repository ownership boundaries, dependency direction, architecture isolation, build-module shape, and test aggregation.

## What this spec is not

This spec does not approve an empty file or directory, a public API, or an implementation that lacks an approved owning specification.

## Public namespace and source ownership

`src/stdx.zig` is the public package facade and build module root. `docs/specs/stdx.md` owns its exact public surface.

Each domain uses `src/<domain>.zig` as its facade and `src/<domain>/` for implementation files. A domain facade MAY import implementation files and re-export approved public types, functions, constants, submodules, and aliases. A domain facade MUST NOT allocate, validate input, synchronize, target-probe, select platform policy, implement algorithms, or hide dependencies behind wrapper layers.

Ordinary domain facades MUST NOT be named `root.zig`.

## Data structures and representation

The repository contains `build.zig`, `build.zig.zon`, `README.md`, `docs/`, `src/`, and `test/`. The `docs/` tree contains specifications, planning material, guidelines, and project decisions. The source tree contains `src/stdx.zig`, domain facade files, and implementation directories. The test tree contains hierarchical `all.zig` aggregation facades rooted at `test/all.zig`.

The repository tree is an ownership map, not permission to create empty scaffolding. A file or directory MAY land only when an approved owning specification and implementation slice require it.

## Global invariants

- Each `.zig` file MUST own one concept or one type family. It MAY split by sub-concern only when an owning specification requires the split.
- File names such as `utils.zig`, `helpers.zig`, `common.zig`, and `misc.zig` are not allowed.
- A file named `manager.zig` is allowed only when an approved specification owns a public concept named `Manager`.
- Domain facades MUST contain no logic beyond importing, re-exporting, and aliasing.
- Cross-domain primitive imports MUST be named by the importing specification and MUST preserve an acyclic dependency graph.

## API

The public package facade imports domains through declarations of this form:

```zig
pub const bits = @import("bits.zig");
```

Domain facades export implementation declarations through declarations of this form:

```zig
pub const power_of_two = @import("bits/power_of_two.zig");
pub const isPowerOfTwo = power_of_two.isPowerOfTwo;
```

## Implementation constraints

### Layering

Dependencies MUST follow this direction:

```text
stdx.zig -> domain facades -> implementation files in the same domain
primitive/domain implementations -> core, bits, addr, layout, bytes as needed
primitive/domain implementations -> approved primitive domains only when the owning spec names the dependency and the graph remains acyclic
bytes -> layout, core
layout -> core, bits
addr -> core, bits
dma -> core, addr
bits -> core
barrier -> core, arch
arch -> core
```

- `core` MUST import only `std` and `builtin`.
- `arch` MUST NOT import `barrier`; `barrier` MAY import `arch`.
- `layout` MUST NOT import `bytes`; `bytes` MAY import `layout`.
- Generic modules MUST NOT perform architecture or target probing directly.
- Implementation modules MAY import each other directly only when their owning specifications allow the dependency.

### Architecture isolation

Architecture-specific code MUST exist only under `src/arch/` and MUST be surfaced through `src/arch.zig`. Approved architecture namespaces are `stdx.arch.x86_64`, `stdx.arch.aarch64`, and `stdx.arch.riscv`. `stdx.arch.x86` is not an approved namespace.

Architecture-specific code MUST be target-gated, MUST compile out or expose unsupported behavior on unsupported targets as its owning specification defines, MUST keep inline assembly out of generic modules, and MUST document instruction and feature requirements in its owning specification.

### Build and standard-library use

`build.zig` MUST create the public `stdx` module from `src/stdx.zig`. The default test module MUST import `stdx` from `test/all.zig`. The default test command is `zig build test`.

Library primitives MAY use `std.mem.Allocator`, portable compile-time reflection, and portable builtins including `@sizeOf`, `@alignOf`, `@bitSizeOf`, atomics, and byte swaps. Tests MAY use `std.testing` and test-only allocators and failure allocators.

Library primitives MUST NOT use OS syscalls, thread parking, file IO, environment access, hidden timers, or platform probing without an owning specification.

### Source creation

A source file MAY land only when all of these conditions are true:

1. An approved owning specification exists.
2. The module header cites that specification.
3. The file owns one concept or type family.
4. The tests required by the owning specification land with the implementation slice.
5. The dependency direction conforms to this specification.

## Testing

`test/all.zig` MUST import only immediate domain test facades with comptime imports. Each domain test facade MUST import only its immediate category facades. Each category facade MUST import only its immediate child facades or its own leaf test modules. A leaf test module MUST NOT import another leaf test module. Every leaf test module MUST have exactly one aggregation path from `test/all.zig`.

Test directories MUST mirror source domains and public namespace boundaries. A test-only category MAY group declarations that share one source or specification owner but have no public namespace. Its name MUST identify that ownership boundary. Aggregation facades MUST contain imports only; they MUST NOT contain tests, helpers, fixtures, or assertions.

Local pure-logic tests MAY be in their source file. Multi-module, model, stress, and fixture-driven tests MUST be under `test/`. Aggregation facades prove that every required leaf test is part of the default test build. They do not replace domain tests.
