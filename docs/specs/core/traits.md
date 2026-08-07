# Core traits

Status: Approved.

`stdx.core` defines zero-allocation callback type factories and semantic laws for ordering, equality, and hashing. Consumers use these factories without runtime vtables or generic trait objects.

## What this spec is

This specification defines the callback type factories, callback context rules, compile-time and runtime callback rules, ordering and hashing laws, and consumer requirements.

## What this spec is not

This specification does not define sort, heap, map, set, or tree APIs; default hash algorithms or comparators; callback allocation behavior beyond this contract; or callback-context storage for an individual container.

## Public namespace and source ownership

The public namespace is `stdx.core.Order`, `stdx.core.Compare`, `stdx.core.LessThan`, `stdx.core.Eql`, and `stdx.core.Hash`.

Source ownership:

```text
src/core.zig
src/core/traits.zig
```

`src/core.zig` re-exports these declarations from `core/traits.zig`.

## Cross-spec relationships

A collection or algorithm that accepts one of these callbacks depends on this specification. The consumer specification owns callback storage, callback invocation order, and any permitted exception to this specification's default callback behavior.

## API

```zig
pub const Order = std.math.Order;

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

Callback value operands are `*const T`. A consumer that requires by-value callbacks MUST define that distinct public contract in its own specification.

## Callback context and invocation

A consumer passes `Context` by value. A callback with no context MUST use `void` and receive `{}` as its context value. A callback that requires mutable or large context SHOULD use a pointer `Context` type.

A consumer MUST NOT store callback context unless its own specification defines the storage and lifetime. Otherwise, the consumer borrows context for the duration of the operation that receives it.

A callback MUST NOT assume stable pointer identity unless the consuming specification guarantees pointer stability.

A consumer SHOULD accept callbacks as comptime-known `fn` values. A consumer that stores callbacks in an options struct MUST make those fields `comptime` unless its specification explicitly defines runtime function-pointer storage. A consumer that uses runtime function pointers MUST use an explicit pointer type such as `*const fn (...) ...` and define the runtime storage behavior in its own specification.

## Callback behavior contract

Unless the consumer specification explicitly permits an exception, a caller-provided callback MUST NOT allocate; wait, sleep, block, or spin on external state; mutate the collection or algorithm input under operation; or re-enter the same primitive instance. A callback MUST be deterministic for the period that values are resident in the consumer and MUST be total for every value the consumer can store or process.

A callback that violates these requirements is a caller contract violation. A consumer is not required to detect it. A consumer's allocation and waiting contract excludes allocation and waiting performed by caller callbacks; the consumer specification MUST state whether callback allocation or waiting is permitted.

## Ordering laws

### `Compare`

`Compare` defines a total order over the consumer domain. For every `lhs` and `rhs`, it MUST return exactly one of `.lt`, `.eq`, or `.gt`. It MUST be antisymmetric: `compare(a, b) == .lt` implies `compare(b, a) == .gt`. It MUST preserve equality symmetry: `compare(a, b) == .eq` implies `compare(b, a) == .eq`. It MUST be transitive for both ordering and equality. It MUST be deterministic while values are resident in the consumer.

An ordered map or set MUST use `.eq` as key equivalence unless its owning specification defines another key-extraction or equality rule.

### `LessThan`

`LessThan` defines a strict weak order. It MUST be irreflexive, asymmetric, transitive, and transitively incomparable. It MUST be deterministic while values are resident in the consumer.

A heap MUST interpret `LessThan` as lower priority unless the heap specification defines another interpretation. A sort algorithm MUST produce ascending order under the supplied relation.

## Equality and hash laws

### `Eql`

`Eql` defines equivalence over the consumer domain. It MUST be reflexive, symmetric, transitive, and deterministic while values are resident in the consumer.

### `Hash`

`Hash` returns a non-cryptographic `u64` hash unless the consumer specification explicitly requires a stronger property. When a consumer pairs `Hash` with `Eql`, `eql(a, b) == true` MUST imply `hash(a) == hash(b)`. The hash MUST be deterministic while the value is resident in the consumer. Collisions are permitted. The hash MUST use semantic key identity rather than pointer address unless the consumer specification defines an identity map or set.

This specification does not define seeding, keyed hashing, randomized hashing, or denial-of-service resistance. A hash-map specification owns those decisions.

## Consumer naming and options

A consumer MUST use these names unless its owning specification defines a stronger domain term:

| Concept | Name |
| --- | --- |
| Strict ordering callback | `lessThan` |
| Three-way ordering callback | `compare` |
| Equality callback | `eql` |
| Hash callback | `hash` |
| Callback context | `context` |
| Left value | `lhs` |
| Right value | `rhs` |
| Hashed value | `value` |

A consumer with callback options MUST derive its options type from explicit `Context` and value types. It MUST preserve the callback names, pointer-operand convention, context semantics, and comptime-default rule unless its specification explicitly defines an override. The consumer specification owns exact option placement and factory signatures.

## Errors and fault behavior

Invalid trait laws are caller contract violations. A zstdx primitive is not required to detect non-transitive ordering, unstable hashing, or inconsistent equality. A consumer MAY add an optional debug check for an easy-to-detect violation when its safety options control that check.

## Testing

Tests for `stdx.core` MUST verify that `Order` is public through `stdx.core`; that `Compare`, `LessThan`, `Eql`, and `Hash` compile for `Context = void` and a scalar `T`; that callbacks accept pointer operands without requiring value copies; and that a pointer context compiles. These compile-time checks prove the public callback type contracts.

For each consumer, tests MUST use `Context = void` and, when the API exposes context, a non-void context. Tests for equality or ordering MUST include equal values or duplicate keys. A hash-based consumer MUST exercise colliding hashes and verify that lookup remains correct. An ordering-based consumer MUST exercise a non-natural ordering. These tests prove that the consumer applies the callback and semantic laws rather than assuming natural integer order or unique hashes.
