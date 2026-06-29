# Conventions

Implementation conventions for zstdx source and specs. Terse rules; deviations need a reason in review.

These conventions extend `docs/guidelines/zig.md`.

## Authority order

When rules conflict, follow this order:

1. approved specs under `docs/specs/`;
2. this conventions document;
3. baseline `docs/guidelines/zig.md`;
4. planning notes under `docs/planning/`, which are never authoritative for landed code.

## Spec ownership

Every public module is owned by one spec under `docs/specs/`.

- Source module headers cite the owning spec path.
- A module without an approved owning spec does not land.
- Planning documents do not define public API contracts.
- Specs define contracts; source implements them.

## Directory ownership

Source directory ownership is defined by `docs/specs/architecture.md`.

- `src/core/` — options, traits, debug policy, and shared range primitives.
- `src/bits/` — power-of-two helpers, flags, fields, bitsets, bitmaps.
- `src/addr/` — strong address, size, page, frame, and range types.
- `src/barrier/` — generic compiler, CPU, IO, and DMA ordering surfaces.
- `src/arch/` — architecture-specific CPU and fence helpers.
- `src/layout/` — endian, packed-view, and layout assertion helpers.
- `src/bytes/` — byte cursors, builders, unaligned and bounds-checked byte access, endian readers/writers.
- `src/mem/` — memory alignment, allocators, and memory-resource primitives.
- `src/collections/` — non-intrusive containers.
- `src/intrusive/` — intrusive containers.
- `src/sync/` — synchronization primitives.
- `src/concurrent/` — concurrent queues, rings, deques, and reclamation helpers.
- `src/io/` — volatile and MMIO access wrappers.
- `src/rings/`, `src/tags/`, `src/sg/` — generic descriptor rings, tag pools, and scatter/gather structures.
- `src/diag/` — invariant, trace, panic-safe log, stress, and benchmark helpers.

## File responsibility

Use the baseline ownership rules in `docs/guidelines/zig.md`. zstdx split decisions must follow the owning spec
and the owned mechanic, not file length.

Allowed zstdx split shapes:

- `collections/list.zig` plus `collections/static_list.zig` if the static variant has independent mechanics.
- `barrier.zig`, `barrier/compiler.zig`, `barrier/io_dma.zig` if the contracts differ.
- `arch/x86/fence.zig`, `arch/x86/cpu.zig`.

Disallowed zstdx split shapes:

- `manager.zig` unless the spec owns a type named `Manager`.

## Namespace facades

`src/stdx.zig` is the public package facade. Domain facade files such as `src/bits.zig` may re-export stable
public surfaces for one domain.

Domain facades follow the baseline thin-facade rule in `docs/guidelines/zig.md`. They may:

- import implementation files;
- re-export approved public types, functions, constants, and submodules;
- provide short aliases to declarations owned by implementation files.

Domain facades must not provide wrapper modules around sibling packages.

Implementation modules import each other directly when the owning specs allow the dependency.

Root exports may promote flagship type families (`List`, `Ring`, `HashMap`, ...) after their owning specs approve
the exact surface. The subsystem namespace remains the canonical home.

## Imports and aliases

Use the baseline import and alias rules in `docs/guidelines/zig.md`.

zstdx sorts aliases by alias name unless a small semantic grouping is clearer.

## Comments

Use the baseline comment and module-header rules in `docs/guidelines/zig.md`.

zstdx source comments may cite approved `docs/specs/...` paths only. They must not cite `docs/planning/...`.

## Public API strictness

zstdx public APIs are explicit and domain-neutral. A public surface lands only under the namespace approved by its
owning spec.

Generic primitives must not encode downstream policy. Domain-specific systems belong in downstream packages.

## Naming discipline

zstdx names encode ownership and capacity.

- `Managed` stores an allocator handle and may allocate only where the method contract says so.
- `Unmanaged` requires the caller to pass an allocator to allocating operations.
- `Static` has comptime fixed capacity and never allocates.
- `Bounded` uses caller-provided storage or runtime fixed capacity and never allocates after initialization.
- `View` borrows and does not own.
- `Owned` owns memory or a resource.
- `Handle` is generation-checked when stale-use detection is part of the contract.
- `clearRetainingCapacity` preserves backing storage.
- `clearAndFree` releases backing storage.
- `approxLen` is permitted only when concurrency makes exact length expensive or impossible.

## API grammar

zstdx public names use the baseline Zig naming rules with these package terms:

- namespaces and modules are lower-case domain names: `bits`, `addr`, `mem`, `layout`, `bytes`, `intrusive`;
- type names and type factories are PascalCase: `List`, `BitSet`, `Address`, `BitFlags`;
- runtime functions and methods are lower camel case: `alignUp`, `append`, `pushBack`, `clearRetainingCapacity`;
- acronyms are words unless the owning spec approves an ABI name: `PhysAddr`, `VirtAddr`, `DmaAddr`,
  `MmioRegister`;
- `Static`, `Bounded`, `Managed`, and `Unmanaged` are nested under the family they specialize: `List.Static`, not
  `StaticList`;
- slice exposure uses `asSlice` / `asConstSlice` unless a spec deliberately exposes fields;
- list-like containers use directional verbs `pushBack` / `popFront` / `pushFront` / `popBack` and `front` / `back` accessors;
- stack-like containers push/pop;
- queue, ring, and deque containers use the same directional names: `pushBack`, `popFront`, `pushFront`, `popBack`, `front`, `back`;
- intrusive single-ended containers (`Queue`, `Stack`) follow their family's vocabulary; intrusive doubly-linked lists use the deque vocabulary.

## Constructors

zstdx constructor vocabulary is closed. Pick the verb by argument shape and fallibility:

- `Type.init(...)` — infallible. No allocation, no argument validation. Includes the no-arg form `Type.init()` for inline-storage static containers.
- `Type.initCapacity(allocator, n)` — may allocate or reserve capacity if the owning spec says so.
- `Type.wrap(storage)` — infallible, borrows caller-owned storage. Used by every `Bounded` container and any type that takes a backing buffer at runtime.
- `Type.fromX(input)` — single-input reinterpretation. Use `fromInt`, `fromNative`, `fromBytes`, `fromAddress`, etc. May be infallible (`Type.fromInt(value: Int) Self`) or fallible (`Type.fromAddress(addr: Addr) Error!Self`).
- `Type.fromXY(a, b) Error!Self` — multi-input validating constructor. Pick a domain-specific verb: `fromStartLen`, `fromBounds`, `fromBaseCount`, `fromAddressBytes`.
- `deinit` releases resources owned by the value.

Any constructor that returns an error union is named `from*`, never `init`. There is no `Type.initUnchecked` variant — callers with proven validity use a struct literal.

## Error vocabulary

zstdx uses one canonical name per error condition. Reuse these names across specs; do not invent near-duplicates.

| Error | Meaning |
| --- | --- |
| `Overflow` | Arithmetic over- or under-flow; the saturating value is not representable in `T`. Covers both directions. |
| `OutOfBounds` | Index or offset outside the addressable domain of a value or container. |
| `EndOfStream` | Sequential consumer exhausted past the end of the input. |
| `InvalidAlignment` | Alignment **argument** is malformed: zero or not a power of two. |
| `Misaligned` | A **value** is not aligned to a required boundary. |
| `Full` | Fixed-capacity container has no room. |
| `OutOfMemory` | Allocator-shaped exhaustion; matches the `std.mem.Allocator` convention. |
| `InvalidRange` | Constructor input violates `end >= start`. |
| `Overlap` | Map insertion would overlap an existing entry. |

Specs must not introduce near-duplicates such as `OutOfRange`, `Truncated`, or `Underflow`.

## Error placement

- Free functions in a module → module-level `pub const Error = error{...}`.
- Types with state or methods → nested `pub const Error = error{...}` inside the type or returned namespace.
- Domain facades do not re-export error sets. A caller writes `stdx.bytes.Cursor.Error` or `stdx.mem.alignment.Error`, never `stdx.bytes.Error`.

Per-operation error sets may narrow the type-level union when a method can only produce a subset of variants. The type-level `Error` remains a documentary union over every variant the type can return.

## Predicate return convention

- "is X?" / "has X?" / "contains X?" predicates return plain `bool`. Out-of-domain inputs return `false`; comptime-checkable programmer errors use `std.debug.assert`.
- Mutators that take a runtime index return `Error!void` with `OutOfBounds`.
- Optional lookups return `?T` or `?*T`; do not wrap optional lookups in an error union.

## Capacity vocabulary

Static containers expose their comptime capacity as a `pub const` on the returned type. The constant name uses the singular element noun plus `_capacity`:

- `item_capacity` for element containers (`List.Static`, `Ring.Static`).
- `range_capacity` for range containers (`RangeSet.Static`).
- `entry_capacity` for key-value containers (`RangeMap.Static`).
- `bit_capacity` for bitsets (`BitSet.Static`).

The comptime factory parameter name matches: `comptime capacity_items`, `capacity_ranges`, `capacity_entries`, `capacity_bits`.

Inline-storage containers expose their backing array as `buffer`:

```zig
buffer: [capacity_items]T = undefined,
```

Runtime helpers return `usize`: `len()`, `capacity()`, `remaining()`, `isEmpty()`, `isFull()`. Every static and bounded container exposes the same five helpers; the `count()` name is reserved for set-flavored types where population differs from slot count.

## Set-flavored exception

`BitSet.Static` and any future set-flavored primitive use set semantics:

- `count(self) usize` returns the population (set-element count), not the slot count.
- `<element>_capacity` (e.g. `bit_capacity`) gives the slot count.
- `clearRetainingCapacity(self)` clears every element.
- `setAll(self)` sets every element (paired with `set(index)` / `unset(index)`).
- Set-flavored types do not expose `insert(index)` / `remove(index)`; callers use `set` / `unset`.

## Behavior contract concurrency column

The `Concurrency` column of behavior-contract tables uses one of five closed terms:

| Term | Meaning |
| --- | --- |
| `pure function` | Free function with no receiver state. |
| `value type` | Receiver is a self-contained value with no external storage. |
| `type factory` | The `Static(T, N)` / `Bounded(T)` generic-factory row itself. |
| `caller-owned value` | Static container that owns inline storage. |
| `caller-owned buffer` | Bounded container or other type that borrows external storage. |

No other phrasings are permitted. Specs that need to distinguish read-only from mutable access state that distinction in prose under `## Concurrency and ordering`, not in the column.

## Runtime contracts

zstdx specs use the baseline public-contract checklist in `docs/guidelines/zig.md`.

Primitive specs must state the primitive-specific allocation, waiting, capacity, execution-bound, invalidation, and
ordering rules in their behavior contract tables.

## Barrier and architecture boundaries

zstdx owns generic barriers only when a spec names the compiler, CPU, IO, or DMA contract.

Architecture-specific instructions live under `src/arch/<arch>/` and must document feature requirements.

## Domain neutrality

`zstdx` does not implement domain systems. Generic mechanisms are allowed; policy protocols are not.

Allowed examples:

- typed MMIO register wrapper;
- descriptor ring;
- tag allocator;
- scatter/gather list;
- strong DMA address type.

Disallowed examples:

- PCI enumeration;
- NVMe queue setup;
- ACPI parser;
- UEFI protocol invocation;
- filesystem implementation;
- IOMMU backend;
- hypervisor VMCS/VMCB handling.

## Implementation order per module

Each module lands in this order:

1. owning spec exists and is approved;
2. public type skeletons and compile-time assertions;
3. unit tests for contracts and edge cases;
4. implementation;
5. model, stress, or integration tests where the spec requires them.

A module without its owning spec does not land.
