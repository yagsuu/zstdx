//! MMIO access. See `docs/specs/io/mmio.md`.

const std = @import("std");

const addr = @import("addr");
const endian = @import("layout").endian;

pub const Mmio = struct {
    pub fn Register(comptime T: type) type {
        return extern struct {
            value: Int,

            pub const size = @sizeOf(Int);

            pub const __StdxMmioRegister = void;

            const Self = @This();

            pub const Value = T;
            pub const Int = Impl.Word(T);

            pub fn load(self: *const volatile Self) T {
                return Impl.load(T, &self.value);
            }

            pub fn store(self: *volatile Self, value: T) void {
                Impl.store(T, &self.value, value);
            }
        };
    }

    pub fn Ref(comptime T: type) type {
        return struct {
            ptr: Pointer,

            const Self = @This();
            const Pointer = *const volatile Impl.Word(T);

            pub fn from(address: addr.VirtAddr) error{Misaligned}!Self {
                return .{ .ptr = try addr.castAligned(Pointer, address) };
            }

            pub fn load(self: Self) T {
                return Impl.load(T, self.ptr);
            }
        };
    }

    pub fn RefMut(comptime T: type) type {
        return struct {
            ptr: Pointer,

            const Self = @This();
            const Pointer = *volatile Impl.Word(T);

            pub fn from(address: addr.VirtAddr) error{Misaligned}!Self {
                return .{ .ptr = try addr.castAligned(Pointer, address) };
            }

            pub fn load(self: Self) T {
                return Impl.load(T, self.ptr);
            }

            pub fn store(self: Self, value: T) void {
                Impl.store(T, self.ptr, value);
            }
        };
    }

    pub const Window = struct {
        bytes: []volatile u8,

        const Self = @This();

        pub const Error = Impl.Error;

        pub fn from(bytes: []volatile u8) Self {
            return .{ .bytes = bytes };
        }

        pub fn reg(self: Self, comptime T: type, offset: usize) Error!Ref(T) {
            return .{ .ptr = try Impl.reg(*const volatile Impl.Word(T), self.bytes, offset) };
        }

        pub fn regMut(self: Self, comptime T: type, offset: usize) Error!RefMut(T) {
            return .{ .ptr = try Impl.reg(*volatile Impl.Word(T), self.bytes, offset) };
        }

        pub fn field(self: Self, comptime Layout: type, comptime name: []const u8) Error!Ref(@FieldType(Layout, name).Value) {
            const T = @FieldType(Layout, name).Value;
            return .{ .ptr = try Impl.field(*const volatile Impl.Word(T), Layout, name, self.bytes) };
        }

        pub fn fieldMut(self: Self, comptime Layout: type, comptime name: []const u8) Error!RefMut(@FieldType(Layout, name).Value) {
            const T = @FieldType(Layout, name).Value;
            return .{ .ptr = try Impl.field(*volatile Impl.Word(T), Layout, name, self.bytes) };
        }
    };
};

const Impl = struct {
    const Error = error{ OutOfBounds, Misaligned };

    fn Word(comptime T: type) type {
        const invalid = "Mmio.Register requires u8/u16/u32/u64, layout.Le/Be over those widths, or a packed struct backed by those widths";

        const Int = switch (@typeInfo(T)) {
            .int => T,
            .@"struct" => |info| if (info.layout == .@"packed")
                info.backing_integer orelse @compileError(invalid)
            else if (@hasDecl(T, "Int"))
                T.Int
            else
                @compileError(invalid),
            else => @compileError(invalid),
        };

        switch (Int) {
            u8, u16, u32, u64 => {},
            else => @compileError(invalid),
        }

        if (T != Int and @typeInfo(T).@"struct".layout != .@"packed") {
            if (T != endian.Le(Int) and T != endian.Be(Int)) {
                @compileError(invalid);
            }
        }

        return Int;
    }

    fn wrapper(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .@"struct" => |info| info.layout != .@"packed" and @hasDecl(T, "Int"),
            else => false,
        };
    }

    fn load(comptime T: type, pointer: *const volatile Word(T)) T {
        if (comptime wrapper(T)) {
            return .{ .bytes = @bitCast(pointer.*) };
        }
        return @bitCast(pointer.*);
    }

    fn store(comptime T: type, pointer: *volatile Word(T), value: T) void {
        if (comptime wrapper(T)) {
            pointer.* = @bitCast(value.bytes);
            return;
        }
        pointer.* = @bitCast(value);
    }

    fn reg(comptime Pointer: type, bytes: []volatile u8, offset: usize) Error!Pointer {
        const size = @sizeOf(@typeInfo(Pointer).pointer.child);
        if (size > bytes.len) {
            return error.OutOfBounds;
        }

        if (offset > bytes.len - size) {
            return error.OutOfBounds;
        }

        const address = addr.cast(addr.VirtAddr, bytes.ptr + offset);
        return addr.castAligned(Pointer, address);
    }

    fn field(comptime Pointer: type, comptime Layout: type, comptime name: []const u8, bytes: []volatile u8) Error!Pointer {
        const info = @typeInfo(Layout);
        if (info != .@"struct" or info.@"struct".layout != .@"extern") {
            @compileError("Mmio.Window.field requires an extern struct layout");
        }

        const Lane = @FieldType(Layout, name);

        if (@typeInfo(Lane) != .@"struct" or !@hasDecl(Lane, "__StdxMmioRegister")) {
            @compileError("Mmio.Window.field requires Register(T) fields");
        }

        return reg(Pointer, bytes, @offsetOf(Layout, name));
    }
};

pub const unit = struct {
    const testing = std.testing;

    const Flags = packed struct(u32) {
        enabled: bool,
        mode: u3,
        _reserved_4: u28,
    };

    test "endian registers encode device bytes and packed updates preserve reserved bits" {
        var bytes: [16]u8 align(8) = @splat(0);
        const window = Mmio.Window.from(&bytes);
        const little = try window.regMut(endian.Le(u32), 0);
        const big = try window.regMut(endian.Be(u32), 4);
        const flags = try window.regMut(Flags, 8);

        little.store(.from(0x12345678));
        big.store(.from(0x12345678));
        flags.store(.{ .enabled = false, .mode = 2, ._reserved_4 = 0xdeadbee });

        var updated = flags.load();
        updated.enabled = true;
        updated.mode = 3;
        flags.store(updated);

        try testing.expectEqualSlices(u8, &.{ 0x78, 0x56, 0x34, 0x12 }, bytes[0..4]);
        try testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56, 0x78 }, bytes[4..8]);
        try testing.expectEqual(@as(u32, 0x12345678), (try window.reg(endian.Le(u32), 0)).load().native());
        try testing.expectEqual(@as(u32, 0x12345678), (try window.reg(endian.Be(u32), 4)).load().native());
        try testing.expectEqual(@as(u32, 0xdeadbee7), std.mem.readInt(u32, bytes[8..12], @import("builtin").cpu.arch.endian()));
    }

    test "window bounds and alignment use the actual register address" {
        var bytes: [16]u8 align(8) = @splat(0);
        const window = Mmio.Window.from(&bytes);
        const shifted = Mmio.Window.from(bytes[1..]);
        const empty = Mmio.Window.from(bytes[0..0]);

        (try window.regMut(u32, 12)).store(0x12345678);
        (try shifted.regMut(u32, 3)).store(0xaabbccdd);

        try testing.expectEqual(@as(u32, 0x12345678), (try window.reg(u32, 12)).load());
        try testing.expectEqual(@as(u32, 0xaabbccdd), (try window.reg(u32, 4)).load());
        try testing.expectError(error.OutOfBounds, window.reg(u32, 13));
        try testing.expectError(error.OutOfBounds, window.reg(u8, std.math.maxInt(usize)));
        try testing.expectError(error.OutOfBounds, empty.reg(u8, 0));
        try testing.expectError(error.Misaligned, window.reg(u32, 2));
        try testing.expectError(error.Misaligned, shifted.reg(u32, 0));
    }

    test "extern fields preserve overlay offsets and enforce lane alignment" {
        const Layout = extern struct {
            id: Mmio.Register(u16),
            _padding: [6]u8,
            config: Mmio.Register(endian.Le(u32)),
            status: Mmio.Register(Flags),
        };
        const Unaligned = extern struct {
            prefix: u8,
            value: Mmio.Register(endian.Le(u32)) align(1),
        };
        var bytes: [16]u8 align(8) = @splat(0);
        const window = Mmio.Window.from(&bytes);

        (try window.fieldMut(Layout, "config")).store(.from(0x12345678));
        (try window.fieldMut(Layout, "status")).store(.{ .enabled = true, .mode = 3, ._reserved_4 = 0 });

        try testing.expectEqualSlices(u8, &.{ 0x78, 0x56, 0x34, 0x12 }, bytes[8..12]);
        try testing.expectEqual(@as(u3, 3), (try window.field(Layout, "status")).load().mode);
        try testing.expectError(error.Misaligned, window.field(Unaligned, "value"));
    }

    test "standalone references validate alignment and alias overlay lanes" {
        const Layout = extern struct {
            control: Mmio.Register(Flags),
        };
        var registers: Layout = .{ .control = .{ .value = 0xdeadbee0 } };
        const address = addr.cast(addr.VirtAddr, &registers.control);
        const reference = try Mmio.RefMut(Flags).from(address);
        const readonly = try Mmio.Ref(Flags).from(address);
        var value = reference.load();

        value.enabled = true;
        value.mode = 3;
        reference.store(value);

        try testing.expectEqual(@as(u32, 0xdeadbee7), registers.control.value);
        try testing.expect(readonly.load().enabled);

        registers.control.store(.{ .enabled = false, .mode = 2, ._reserved_4 = 0 });

        try testing.expectEqual(@as(u3, 2), reference.load().mode);
        try testing.expect(!registers.control.load().enabled);
        try testing.expectError(error.Misaligned, Mmio.Ref(Flags).from(try address.add(1)));
        try testing.expectError(error.Misaligned, Mmio.RefMut(Flags).from(try address.add(1)));
    }
};
