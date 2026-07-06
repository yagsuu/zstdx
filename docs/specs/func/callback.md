# Func callback

Status: Approved.

`stdx.func.Callback(Fn)` is a runtime-erased single-function callback: a
`{context, invoke}` pair specialized at compile time on a function
signature `Fn`. `stdx.func.Closure(Fn, capacity_bytes)` extends the pair
with inline caller state, comptime-verified to fit and align. Together
they cover the "type-erased handler with optional captured state"
pattern without allocation.

The primitive is single-function. Multi-method dispatch (allocator-shaped
interfaces, reader/writer families) is a vtable, not a `Callback`, and
is owned by each consuming spec.

## Owned scope

This spec owns:

- `stdx.func.Callback(Fn)` — the `{context, invoke}` value type;
- `stdx.func.Closure(Fn, capacity_bytes)` — inline-storage constructor
  for `Callback`;
- `Callback(Fn).wrap`, `Callback(Fn).bind`,
  `Callback(Fn).bindMethod` factory family;
- `Closure(Fn, N).init` factory and its `callback()` projection;
- comptime signature validation for `Fn` and for every bound function;
- context lifetime and reentrancy contracts;
- interoperation between `Callback(Fn)` and `Closure(Fn, N)`;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- multi-method dispatch — allocator-shaped, reader/writer-shaped, and
  vtable-shaped interfaces are owned by their consuming specs;
- allocator-backed closures — inline `Closure(Fn, N)` is the only
  variant approved by this spec;
- comparators, hashers, and equality callbacks — owned by
  `docs/specs/core/traits.md`;
- async or coroutine callbacks — owned by `std.Io`;
- reference counting, weak references, or lifetime enforcement on
  `context`;
- global registration tables, dispatch tables, or callback stores;
- runtime replacement of an already-constructed callback's invoke
  pointer;
- root promotion of `Callback` or `Closure`.

## When to use — and when not to

Callbacks trade an indirect call plus context deref for the ability to
carry the function through a value slot at runtime. Use them when the
callee is not known at the callsite that stores the reference.

Use `Callback(Fn)` when:

- an interrupt vector, completion hook, timer expiry, or event listener
  needs a per-instance handler stored in a table or in another struct;
- a subsystem exposes a hook slot whose caller supplies the target at
  runtime;
- a queue, ring, or deferred-cleanup list carries actions whose targets
  vary per entry.

Use `Closure(Fn, N)` when a callback also needs to carry small
per-invocation state whose lifetime should coincide with the callback
itself.

Do not use `Callback(Fn)` when:

- the callee is comptime-known at the invocation site — pass a
  comptime `fn` value directly, matching the pattern approved by
  `docs/specs/core/traits.md`;
- an interface exposes more than one method — model it as a vtable
  under the consuming spec, not as parallel `Callback` fields;
- the interface is a comparator, hasher, or equality function — use
  `stdx.core.Compare`, `stdx.core.LessThan`, `stdx.core.Eql`, or
  `stdx.core.Hash`;
- the interface is an iterator visitor consumed in a monomorphized
  loop — pass `anytype`;
- the callback has no context — a plain `*const fn (Args) Return`
  fits in one word instead of two;
- `std.io.AnyReader` or `std.io.AnyWriter` already fits — those std
  types remain canonical for `Reader` and `Writer` erasure.

## Public namespace

Types live under `stdx.func`:

```zig
stdx.func.Callback
stdx.func.Closure
```

They are not root-promoted:

```zig
stdx.Callback // not exported
stdx.Closure  // not exported
```

The namespace is named `func` rather than `fn` because `fn` is a Zig
keyword.

Source ownership:

```text
src/func.zig
src/func/callback.zig
src/func/closure.zig
src/func/validate.zig
test/func/callback_test.zig
test/func/closure_test.zig
```

`src/func.zig` re-exports:

```zig
pub const callback = @import("func/callback.zig");
pub const closure = @import("func/closure.zig");

pub const Callback = callback.Callback;
pub const Closure = closure.Closure;
```

`src/func.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## Approved API

```zig
pub fn Callback(comptime Fn: type) type {
    return struct {
        pub const Signature: type = Fn;
        pub const Args: type = ArgsTuple(Fn);
        pub const Return: type = ReturnType(Fn);
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

`ArgsTuple(Fn)` is the `std.meta.ArgsTuple` of `Fn`. `ReturnType(Fn)` is
`@typeInfo(Fn).@"fn".return_type.?`. The `bind`, `bindMethod`, and
`Closure.init` factories take `fn_ptr: anytype`; the accepted signature
is `Fn` with `*Ctx` (or `*State`) prepended, validated structurally at
compile time.

The `Callback(Fn).context` and `Callback(Fn).invoke` fields are public
for introspection (equality, debug logging, table snapshots). Callers
must not overwrite them; the invocation contract holds only against
fields produced by an approved factory.

There is no `Callback.rebind`, no `Callback.setContext`, and no
`Callback.setInvoke`. There is no allocator-backed `Closure`.

## Signature validation

`Callback(Fn)` and `Closure(Fn, N)` compile-error at instantiation when
`Fn` is not admissible.

`Fn` must satisfy:

- `@typeInfo(Fn) == .@"fn"`;
- `@typeInfo(Fn).@"fn".is_generic == false`;
- `@typeInfo(Fn).@"fn".is_var_args == false`;
- `@typeInfo(Fn).@"fn".return_type != null`;
- every parameter has a concrete, non-`null` type.

Rejected shapes: generic functions, functions taking `anytype`, functions
taking `comptime` parameters, variadic functions, and naked functions.

`bind` and `bindMethod` additionally validate at compile time:

- for `bind`, `fn_ptr` resolves to a function whose signature equals
  `Fn` with `*Ctx` prepended as the first parameter;
- for `bindMethod`, `@field(Ctx, method_name)` resolves to a `pub`
  function whose signature equals `Fn` with `*Ctx` prepended as the
  first parameter;
- signature mismatches emit a `@compileError` naming the required
  shape.

`wrap` validates that `fn_ptr` has type `*const Fn`.

`Closure(Fn, N).init` validates at compile time:

- `@sizeOf(State) <= capacity`;
- `@alignOf(State) <= alignment`;
- `fn_ptr` resolves to a function whose signature equals `Fn` with
  `*State` prepended as the first parameter.

## Semantics

### Representation

`Callback(Fn)` holds one `?*anyopaque` context and one `*const Invoke`
function pointer. `@sizeOf(Callback(Fn)) == 2 * @sizeOf(usize)` on every
supported target.

`Closure(Fn, N)` holds `capacity` bytes of inline storage aligned to
`@alignOf(usize)` and one `*const Invoke` function pointer.
`@sizeOf(Closure(Fn, N)) == stdx.mem.alignUp(usize, N, @alignOf(usize)) + @sizeOf(usize)` (using `catch unreachable`; `alignUp` is infallible for power-of-two alignment within `usize` range).

Both layouts are pinned by `comptime` assertions inside their type
bodies.

### Construction

`Callback(Fn).init(context, invoke)` returns
`.{ .context = context, .invoke = invoke }`. The caller supplies an
already-erased `invoke` thunk. Reserved for callers who synthesize their
own thunk; `wrap`, `bind`, and `bindMethod` are the ordinary paths.

`Callback(Fn).wrap(fn_ptr)` returns a callback whose `context` is `null`
and whose `invoke` dispatches to `fn_ptr` ignoring the context slot.

`Callback(Fn).bind(Ctx, ctx, fn_ptr)` returns a callback whose `context`
is `@ptrCast(ctx)` and whose `invoke` re-casts the context to `*Ctx` and
delegates to `fn_ptr`.

`Callback(Fn).bindMethod(Ctx, ctx, method_name)` resolves
`@field(Ctx, method_name)` at compile time, validates its signature
against the required `fn (*Ctx, ...) Return` shape, and delegates to
`bind`.

`Closure(Fn, N).init(State, state, fn_ptr)` bit-copies `state` into the
closure's inline storage and stores a thunk that re-casts the storage
to `*State` and delegates to `fn_ptr`. The captured `state` is a
value copy; interior pointers into the caller's `state` variable
survive the copy, interior pointers into the closure's own storage do
not.

### Invocation

`Callback(Fn).call(args)` returns `self.invoke(self.context, args)`.
`args` is an `Args` tuple; single-argument callbacks pass `.{value}`,
zero-argument callbacks pass `.{}`.

For `Return` an error union, `call` propagates errors verbatim. For
`Return` `void`, `call` returns `void`. For `Return` a concrete value
type, `call` returns the value.

`Closure(Fn, N).callback()` returns a `Callback(Fn)` whose `context`
points into the closure's `storage` and whose `invoke` is the closure's
thunk. The returned callback borrows the closure's storage for the
lifetime of the closure value. A `Closure` that is moved or copied
invalidates any previously-returned `Callback`; callers who need a
stable callback keep the closure at a stable address (heap slot, arena
slot, static storage) and re-derive the callback after any move.

### Equality

`Callback(Fn).eql(other)` returns
`self.context == other.context and self.invoke == other.invoke`.
Reflects field identity, not caller intent — two callbacks bound to the
same method through separate `bindMethod` calls compare equal because
they share the same synthesized thunk instance for a given `(Ctx,
method_name)` pair.

## Clock parameter

Not applicable. Callbacks are clock-agnostic.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `Callback.init` | never | never | O(1) | value type | none | infallible |
| `Callback.wrap` | never | never | O(1) | value type | none | infallible; compile error on shape mismatch |
| `Callback.bind` | never | never | O(1) | value type | none | infallible; compile error on shape mismatch |
| `Callback.bindMethod` | never | never | O(1) | value type | none | infallible; compile error on missing/mismatched method |
| `Callback.call` | delegates to callee | delegates to callee | O(1) + callee | delegates to callee | delegates to callee | propagates `Return` |
| `Callback.eql` | never | never | O(1) | value type | none | infallible |
| `Closure.init` | never | never | O(1) + `@sizeOf(State)` copy | value type | none | infallible; compile error on size/alignment overrun |
| `Closure.callback` | never | never | O(1) | reader | none | infallible |

`Callback` and `Closure` are safe from any execution context including
NMI when the bound callee is safe from that context. The primitive
itself performs no allocation, no locking, no syscall, and no atomic
operation.

`Callback.call` performs one indirect call and one context load.
Consumer specs that reject indirect dispatch on hot paths reject
`Callback` on those paths; the primitive is not a substitute for
comptime specialization.

## Context lifetime

`context` is a borrowed pointer. `Callback` and `Closure.callback()`
never take ownership, never allocate, and never free. A callback that
outlives its `context` is a caller contract violation and is not
detected by this primitive.

`Closure` owns the memory pointed to by the `Callback` it produces.
Copying or moving a `Closure` invalidates a previously-returned
`Callback` because the context pointer references the old storage
address.

## Reentrancy

Callbacks may recurse into themselves and may invoke other callbacks
that eventually reach the same instance. The primitive imposes no
reentrancy discipline. Consumer specs that require non-reentrant
dispatch document that requirement themselves.

## Ordering and concurrency

`Callback` and `Closure` are value types with no atomic state and no
internal synchronization. Concurrent use of a shared `Callback` value
by multiple threads is safe iff every field read observes a
consistently-published value; publication is the caller's
responsibility.

A `Callback` stored in a shared slot (interrupt vector, hook table)
must be published under whatever ordering discipline the slot's owning
spec defines. This primitive contributes no ordering.

## Comparison to standard library

`std.io.AnyReader` and `std.io.AnyWriter` remain the canonical
type-erased handles for `Reader` and `Writer` interfaces. This spec
does not alias or replace them.

`std.mem.Allocator` and future `std.Io` vtables remain canonical for
multi-method dispatch. `Callback(Fn)` is not a substitute; consumers
building multi-method interfaces define their own vtable.

`std.EnumMap(Tag, *const fn (...))` remains the canonical
enum-indexed dispatch table for context-less function pointers.
`Callback(Fn)` composes as the value type inside such a table when
context is required.

Comptime-specialized dispatch through `anytype`, comptime `fn` values,
and the callback type factories in `stdx.core` (`Compare`, `LessThan`,
`Eql`, `Hash`) remains preferred where the callee is known at the
callsite; `Callback(Fn)` costs one indirect call and one context load
per invocation.

## Examples

Interrupt vector with per-instance handlers:

```zig
const Handler = stdx.func.Callback(fn (*IsrFrame) void);

var vectors: [256]?Handler = [_]?Handler{null} ** 256;

fn register(vec: u8, device: *Device) void {
    vectors[vec] = .bindMethod(Device, device, "onIrq");
}

fn dispatch(vec: u8, frame: *IsrFrame) void {
    if (vectors[vec]) |cb| cb.call(.{frame});
}
```

Deferred cleanup queue over a bounded ring:

```zig
const Action = stdx.func.Callback(fn () void);

var deferred: stdx.collections.Ring.Bounded(Action) = ...;

fn enqueueClose(fd: FileHandle) !void {
    try deferred.push(.bindMethod(FileHandle, fd, "close"));
}

fn drain() void {
    while (deferred.pop()) |cb| cb.call(.{});
}
```

Timer expiry with captured retry state:

```zig
const Trigger = stdx.func.Callback(fn (Instant) void);
const RetryClosure = stdx.func.Closure(fn (Instant) void, 32);

fn schedule(sched: *Scheduler, at: Instant, attempts: u32) !void {
    var slot = try sched.arena.create(RetryClosure);
    slot.* = .init(Retry, .{ .attempts = attempts }, Retry.trigger);
    sched.armAt(at, slot.callback());
}
```

Free-function callback with no context:

```zig
const Ready = stdx.func.Callback(fn () bool);

fn always() bool {
    return true;
}

const cb: Ready = .wrap(&always);
```

## Required tests

Tests live in `test/func/callback_test.zig` and
`test/func/closure_test.zig`.

Required tests for `Callback(Fn)`:

- Compile-only: `Callback(u32)` (non-function `Fn`) rejected;
- Compile-only: `Callback(fn (comptime T: type) void)` (generic)
  rejected;
- Compile-only: `Callback(fn (anytype) void)` rejected;
- Compile-only: `Callback(fn (u32, ...) void)` (variadic) rejected;
- Compile-only: `Callback(fn (u32) void).bind(Ctx, ctx, &wrongSig)`
  rejected with signature mismatch;
- Compile-only: `Callback(fn (u32) void).bindMethod(Ctx, ctx,
  "missing")` rejected with missing method;
- `wrap(&fnPtr)` dispatch: `Return = void`, single-argument input
  arrives at callee unchanged;
- `wrap(&fnPtr)` dispatch: `Return = u32`, callee return arrives at
  caller unchanged;
- `wrap(&fnPtr)` dispatch: `Return = error{X}!u32`, callee error
  propagates through `call`;
- `bind(Ctx, &ctx, &fnPtr)` dispatch: context pointer arrives at
  callee equal to `&ctx`;
- `bindMethod(Ctx, &ctx, "onEvent")` dispatch: method receives `*Ctx`
  equal to `&ctx` and every remaining argument unchanged;
- `call(.{a, b, c})` for three-argument `Fn` arrives with tuple fields
  mapped to positional args in order;
- `call(.{})` for zero-argument `Fn` returns the callee's return value;
- `eql` returns true for two callbacks constructed by identical
  `wrap` / `bind` / `bindMethod` calls, false for callbacks whose
  context or invoke differs;
- `@sizeOf(Callback(fn () void)) == 2 * @sizeOf(usize)`;
- `Callback(Fn).init(ctx, invoke_ptr)` returns a value whose `context`
  and `invoke` fields are field-identical to the arguments.

Required tests for `Closure(Fn, N)`:

- Compile-only: `Closure(fn () void, 4).init(u64, 0, &fnPtr)` rejected
  for oversize state;
- Compile-only: `Closure(fn () void, 32).init(WideAlign, state,
  &fnPtr)` rejected for over-aligned state;
- Compile-only: `Closure(fn (u32) void, 16).init(State, s, &wrongSig)`
  rejected for signature mismatch;
- `init(State, state, &fnPtr).callback().call(args)` reaches the
  callee with `*State` pointing to storage containing a bit-copy of
  `state`;
- Mutating `state` after `init` does not affect the closure's captured
  copy;
- `@sizeOf(Closure(fn () void, 16)) ==
  stdx.mem.alignUp(usize, 16, @alignOf(usize)) + @sizeOf(usize)`;
- `callback()` returns a `Callback(Fn)` whose `context` equals
  `@ptrCast(&closure.storage)`;
- Multi-argument `Fn`: `init(State, s, &fnPtr).callback().call(args)`
  wires every argument through correctly.

Non-x86 build compiles the module.

## Open questions

None.
