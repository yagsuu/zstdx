# `stdx.core` callback traits

Callback type factories for ordering, equality, and hashing.
`core` denotes `stdx.core`. `core.Order` is `std.math.Order`.

## Callback types

Each factory takes comptime `Context: type` and `T: type` and returns:

| Factory | Callback type |
| --- | --- |
| `core.Compare(Context, T)` | `fn (context: Context, lhs: *const T, rhs: *const T) core.Order` |
| `core.LessThan(Context, T)` | `fn (context: Context, lhs: *const T, rhs: *const T) bool` |
| `core.Eql(Context, T)` | `fn (context: Context, lhs: *const T, rhs: *const T) bool` |
| `core.Hash(Context, T)` | `fn (context: Context, value: *const T) u64` |

## Context and invocation

Context is passed by value. Context-free callbacks use `void` and receive `{}`.
Consumers borrow context for the receiving operation unless their contract
defines storage and its lifetime. Callbacks MUST NOT assume stable operand
pointer identity unless the consumer guarantees it.

Callbacks are bound at comptime unless the consumer explicitly defines runtime
storage. Runtime callbacks use explicit function-pointer types, such as
`*const fn (...) ...`, with consumer-defined storage behavior.

Unless the consumer explicitly permits an exception, callbacks MUST NOT:

- Allocate, wait, sleep, block, or spin on external state.
- Mutate the collection or algorithm input under operation.
- Re-enter the same primitive instance.

Callbacks MUST be total for every value the consumer can store or process, and
deterministic while values remain resident. Consumer allocation and waiting
guarantees exclude callback work. The consumer contract defines allocation and
waiting permissions and invocation order.

## Semantic laws

| Callback | Required law |
| --- | --- |
| `core.Compare` | Total order: exactly `.lt`, `.eq`, or `.gt`. Antisymmetric ordering (`compare(a, b) == .lt` implies `compare(b, a) == .gt`), symmetric equality, and transitive ordering and equality. |
| `core.LessThan` | Strict weak order: irreflexive, asymmetric, transitive, and transitively incomparable. |
| `core.Eql` | Equivalence relation: reflexive, symmetric, and transitive. |
| `core.Hash` | With `core.Eql`, `eql(a, b)` implies `hash(a) == hash(b)`. Collisions are permitted. |

- Ordered maps and sets use `.eq` as key equivalence unless their contract defines
  another key-extraction or equality rule.
- Heaps interpret `core.LessThan` as lower priority unless their contract states
  otherwise. Sorts produce ascending order under the relation.
- `core.Hash` is non-cryptographic unless the consumer requires stronger properties.
  Hash semantic key identity, not pointer addresses, unless the consumer defines
  an identity map or set.

These laws apply to the consumer's entire domain, including equal values and
duplicate keys.
Hash-map contracts own seeding, keyed or randomized hashing, and denial-of-service
resistance.

## References

- [Callback types](../../../src/core/traits.zig)
