# Func callback

Status: Approved.

`stdx.func.Callback(Fn)` is a runtime-erased, single-function callback. `stdx.func.Closure(Fn, capacity_bytes)` stores copied state inline and projects it as a `Callback(Fn)`. Neither primitive allocates.

## What this spec is

This specification defines the `stdx.func` callback namespace, the `Callback` and `Closure` types, their representation, compile-time signature validation, construction, invocation, comparison, context lifetime, reentrancy, concurrency effects, and required tests.

## What this spec is not

This specification does not define:

- multi-method dispatch, including allocator-shaped, reader/writer-shaped, and vtable-shaped interfaces; consuming specifications own those interfaces;
- allocator-backed closures;
- comparators, hashers, or equality callbacks; `docs/specs/core/traits.md` owns them;
- asynchronous or coroutine callbacks; `std.Io` owns them;
- reference counting, weak references, or runtime lifetime enforcement for `context`;
- global callback registration, dispatch, or storage tables; or
- root exports for `Callback` or `Closure`.

## Terminology

- **context**: The optional erased pointer stored by a `Callback` and passed as the first argument to its invoke thunk.
- **invoke thunk**: A function with type `Callback(Fn).Invoke` that converts a callback's erased context and argument tuple to a target function call.
- **stable address**: An address that does not change while a borrowed callback can be invoked.

## Public namespace and source ownership

The public types are `stdx.func.Callback` and `stdx.func.Closure`.

The implementation sources are:

```text
src/func.zig
src/func/callback.zig
src/func/closure.zig
src/func/validate.zig
```

The required test sources are:

```text
test/func/callback_test.zig
test/func/closure_test.zig
```

`src/func.zig` is a thin facade. It imports, re-exports, and aliases the public types only.

## Cross-spec relationships

This specification composes with `docs/specs/core/traits.md` only by excluding that specification's comparator, hasher, and equality callback types. It does not define their contracts.

A consumer MAY store a `Callback` in its own interrupt vector, hook table, queue, ring, or other storage. The consumer owns publication, storage lifetime, ordering, and any policy for indirect dispatch.

## Data structures and representation

`Callback(Fn)` contains one `?*anyopaque` context pointer and one `*const Invoke` function pointer. For every supported target:

```zig
@sizeOf(Callback(Fn)) == 2 * @sizeOf(usize)
```

`Closure(Fn, N)` contains `N` bytes of inline storage aligned to `@alignOf(usize)` and one `*const Callback(Fn).Invoke` function pointer. For every supported target:

```zig
@sizeOf(Closure(Fn, N)) ==
    stdx.mem.alignUp(usize, N, @alignOf(usize)) + @sizeOf(usize)
```

`stdx.mem.alignUp` is infallible for this power-of-two alignment and `usize` input. Both types MUST contain comptime assertions for their required size.

The `context` and `invoke` fields define the representation used for introspection, equality checks, debug logging, and table snapshots. A caller MUST NOT overwrite either field. Invocation is defined only for fields produced by `init`, `wrap`, `bind`, `bindMethod`, or `Closure.callback`.

## Global invariants

- `Callback` and `Closure` MUST NOT allocate, free memory, lock, perform a syscall, perform an atomic operation, or access a hidden global.
- `Callback` and `Closure` MUST NOT impose a clock, scheduling, or waiting policy.
- A callback factory MUST validate its required function shape at compile time.
- `Callback` MUST preserve the supplied function signature `Fn` at its public call boundary.
- `Closure.init` MUST copy the supplied `State` value into the closure's inline storage.
- `Callback` does not own its context pointer.
- A callback returned by `Closure.callback` borrows the closure's inline storage.
- This primitive imposes no reentrancy discipline.
- This primitive contributes no synchronization or memory-ordering edge.

## API

```zig
pub fn Callback(comptime Fn: type) type {
    return struct {
        pub const Signature: type = Fn;
        pub const Args: type = std.meta.ArgsTuple(Fn);
        pub const Return: type = @typeInfo(Fn).@"fn".return_type.?;
        pub const Invoke: type = fn (?*anyopaque, Args) Return;

        context: ?*anyopaque,
        invoke: *const Invoke,

        pub fn init(context: ?*anyopaque, invoke: *const Invoke) Self;

        pub fn wrap(comptime fn_ptr: *const Fn) Self;
        pub fn bind(
            comptime Ctx: type,
            ctx: *Ctx,
            comptime fn_ptr: anytype,
        ) Self;
        pub fn bindMethod(
            comptime Ctx: type,
            ctx: *Ctx,
            comptime method_name: []const u8,
        ) Self;

        pub fn call(self: Self, args: Args) Return;
        pub fn eql(self: Self, other: Self) bool;
    };
}

pub fn Closure(comptime Fn: type, comptime capacity_bytes: usize) type {
    return struct {
        pub const Signature: type = Fn;
        pub const capacity: usize = capacity_bytes;
        pub const alignment: usize = @alignOf(usize);

        storage: [capacity]u8 align(alignment),
        invoke: *const Callback(Fn).Invoke,

        pub fn init(
            comptime State: type,
            state: State,
            comptime fn_ptr: anytype,
        ) Self;

        pub fn callback(self: *Self) Callback(Fn);
    };
}
```

`Callback` has no `rebind`, `setContext`, or `setInvoke` operation. `Closure` has no allocator-backed variant.

## Signature validation

`Callback(Fn)` and `Closure(Fn, N)` MUST cause a compile error when `Fn` is not admissible. An admissible `Fn`:

- MUST be a function type;
- MUST NOT be generic;
- MUST NOT be variadic;
- MUST have a non-null return type; and
- MUST have a concrete, non-null type for every parameter.

Accordingly, generic functions, functions with `anytype` or `comptime` parameters, variadic functions, and naked functions are rejected.

`Callback.wrap` MUST accept only a value with type `*const Fn`.

`Callback.bind` MUST cause a compile error unless `fn_ptr` points to a function whose signature is `Fn` with `*Ctx` as its first parameter.

`Callback.bindMethod` MUST cause a compile error unless `@field(Ctx, method_name)` resolves to a public function whose signature is `Fn` with `*Ctx` as its first parameter. A signature mismatch MUST report the required shape in its `@compileError`.

`Closure.init` MUST cause a compile error when any of the following conditions is true:

- `@sizeOf(State) > capacity`;
- `@alignOf(State) > alignment`; or
- `fn_ptr` does not point to a function whose signature is `Fn` with `*State` as its first parameter.

## Callback construction

### `Callback.init`

`Callback.init(context, invoke)` MUST return a callback whose fields equal `context` and `invoke`. The caller supplies the already-erased invoke thunk. `init` does not validate the thunk's behavior.

### `Callback.wrap`

`Callback.wrap(fn_ptr)` MUST return a callback with a null context. Its invoke thunk MUST ignore the context slot and call `fn_ptr` with the supplied arguments.

### `Callback.bind`

`Callback.bind(Ctx, ctx, fn_ptr)` MUST return a callback whose context is `@ptrCast(ctx)`. Its invoke thunk MUST cast the context to `*Ctx` and call `fn_ptr` with that pointer before the supplied arguments.

### `Callback.bindMethod`

`Callback.bindMethod(Ctx, ctx, method_name)` MUST resolve `@field(Ctx, method_name)` at compile time and construct the callback with the same behavior as `bind(Ctx, ctx, &@field(Ctx, method_name))`.

## Closure construction

`Closure.init(State, state, fn_ptr)` MUST store a value copy of `state` in the closure's inline storage. Its invoke thunk MUST cast that storage to `*State` and call `fn_ptr` with the state pointer before the supplied arguments.

Interior pointers stored in the caller's `state` value remain pointers to their original referents after the copy. An interior pointer to the closure's storage does not remain valid after the closure is copied or moved.

## Invocation

`Callback.call(args)` MUST call `self.invoke(self.context, args)` and return its result.

`args` is an `Args` tuple. A caller MUST pass `.{}` for a zero-argument signature and `.{ value }` for a single-argument signature.

For an error-union `Return`, `call` MUST propagate the callee error unchanged. For a `void` `Return`, `call` returns `void`. For every other `Return`, `call` MUST return the callee result unchanged.

`Closure.callback()` MUST return a `Callback(Fn)` whose context points to the closure's storage and whose invoke pointer is the closure's invoke thunk.

## Equality

`Callback.eql(other)` MUST return `true` exactly when both `context` fields are equal and both `invoke` fields are equal. It compares field identity, not semantic equivalence of the target behavior. Identical `wrap`, `bind`, and `bindMethod` constructions use the same synthesized thunk for their corresponding compile-time inputs.

## Lifetime and copying

A `Callback` context pointer is borrowed. `Callback`, `Closure.init`, and `Closure.callback` MUST NOT take ownership of, retain, allocate for, or free a context.

The caller MUST keep a context passed to `Callback.bind` alive and at a stable address until every callback that borrows it is no longer invoked. The primitive does not detect a context-lifetime violation.

A callback returned by `Closure.callback` borrows the source closure's storage. Copying or moving that closure invalidates every callback previously returned from it because each callback points to the prior storage address. A caller that requires a stable callback MUST keep the closure at a stable address and obtain a new callback after every move.

## Reentrancy, execution context, and concurrency

A callback MAY invoke itself recursively or invoke another callback that reaches the same callback. A consumer that prohibits reentrant dispatch MUST state and enforce that restriction.

The primitive is safe in any execution context, including NMI, only when the bound callee is safe in that context.

`Callback.call` performs one indirect call and one context load. It has complexity `O(1)` plus the callee cost. A consumer that forbids indirect dispatch on a hot path MUST NOT use `Callback` on that path.

`Callback` and `Closure` are value types without atomic state or internal synchronization. A caller that publishes a shared callback MUST ensure that each reader observes a consistently published value. The owner of a shared callback slot MUST define the required synchronization and ordering. Concurrent invocation has only the synchronization and safety guarantees of the callee and context.

## Allocation and fault behavior

`Callback.init`, `Callback.wrap`, `Callback.bind`, `Callback.bindMethod`, `Callback.eql`, `Closure.init`, and `Closure.callback` are infallible at runtime. The factories that validate types MAY cause compile errors as specified above.

`Callback.call` has the allocation, waiting, error, concurrency, and ordering effects of the bound callee. The callback primitive adds no such effect.

## Implementation constraints

The implementation MUST use the `{ context, invoke }` representation for `Callback` and inline `storage` plus `invoke` for `Closure`.

The implementation MUST use a function pointer with type `*const Callback(Fn).Invoke` for every invoke thunk. It MUST preserve the public constants and the ABI footprint in the API section.

The implementation MUST NOT add an allocator-backed closure, hidden callback storage, synchronization, or runtime type validation.

## Testing

Tests MUST use runtime dispatch observations and compile-time rejection fixtures to verify the observable contracts below.

- **Representation:** Measure `@sizeOf(Callback(fn () void))` and `@sizeOf(Callback(fn (u32) u32))` to prove the two-word ABI footprint. Measure closure sizes for aligned and unaligned capacities to prove the aligned-capacity-plus-invoke-word layout guarantee. Verify that `init` preserves the exact supplied context and invoke pointer fields.
- **Signature boundaries:** Compile invalid `Fn` forms, invalid `wrap` pointers, invalid bound signatures, a missing method, oversize state, and over-aligned state. Each fixture MUST fail at compile time. These tests prove that erased invocation cannot be constructed with an unsupported signature or state layout.
- **Invocation:** Invoke wrapped, bound, and bound-method callbacks with zero, one, and multiple arguments. Observe unchanged positional arguments, callee return values, `void` behavior, and unchanged error-union errors. These tests prove that the thunk preserves `Fn` at the public call boundary.
- **Context and equality:** Bind distinct context objects and observe that each callee receives its own object. Compare callbacks with equal and unequal field pairs. These tests prove context forwarding and field-identity comparison.
- **Closure state and borrowing:** Initialize a closure from state, mutate the source state, then invoke the projected callback and inspect the stored state. Verify that the callback context equals the closure storage address. Keep a closure in a stable allocated slot, invoke its callback, and observe the stored-state update. These tests prove copy-on-initialization and the stable-address lifetime contract.
- **Target coverage:** Compile and execute the callback module on a non-x86 target. This test proves that the layout and dispatch contract does not depend on x86-specific behavior.
