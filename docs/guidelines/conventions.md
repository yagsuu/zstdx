# Conventions

Implementation conventions for zstdx source and API contracts. Terse rules; deviations need a reason in review.

These conventions extend `docs/guidelines/zig.md`.

## Authority order

When rules conflict, follow this order:

1. published API contracts under `docs/api/`;
2. this conventions document;
3. baseline `docs/guidelines/zig.md`;
4. planning notes under `docs/planning/`, which are never authoritative for landed code.

## Contract ownership and writing

Public primitive behavior has an owning contract under `docs/api/`; a family
contract covers all variants. Re-export-only facades do not need separate pages.
Facade documentation identifies its domain without copying the exported surface.

Contract review, content, and reference maintenance follow
`docs/guidelines/api-writing.md`. Resolve unresolved public behavior before
implementation; planning documents do not define production contracts.

## Dependencies

- Cross-category dependencies MUST be explicit in the build-module graph, named
  by the importing behavior's contract, and acyclic.
- Implementations import categories directly, not through the `stdx` facade.
- `core` imports only `std` and `builtin`.
- `arch` MUST NOT import `barrier`; `barrier` may import `arch`.
- `layout` MUST NOT import `bytes`; `bytes` may import `layout`.

## File responsibility

Use the baseline ownership rules in `docs/guidelines/zig.md`. zstdx split decisions must follow the owning contract
and the owned mechanic, not file length.

Do not add catch-all files such as `utils.zig`, `helpers.zig`, `common.zig`, or
`misc.zig`. Use `manager.zig` only for a public concept actually named `Manager`.

## Namespace facades

Facades re-export declarations without wrappers or domain logic.
Subsystem namespaces remain canonical.

Export removals and renames MUST migrate all callers. Do not retain compatibility
aliases or deprecated names.

## Imports and aliases

Use the baseline import and alias rules in `docs/guidelines/zig.md`.

zstdx sorts aliases by alias name unless a small semantic grouping is clearer.

## Comments

Use the baseline comment and module-header rules in `docs/guidelines/zig.md`.

API documentation links to source declarations. Omit reverse path citations from
implementation headers; keep useful behavior, invariant, and safety comments.
Source comments must not cite temporary planning documents.

## Public API strictness

zstdx public APIs are explicit and domain-neutral. A public surface lands only under the namespace defined by its
owning contract.

Generic primitives must not encode downstream policy. Domain-specific systems belong in downstream packages.
Free functions are limited to stateless algorithms and type factories.
Constructors and stateful operations belong to the type they affect.

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
- `Small` is not a general category; inline storage with spill requires its own
  explicit allocation contract.

## API grammar

zstdx public names use the baseline Zig naming rules with these package terms:

- namespaces, modules, and operation families are lower-case domain names: `bits`, `addr`, `mem`, `layout`,
  `bytes`, `intrusive`, `barrier.mmio`, `arch.x86_64.registers.cr0`;
- type names, type families, and type factories are PascalCase: `List`, `BitSet`, `Address`, `BitFlags`,
  `Mmio`, `ScatterGather`, `Page`, `Clock.Monotonic`;
- the split is by declaration role, not by ownership: `Entry`, `Root`, `Result`, and `Mode` are PascalCase
  even when they own no memory; `cpu.tlb`, `registers.cr0`, and `barrier.dma` are lower-case even
  when they access or mutate architectural state;
- a `struct` used only to group operations is a namespace and uses lower-case. A PascalCase `struct`
  must be a type, type family, or type factory that callers may name as a value shape or generic parameter;
- runtime functions and methods are lower camel case: `alignUp`, `append`, `pushBack`, `clearRetainingCapacity`;
- fields, option names, enum tags, and public constants are snake_case unless an owning contract defines an ABI
  spelling. Zig error-set tags use the PascalCase names listed in the error vocabulary below;
- acronyms are words unless the owning contract defines an ABI name: `PhysAddr`, `VirtAddr`, `DmaAddr`,
  `MmioRegister`;
- `Static`, `Bounded`, `Managed`, and `Unmanaged` are nested under the family they specialize: `List.Static`, not
  `StaticList`;
- slice exposure uses `asSlice` / `asConstSlice` unless a contract deliberately exposes fields;
- list-like containers use directional verbs `pushBack` / `popFront` / `pushFront` / `popBack` and `front` / `back` accessors;
- stack-like containers push/pop;
- queue, ring, and deque containers use the same directional names: `pushBack`, `popFront`, `pushFront`, `popBack`, `front`, `back`;
- intrusive single-ended containers (`Queue`, `Stack`) follow their family's vocabulary; intrusive doubly-linked lists use the deque vocabulary.

Collection APIs SHOULD expose applicable length, capacity, empty/full, clearing,
and invariant-validation operations unless their owning contract defines a
narrower surface. Intrusive memberships require distinct embedded nodes.

## Callback contracts

Callback APIs use the [core callback traits](../api/core/traits.md).
Consumers MUST use `lessThan`, `compare`, `eql`, `hash`, `context`, `lhs`, `rhs`,
and `value` for the corresponding concepts unless the contract defines a
stronger domain term. Callback option types MUST derive from explicit context
and value types. Consumers MUST preserve the trait names, pointer operands,
context semantics, and comptime-default rule unless their contract explicitly
overrides them. The consumer owns option placement and factory signatures.

Context-free callbacks MUST use `void`; mutable or large context SHOULD use a
pointer type. Consumers SHOULD accept comptime-known `fn` values. Callback
option fields MUST be `comptime` unless the consumer explicitly defines runtime
storage using function-pointer types. Each consumer MUST document context
storage and lifetime, invocation order, and whether callbacks may allocate or wait.

## Standard-library boundaries

Sequential byte access MUST use `std.Io.Reader` or `std.Io.Writer`. Fixed-window
value conversion MUST use `std.mem`.

## Constructors

zstdx constructor vocabulary is closed. Pick the verb by argument shape and fallibility:

- `Type.init(...)` — infallible. No allocation, no argument validation. Includes the no-arg form `Type.init()` for inline-storage static containers.
- `Type.initCapacity(allocator, n)` — may allocate or reserve capacity if the owning contract says so.
- `Type.wrap(storage)` — infallible, borrows caller-owned storage. Used by every `Bounded` container and any type that takes a backing buffer at runtime.
- `Type.fromX(input)` — single-input reinterpretation. Use `fromInt`, `fromNative`, `fromBytes`, `fromAddress`, etc. May be infallible (`Type.fromInt(value: Int) Self`) or fallible (`Type.fromAddress(addr: Addr) Error!Self`).
- `Type.fromXY(a, b) Error!Self` — multi-input validating constructor. Pick a domain-specific verb: `fromStartLen`, `fromBounds`, `fromBaseCount`, `fromAddressBytes`.
- `deinit` releases resources owned by the value.

Any constructor that returns an error union is named `from*`, never `init`. There is no `Type.initUnchecked` variant — callers with proven validity use a struct literal.

## Error vocabulary

zstdx uses one canonical name per error condition. Reuse these names across contracts; do not invent near-duplicates.

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

Contracts must not introduce near-duplicates such as `OutOfRange`, `Truncated`, or `Underflow`.

## Error placement

- Free functions in a module → module-level `pub const Error = error{...}`.
- Types with state or methods → nested `pub const Error = error{...}` inside the type or returned namespace.
- Namespace facades may re-export a module-level error set when they re-export the free functions that return it. A caller writes `stdx.bytes.Error`.

Per-operation error sets may narrow the type-level union when a method can only produce a subset of variants. The type-level `Error` remains a documentary union over every variant the type can return.

## Predicate return convention

- "is X?" / "has X?" / "contains X?" predicates return plain `bool`. Out-of-domain inputs return `false`; comptime-checkable programmer errors use `std.debug.assert`.
- Mutators that take a runtime index return `Error!void` with `OutOfBounds`, unless the success path is idempotent: bit-flag mutators on a state-bearing slot (e.g. `BitSet.set`/`unset`/`assign`) may return `Error!bool` carrying the prior bit value so callers can detect a no-op transition without a second read. A `toggle`-style mutator that always changes state returns the **new** value instead.
- Mutators that already encode change through their error set (e.g. `BitmapAllocator.reserveOne` → `error.AlreadyAllocated`, `RangeSet.insert` → `error.Overlap`) must not also return a prior-value bool: the error is the change signal.
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

## Runtime contracts

API contracts use the baseline public-contract checklist in `docs/guidelines/zig.md`.
State applicable allocation, waiting, capacity, execution-bound, invalidation,
and ordering guarantees without requiring a behavior table.

## Barrier and architecture boundaries

zstdx owns generic barriers only when a contract names the compiler, CPU, IO, or DMA guarantees.

Architecture-specific code lives under `src/arch/`; inline assembly stays out of
generic modules. Generic modules MUST NOT probe architecture or targets directly.
Hardware contracts define instruction, feature, privilege, and unsupported-target
behavior; implementations MUST gate target-specific code accordingly.

## Domain neutrality

The [README](../../README.md#overview) defines the mechanism-versus-policy boundary.
Hardware formats and programming primitives are permitted; device drivers,
protocol orchestration, mapping policy, VM-exit dispatch, and scheduler policy
remain downstream. Primitive contracts define the exact division of responsibility.

## Implementation order per module

Public behavior lands in this order:

1. review and publish its owning contract;
2. implement the behavior with applicable assertions and verification;
3. add model, stress, or integration coverage where required.

Re-export-only facades need no separate contract. Do not create source scaffolding
without an implementation need.


## Shared impl across Static / Bounded variants

Subsystems that expose both `Static` (compile-time-capacity) and `Bounded`
(runtime-capacity) variants over a common operation set share the
implementation via module-scope `comptime`-parameterized free functions in the
subsystem's primary file. The variants are thin wrappers that pass their
internal buffer and capacity into the free functions.

This pattern is in effect in `src/ranges/` and `src/mem/alloc/bitmap.zig`. New
subsystems with the same shape MUST follow it. A private `Core` struct that
both variants delegate to is not used for this role.