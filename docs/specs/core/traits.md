# Core traits

Status: Approved.

`zstdx.core` owns zero-allocation callback type factories and semantic laws for ordering, equality, and hashing. These traits exist to keep collection and algorithm specs consistent without forcing runtime vtables or broad policy objects.

The traits are concrete public API, but source implementation lands only when an approved consumer needs them.

## Owned scope

This spec owns:

- public callback type factory names;
- callback signatures;
- ordering, equality, and hashing laws;
- callback context rules;
- compile-time versus runtime callback rules;
- required documentation and tests for consumers.

This spec does not own:

- sort, heap, map, set, or tree APIs;
- default hash algorithms;
- default comparators;
- allocation behavior of user callbacks beyond the contracts below;
- storage of callback context inside individual containers.

## Concrete consumers

Approved future consumers include:

- `algo.sortUnstable` and `algo.insertionSort` for `LessThan`;
- `Heap.Binary`, `Heap.Dary`, and `Heap.Indexed` for `LessThan`;
- `HashMap` and `HashSet` for `Hash` plus `Eql`;
- `BTree.Map`, `BTree.Set`, range maps, and ordered structures for `Compare`;
- intrusive ordered structures when key extraction is specified by their owning spec.

No generic trait object or runtime interface is approved.

## Public namespace

Traits live under `zstdx.core`:

```zig
zstdx.core.Order
zstdx.core.Compare
zstdx.core.LessThan
zstdx.core.Eql
zstdx.core.Hash
```

They are not root-promoted:

```zig
zstdx.Compare // not exported
```

Source ownership:

```text
src/core.zig
src/core/traits.zig
```

`src/core.zig` re-exports:

```zig
pub const Order = @import("core/traits.zig").Order;
pub const Compare = @import("core/traits.zig").Compare;
pub const LessThan = @import("core/traits.zig").LessThan;
pub const Eql = @import("core/traits.zig").Eql;
pub const Hash = @import("core/traits.zig").Hash;
```

## Approved API

```zig
pub const Order = enum {
    lt,
    eq,
    gt,
};

pub fn Compare(comptime Context: type, comptime T: type) type {
    return fn (context: Context, lhs: *const T, rhs: *const T) Order;
}

pub fn LessThan(comptime Context: type, comptime T: type) type {
    return fn (context: Context, lhs: *const T, rhs: *const T) bool;
}

pub fn Eql(comptime Context: type, comptime T: type) type {
    return fn (context: Context, lhs: *const T, rhs: *const T) bool;
}

pub fn Hash(comptime Context: type, comptime T: type) type {
    return fn (context: Context, value: *const T) u64;
}
```

All value operands are `*const T` to avoid mandatory copies for large values and to make callback cost explicit. A consumer that needs by-value callbacks must justify that in its owning spec.

## Context rules

`Context` is passed by value to callbacks.

For callbacks with no context, use `void` and pass `{}`:

```zig
fn lessU32(_: void, lhs: *const u32, rhs: *const u32) bool {
    return lhs.* < rhs.*;
}
```

If mutable or large context is needed, the `Context` type should be a pointer:

```zig
const Ctx = *const LookupTables;
```

A primitive may store context only if its owning spec explicitly says so. Otherwise context is borrowed only for the duration of the operation that receives it.

Callbacks must not assume that pointer identity is stable unless the consuming primitive's spec promises pointer stability.

## Compile-time callback rule

Default consumer APIs should take callbacks as comptime-known `fn` values, not runtime function pointers.

Approved pattern:

```zig
pub fn sort(
    comptime T: type,
    items: []T,
    context: anytype,
    comptime lessThan: zstdx.core.LessThan(@TypeOf(context), T),
) void;
```

Options structs that include callback fields are comptime options unless the owning spec explicitly approves runtime storage.

Runtime function pointers require an owning-spec rationale and must use explicit pointer types, e.g. `*const fn (...) ...`.

## Callback behavior contract

Unless the consuming spec explicitly permits otherwise, callbacks must:

- not allocate;
- not wait, sleep, block, or spin on external state;
- not mutate the collection or algorithm input being operated on;
- not re-enter the same primitive instance;
- be deterministic for the lifetime required by the consuming primitive;
- be total over every value that can be stored or processed by the consuming primitive.

If a caller supplies a callback that violates these requirements, behavior is a caller contract violation. The primitive is not required to detect it.

Callback behavior is caller-provided behavior. A primitive's own allocation/waiting contract does not include allocation or waiting performed inside caller callbacks; consumer specs must still state whether such callbacks are allowed.

## Ordering laws

### `Compare`

`Compare` defines a total order over `T` for the consuming primitive's domain.

Required laws:

- exactly one of `.lt`, `.eq`, or `.gt` is returned for any `lhs`, `rhs`;
- antisymmetry: if `compare(a, b) == .lt`, then `compare(b, a) == .gt`;
- equality symmetry: if `compare(a, b) == .eq`, then `compare(b, a) == .eq`;
- transitivity: if `a < b` and `b < c`, then `a < c`;
- equality transitivity: if `a == b` and `b == c`, then `a == c`;
- deterministic result while values are resident in the consuming structure.

Ordered maps and sets use `.eq` as key equivalence unless their owning spec defines a separate key extraction/equality rule.

### `LessThan`

`LessThan` defines a strict weak order.

Required laws:

- irreflexive: `lessThan(a, a)` is false;
- asymmetric: if `lessThan(a, b)` is true, `lessThan(b, a)` is false;
- transitive: if `a < b` and `b < c`, then `a < c`;
- transitive incomparability: if neither `a < b` nor `b < a`, and neither `b < c` nor `c < b`, then neither `a < c` nor `c < a`;
- deterministic result while values are resident in the consuming structure.

Heaps use `LessThan` to mean lower priority unless the heap spec states otherwise. Sort algorithms use `LessThan` to produce ascending order under the supplied relation.

## Equality and hash laws

### `Eql`

`Eql` defines equivalence over `T`.

Required laws:

- reflexive: `eql(a, a)` is true;
- symmetric: `eql(a, b) == eql(b, a)`;
- transitive: if `a == b` and `b == c`, then `a == c`;
- deterministic result while values are resident in the consuming structure.

### `Hash`

`Hash` returns a non-cryptographic `u64` hash unless the consuming spec explicitly requires a stronger property.

Required laws when paired with `Eql`:

- if `eql(a, b)` is true, then `hash(a) == hash(b)`;
- hash value is deterministic while the value is resident in the consuming structure;
- collisions are allowed;
- hash must be based on semantic key identity, not pointer address, unless the consuming spec defines an identity map/set.

`Hash` does not own seeding, keyed hashing, randomized hashing, or DoS-resistance policy. Hash-map specs own those decisions.

## Naming conventions for consumers

Consumers must use these field and parameter names unless their owning spec approves a stronger domain term:

| Concept | Name |
| --- | --- |
| strict ordering callback | `lessThan` |
| three-way ordering callback | `compare` |
| equality callback | `eql` |
| hash callback | `hash` |
| callback context | `context` |
| left value | `lhs` |
| right value | `rhs` |
| hashed value | `value` |

## Consumer option shapes

A consumer that needs callbacks should derive its options type from explicit `Context` and value types. Callback fields are comptime fields unless the consumer spec approves runtime function-pointer storage.

Strict ordering:

```zig
pub fn Options(comptime Context: type, comptime T: type) type {
    return struct {
        context: Context = {},
        comptime lessThan: zstdx.core.LessThan(Context, T),
    };
}
```

Three-way ordering:

```zig
pub fn Options(comptime Context: type, comptime T: type) type {
    return struct {
        context: Context = {},
        comptime compare: zstdx.core.Compare(Context, T),
    };
}
```

Hash/equality:

```zig
pub fn Options(comptime Context: type, comptime K: type) type {
    return struct {
        context: Context = {},
        comptime hash: zstdx.core.Hash(Context, K),
        comptime eql: zstdx.core.Eql(Context, K),
    };
}
```

Exact option placement and factory signatures are owned by each consuming primitive spec, but consumers must preserve the callback names, pointer operand convention, context semantics, and comptime-default rule unless their spec explicitly overrides them.

## Error and safety behavior

Invalid trait laws are caller contract violations. `zstdx` primitives are not required to detect non-transitive ordering, unstable hashing, or inconsistent equality.

A consumer spec may add debug checks for easy-to-detect violations, but such checks are optional and controlled by that primitive's safety options.

## Required tests

For `zstdx.core`:

- `Order` is public through `zstdx.core`;
- `Compare`, `LessThan`, `Eql`, and `Hash` type factories compile for `Context = void` and a scalar `T`;
- pointer operands are accepted without copying values;
- a callback with pointer context compiles.

For each consumer:

- one test uses `Context = void`;
- one test uses non-void context when the API exposes context;
- one test covers equal values or duplicate keys where equality/order is involved;
- hash-based consumers test that collisions do not break lookup;
- ordering-based consumers test at least one non-trivial ordering different from natural integer ascending order.
