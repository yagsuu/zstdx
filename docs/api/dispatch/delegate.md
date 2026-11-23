# `stdx.dispatch.Delegate` / `stdx.dispatch.Closure`

`stdx.dispatch.Delegate(Fn)` pairs a function with a borrowed, erased context.
`stdx.dispatch.Closure(Fn, capacity_bytes)` copies state inline and provides
delegates that borrow that state. Neither primitive allocates. Here,
`Delegate` and `Closure` denote instantiated types.

## Construct a callable

`Fn` must be a concrete, non-generic, non-variadic function type with a return
type and concrete parameter types. Unsupported signatures, including `anytype`
or `comptime` parameters, are compile errors.

| Construction | Context and target |
| --- | --- |
| `Delegate.init(context, invoke)` | Stores the erased context and invoke pointer unchanged. The caller supplies a valid `Delegate.Invoke` implementation |
| `Delegate.wrap(function)` | Wraps a comptime `*const Fn` with null context |
| `Delegate.bind(Context, context, function)` | Borrows `context: *Context` and passes it before the signature arguments |
| `Delegate.bindMethod(Context, context, method)` | Resolves the named public declaration at comptime and binds `&@field(Context, method)` |
| `Closure.init(State, state, function)` | Copies `state` inline |
| `Closure.delegateMut()` | Requires a mutable closure pointer. Returns a `Delegate(Fn)` borrowing its inline state |

### Binding compatibility

| Applies to | Requirement |
| --- | --- |
| `Delegate.bind()`, `Delegate.bindMethod()`, `Closure.init()` target | Comptime function pointer |
| Delegate binding first parameter | Exactly `*Context` |
| Closure binding first parameter | Exactly `*State` |
| Remaining parameters and return type | Exact match with `Fn`, including error sets |
| Named method | Existing public declaration |
| Copied closure state | Size at most `capacity_bytes`, alignment at most `@alignOf(usize)` |

Incompatible targets, missing methods, and state-size or alignment violations
are compile errors. For custom erased dispatch, `Delegate.Invoke` is
`fn (?*anyopaque, Delegate.Args) Delegate.Return`, where `Delegate.Args` is
`std.meta.ArgsTuple(Fn)` and `Delegate.Return` is the return type of `Fn`.

## Invoke and compare

| Parameters in `Fn` | `Delegate.call()` form | `Delegate.callArgs()` form |
| --- | --- | --- |
| Zero | `delegate.call()` | `delegate.callArgs(.{})` |
| One | `delegate.call(value)` | `delegate.callArgs(.{value})` |
| Two or more | `delegate.call(.{ first, second, ... })` | Complete argument tuple |

A tuple-valued single parameter remains one value: `delegate.call(pair)`
corresponds to `delegate.callArgs(.{pair})`, not `delegate.callArgs(pair)`.

Invocation returns the callee's result and propagates errors unchanged.
Errors do not roll back context changes. Dispatch adds O(1) work.
Allocation, waiting, reentrancy, and execution-context restrictions depend on
the callee and context.

`Delegate.eql(other)` compares context and invoke pointer identity.
Wrapping the same function or binding the same function and context produces
equal delegates, including bindings through `Delegate.bindMethod()`.

## Keep context alive and stable

Borrowed contexts must remain alive and at a stable address while delegates
can be invoked. The caller manages cleanup and synchronizes publication and
conflicting access.

| Copy or change | Effect |
| --- | --- |
| Modify the seed after `Closure.init()` | Stored state is unchanged |
| Acquire multiple delegates from one closure | All share that closure's state |
| Copy a closure | Inline state is copied shallowly. Stored pointers still reference the original objects |
| Copy or move a closure with existing delegates | Existing delegates still reference the original closure. Reacquire delegates after moving |

## Storage layout

`Delegate` stores `context: ?*anyopaque` and `invoke: *const Delegate.Invoke`.
Its size is `2 * @sizeOf(usize)`. C ABI and field offsets are not guaranteed.

`Closure` stores `[capacity_bytes]u8` aligned to `@alignOf(usize)` and an invoke
pointer. Its size is the capacity rounded up to that alignment plus
`@sizeOf(usize)`. The total must be representable. Unused bytes are unspecified.

## References

- [Delegates](../../../src/dispatch/delegate.zig)
- [Inline closures](../../../src/dispatch/closure.zig)
