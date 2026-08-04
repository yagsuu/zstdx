//! Callback runtime dispatch tests. See `docs/specs/func/callback.md`.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

const Callback = stdx.func.Callback;

fn addOne(x: u32) u32 {
    return x + 1;
}

fn voidNoArg() void {}

fn returnErr(x: u32) error{Nope}!u32 {
    if (x == 0) return error.Nope;
    return x * 2;
}

var scratch: u32 = 0;

fn recordU32(x: u32) void {
    scratch = x;
}

fn sumThree(a: u32, b: u32, c: u32) u32 {
    return a + b + c;
}

const Ctx = struct {
    seen: u32,

    pub fn boundStore(self: *Ctx, x: u32) void {
        self.seen = x;
    }

    pub fn boundAdd(self: *Ctx, delta: u32) u32 {
        self.seen += delta;
        return self.seen;
    }

    pub fn boundVoid(self: *Ctx) void {
        self.seen += 1;
    }
};

fn boundStore(self: *Ctx, x: u32) void {
    self.seen = x;
}

fn boundAdd(self: *Ctx, delta: u32) u32 {
    self.seen += delta;
    return self.seen;
}

test "unit: Callback size is two words" {
    try testing.expectEqual(
        @as(usize, 2 * @sizeOf(usize)),
        @sizeOf(Callback(fn () void)),
    );
    try testing.expectEqual(
        @as(usize, 2 * @sizeOf(usize)),
        @sizeOf(Callback(fn (u32) u32)),
    );
}

test "unit: wrap dispatches a context-less function with one arg" {
    const cb: Callback(fn (u32) u32) = .wrap(&addOne);
    try testing.expectEqual(@as(u32, 8), cb.call(.{7}));
    try testing.expect(cb.context == null);
}

test "unit: wrap dispatches a zero-arg void function" {
    const cb: Callback(fn () void) = .wrap(&voidNoArg);
    cb.call(.{});
}

test "unit: wrap propagates an error union return" {
    const cb: Callback(fn (u32) error{Nope}!u32) = .wrap(&returnErr);

    try testing.expectEqual(@as(u32, 10), try cb.call(.{5}));
    try testing.expectError(error.Nope, cb.call(.{0}));
}

test "unit: wrap threads multi-argument tuple to callee in positional order" {
    const cb: Callback(fn (u32, u32, u32) u32) = .wrap(&sumThree);
    try testing.expectEqual(@as(u32, 6), cb.call(.{ 1, 2, 3 }));
}

test "unit: bind carries typed context to the callee" {
    var ctx: Ctx = .{ .seen = 0 };
    const cb: Callback(fn (u32) void) = .bind(Ctx, &ctx, &boundStore);

    cb.call(.{42});
    try testing.expectEqual(@as(u32, 42), ctx.seen);
    try testing.expectEqual(@as(?*anyopaque, @ptrCast(&ctx)), cb.context);
}

test "unit: bind propagates callee return value" {
    var ctx: Ctx = .{ .seen = 10 };
    const cb: Callback(fn (u32) u32) = .bind(Ctx, &ctx, &boundAdd);

    try testing.expectEqual(@as(u32, 15), cb.call(.{5}));
    try testing.expectEqual(@as(u32, 15), ctx.seen);
}

test "unit: bindMethod resolves and dispatches a pub method" {
    var ctx: Ctx = .{ .seen = 0 };
    const cb: Callback(fn (u32) void) = .bindMethod(Ctx, &ctx, "boundStore");

    cb.call(.{99});
    try testing.expectEqual(@as(u32, 99), ctx.seen);
}

test "unit: bindMethod propagates a non-void return through call" {
    var ctx: Ctx = .{ .seen = 0 };
    const cb: Callback(fn (u32) u32) = .bindMethod(Ctx, &ctx, "boundAdd");

    try testing.expectEqual(@as(u32, 3), cb.call(.{3}));
    try testing.expectEqual(@as(u32, 6), cb.call(.{3}));
    try testing.expectEqual(@as(u32, 6), ctx.seen);
}

test "unit: bindMethod handles a zero-extra-arg method signature" {
    var ctx: Ctx = .{ .seen = 0 };
    const cb: Callback(fn () void) = .bindMethod(Ctx, &ctx, "boundVoid");

    cb.call(.{});
    cb.call(.{});
    try testing.expectEqual(@as(u32, 2), ctx.seen);
}

test "unit: eql compares field-identity" {
    const cb_a: Callback(fn (u32) u32) = .wrap(&addOne);
    const cb_b: Callback(fn (u32) u32) = .wrap(&addOne);
    // Same fn_ptr, same null context, same synthesized thunk.
    try testing.expect(cb_a.eql(cb_b));

    var ctx: Ctx = .{ .seen = 0 };
    const cb_bound: Callback(fn (u32) u32) = .bind(Ctx, &ctx, &boundAdd);
    try testing.expect(!cb_a.eql(cb_bound));
}

test "unit: eql distinguishes callbacks with different context pointers" {
    var ctx_a: Ctx = .{ .seen = 0 };
    var ctx_b: Ctx = .{ .seen = 0 };
    const cb_a: Callback(fn (u32) void) = .bind(Ctx, &ctx_a, &boundStore);
    const cb_b: Callback(fn (u32) void) = .bind(Ctx, &ctx_b, &boundStore);

    try testing.expect(!cb_a.eql(cb_b));
}

test "unit: init produces a callback with the exact fields supplied" {
    const CB = Callback(fn (u32) void);
    const seed_ctx: ?*anyopaque = @ptrFromInt(0xDEADBEEF00);
    // We cannot call this — the invoke pointer would be invalid — but the
    // shape test suffices for the primitive contract.
    const Thunk = struct {
        fn invoke(_: ?*anyopaque, _: CB.Args) void {}
    };
    const cb: CB = .init(seed_ctx, &Thunk.invoke);
    try testing.expectEqual(seed_ctx, cb.context);
    try testing.expectEqual(&Thunk.invoke, cb.invoke);
}

test "unit: optional Callback slot supports missing entries" {
    var slot: ?Callback(fn () void) = null;
    try testing.expect(slot == null);

    slot = .wrap(&voidNoArg);
    if (slot) |cb| cb.call(.{});
}

test "unit: table of callbacks dispatches per-entry through call" {
    // Regression: two callbacks with different context values dispatched
    // consecutively through the same slot must each reach the correct
    // context.
    var ctx_a: Ctx = .{ .seen = 0 };
    var ctx_b: Ctx = .{ .seen = 0 };
    var table: [2]Callback(fn (u32) void) = .{
        .bind(Ctx, &ctx_a, &boundStore),
        .bind(Ctx, &ctx_b, &boundStore),
    };

    table[0].call(.{1});
    table[1].call(.{2});
    try testing.expectEqual(@as(u32, 1), ctx_a.seen);
    try testing.expectEqual(@as(u32, 2), ctx_b.seen);
}

test "unit: Callback works with a mutable global sink" {
    scratch = 0;
    const cb: Callback(fn (u32) void) = .wrap(&recordU32);
    cb.call(.{7});
    try testing.expectEqual(@as(u32, 7), scratch);
}

// Compile-only rejections — enforced by the `validate` helpers inside
// `src/func/validate.zig`. Zig cannot exercise `@compileError` cases at
// test runtime; the following invariants are trapped by the source:
//
//   Callback(T) traps at instantiation when T is:
//     - not a function type (e.g. Callback(u32))
//     - a generic function (comptime or anytype params)
//     - variadic
//     - naked (no return_type)
//     - any parameter with a null (anytype) concrete type
//
//   Callback(Fn).bind(Ctx, ctx, fn_ptr) traps when fn_ptr's type is not
//   a pointer to a function whose signature equals `Fn` with `*Ctx`
//   prepended as the first parameter.
//
//   Callback(Fn).bindMethod(Ctx, ctx, method_name) traps when:
//     - Ctx has no pub decl named `method_name`
//     - the resolved method's type is not a pointer to a function whose
//       signature equals `Fn` with `*Ctx` prepended as the first
//       parameter.

test "unit: Callback compiles and executes on the host regardless of arch" {
    const cb: Callback(fn (u32) u32) = .wrap(&addOne);
    _ = cb.call(.{0});
}
