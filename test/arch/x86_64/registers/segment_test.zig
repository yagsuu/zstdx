const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const registers = x86.registers;

const testing = std.testing;

fn expectFn(comptime T: type, comptime f: anytype) void {
    comptime testing.expectEqual(T, @TypeOf(f)) catch unreachable;
}

test "model: segment selector representations preserve every bit" {
    inline for (.{ registers.cs.CS, registers.ds.DS, registers.es.ES, registers.fs.FS, registers.gs.GS, registers.ss.SS }) |T| {
        try testing.expectEqual(@as(usize, 2), @sizeOf(T));
        try testing.expectEqual(@as(u16, 0xa5f3), T.fromInt(0xa5f3).raw());
    }
    try testing.expectEqual(@as(u16, 0), registers.cs.CS.init().raw());

    const cs = registers.cs.CS.fromInt(0xffff);
    try testing.expectEqual(@as(u2, 3), cs.rpl);
    try testing.expectEqual(.ldt, cs.table);
    try testing.expectEqual(@as(u13, 0x1fff), cs.index);
    comptime testing.expect(registers.cs.CS != registers.ds.DS) catch unreachable;
}

test "model: FS and GS base representations preserve every bit" {
    inline for (.{ registers.fs_base.FSBase, registers.gs_base.GSBase }) |T| {
        try testing.expectEqual(@as(usize, 8), @sizeOf(T));
        try testing.expectEqual(@as(u64, 0xa5f3_5ca9_3d7e_1c42), T.fromInt(0xa5f3_5ca9_3d7e_1c42).raw());
    }
    try testing.expectEqual(@as(u64, 0), registers.fs_base.FSBase.init().raw());
}

test "compile: segment register accessors instantiate" {
    if (!x86.supported) return;
    expectFn(fn () registers.cs.CS, registers.cs.read);
    expectFn(fn (registers.cs.CS) void, registers.cs.writeFarReturn);
    inline for (.{ registers.ds, registers.es, registers.fs, registers.gs, registers.ss }) |namespace| {
        const T = @TypeOf(namespace.read());
        expectFn(fn () T, namespace.read);
        expectFn(fn (T) void, namespace.write);
    }
    expectFn(fn () registers.fs_base.FSBase, registers.fs_base.read);
    expectFn(fn (registers.fs_base.FSBase) void, registers.fs_base.write);
    expectFn(fn () registers.gs_base.GSBase, registers.gs_base.read);
    expectFn(fn (registers.gs_base.GSBase) void, registers.gs_base.write);
    expectFn(fn () void, registers.gs_base.swap);
}
