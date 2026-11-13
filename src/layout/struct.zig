const std = @import("std");

const alignment = @import("alignment.zig");

const assertLayout = @import("assert.zig").assertLayout;

/// Extern layout with exact byte size and explicit or naturally placed fields.
/// Fields: `T` or `{ type, offset?, default? }`; nonzero-sized, extern-compatible.
/// Gaps default to zero.
pub fn Struct(comptime options: Options, comptime fields: anytype) type {
    return Impl.Build(options, fields);
}

const Options = struct {
    size: usize,
    alignment: usize = 1,
};

const Field = struct {
    name: [:0]const u8,
    offset: usize,
    type: type,
    default: ?*const anyopaque,
};

const Impl = struct {
    fn Build(comptime options: Options, comptime fields: anytype) type {
        const resolved = resolve(options, fields);
        const members = layoutMembers(options, &resolved);

        var names: [members.len][:0]const u8 = undefined;
        var types: [members.len]type = undefined;
        var attributes: [members.len]std.builtin.Type.StructField.Attributes = undefined;

        for (members, 0..) |member, index| {
            const field_align = if (index == 0)
                options.alignment
            else
                @min(@alignOf(member.type), std.math.gcd(options.alignment, member.offset));

            names[index] = member.name;
            types[index] = member.type;

            attributes[index] = .{
                .@"align" = field_align,
                .default_value_ptr = member.default,
            };
        }

        const T = @Struct(.@"extern", null, &names, &types, &attributes);

        assertLayout(T, .{ .size = options.size, .alignment = options.alignment });
        for (resolved) |field| {
            std.debug.assert(@offsetOf(T, field.name) == field.offset);
        }

        return T;
    }

    fn layoutMembers(comptime options: Options, comptime fields: []const Field) [memberCount(options, fields)]Field {
        var members: [memberCount(options, fields)]Field = undefined;
        var offset: usize = 0;
        var index: usize = 0;

        for (fields) |field| {
            if (field.offset > offset) {
                members[index] = padding(offset, field.offset);
                index += 1;
            }

            members[index] = field;
            index += 1;
            offset = field.offset + @sizeOf(field.type);
        }

        if (offset < options.size or index == 0) {
            members[index] = padding(offset, options.size);
            index += 1;
        }

        std.debug.assert(index == members.len);
        std.debug.assert(offset <= options.size);

        return members;
    }

    fn memberCount(comptime options: Options, comptime fields: []const Field) usize {
        var count: usize = 0;
        var offset: usize = 0;

        for (fields) |field| {
            if (field.offset > offset) {
                count += 1;
            }

            count += 1;
            offset = field.offset + @sizeOf(field.type);
        }

        if (offset < options.size or count == 0) {
            count += 1;
        }

        std.debug.assert(offset <= options.size);
        std.debug.assert(count >= fields.len);

        return count;
    }

    fn padding(comptime start: usize, comptime end: usize) Field {
        std.debug.assert(start <= end);

        const T = [end - start]u8;
        const initial: T = @splat(0);

        return .{
            .name = std.fmt.comptimePrint("$pad[0x{x:0>4}..0x{x:0>4})", .{ start, end }),
            .offset = start,
            .type = T,
            .default = &initial,
        };
    }

    fn resolve(comptime options: Options, comptime fields: anytype) [entries(fields).len]Field {
        if (options.alignment == 0 or !std.math.isPowerOfTwo(options.alignment)) {
            @compileError("Struct: alignment must be a nonzero power of two");
        }

        if (options.size % options.alignment != 0) {
            @compileError("Struct: size must be a multiple of alignment");
        }

        var resolved: [entries(fields).len]Field = undefined;
        var offset: usize = 0;
        var prev_offset: usize = 0;

        for (entries(fields), 0..) |entry, field_index| {
            const declaration = @field(fields, entry.name);
            const Resolved = ResolveField(entry.name, declaration, offset);

            const field: Field = .{
                .name = entry.name,
                .offset = Resolved.offset,
                .type = Resolved.Type,
                .default = Resolved.default,
            };

            if (field.offset < prev_offset) {
                @compileError(std.fmt.comptimePrint("Struct: field '{s}' is out of offset order", .{field.name}));
            }

            if (field.offset < offset) {
                @compileError(std.fmt.comptimePrint("Struct: field '{s}' overlaps the previous field", .{field.name}));
            }

            if (field.offset > options.size or Resolved.size > options.size - field.offset) {
                @compileError(std.fmt.comptimePrint("Struct: field '{s}' exceeds size", .{field.name}));
            }

            resolved[field_index] = field;
            offset = field.offset + Resolved.size;
            prev_offset = field.offset;
        }

        return resolved;
    }

    fn ResolveField(
        comptime name: [:0]const u8,
        comptime declaration: anytype,
        comptime cursor: usize,
    ) type {
        const bare = @TypeOf(declaration) == type;

        if (!bare) {
            for (std.meta.fields(@TypeOf(declaration))) |property| {
                const known = std.mem.eql(u8, property.name, "offset") or
                    std.mem.eql(u8, property.name, "type") or
                    std.mem.eql(u8, property.name, "default");

                if (!known) {
                    @compileError(std.fmt.comptimePrint("Struct: unknown field property '{s}'", .{property.name}));
                }
            }
        }

        if (std.mem.startsWith(u8, name, "$pad")) {
            @compileError(std.fmt.comptimePrint("Struct: field '{s}' uses reserved prefix '$pad'", .{name}));
        }

        const T = if (bare) declaration else declaration.type;
        if (@sizeOf(T) == 0) {
            @compileError(std.fmt.comptimePrint("Struct: field '{s}' has zero size", .{name}));
        }

        return struct {
            pub const Type = T;
            pub const size = @sizeOf(Type);
            pub const offset = blk: {
                if (!bare and @hasField(@TypeOf(declaration), "offset")) {
                    break :blk declaration.offset;
                }

                break :blk alignment.alignUp(usize, cursor, @alignOf(Type)) catch {
                    @compileError(std.fmt.comptimePrint("Struct: field '{s}' exceeds size", .{name}));
                };
            };

            pub const default: ?*const anyopaque = blk: {
                if (!bare and @hasField(@TypeOf(declaration), "default")) {
                    const value: Type = declaration.default;
                    break :blk @ptrCast(&value);
                }

                break :blk null;
            };
        };
    }

    fn entries(comptime fields: anytype) []const std.builtin.Type.StructField {
        const info = @typeInfo(@TypeOf(fields));
        if (info != .@"struct") {
            @compileError("Struct: fields must be a named-field record");
        }

        if (info.@"struct".is_tuple and info.@"struct".fields.len != 0) {
            @compileError("Struct: fields must be a named-field record");
        }

        return info.@"struct".fields;
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "partial literals apply typed defaults and zero every generated gap" {
        const Mode = enum(u16) { idle, active = 3 };
        const T = Struct(.{ .size = 32, .alignment = 8 }, .{
            .required = .{ .offset = 2, .type = u8 },
            .magic = .{ .offset = 5, .type = u32, .default = 0x12345678 },
            .mode = .{ .type = Mode, .default = .active },
            .bytes = .{ .offset = 16, .type = [3]u8, .default = .{ 1, 2, 3 } },
            .tail = .{ .offset = 24, .type = u16, .default = 0xabcd },
        });

        const object: T = .{ .required = 0x7f };
        const overridden: T = .{ .required = 1, .magic = 7, .mode = .idle };
        const magic: u32 = 0x12345678;
        const mode: Mode = .active;
        const tail: u16 = 0xabcd;
        var expected: [32]u8 = @splat(0);

        expected[2] = 0x7f;
        @memcpy(expected[5..9], std.mem.asBytes(&magic));
        @memcpy(expected[10..12], std.mem.asBytes(&mode));
        @memcpy(expected[16..19], &[_]u8{ 1, 2, 3 });
        @memcpy(expected[24..26], std.mem.asBytes(&tail));

        try testing.expectEqualSlices(u8, &expected, std.mem.asBytes(&object));
        try testing.expectEqual(@as(u32, 7), overridden.magic);
        try testing.expectEqual(Mode.idle, overridden.mode);
        try testing.expectEqual(@as(u16, 0xabcd), overridden.tail);
        try testing.expectEqual(*align(1) const u32, @TypeOf(&object.magic));
    }

    test "nested and nullable defaults remain typed values" {
        const Target = struct {
            const value: u32 = 42;
        };

        const Inner = Struct(.{ .size = 8 }, .{
            .value = .{ .offset = 1, .type = u32, .default = 9 },
        });

        const Outer = Struct(.{ .size = 32, .alignment = 8 }, .{
            .inner = .{ .offset = 3, .type = Inner, .default = Inner{} },
            .required = .{ .offset = 16, .type = u32 },
            .pointer = .{ .offset = 24, .type = ?*const u32, .default = null },
        });

        const object: Outer = .{ .required = 7 };
        const overridden: Outer = .{
            .inner = .{ .value = 99 },
            .required = 8,
            .pointer = &Target.value,
        };

        const bytes = std.mem.asBytes(&object);

        try testing.expectEqual(@as(u32, 9), object.inner.value);
        try testing.expectEqual(@as(u32, 99), overridden.inner.value);
        try testing.expect(object.pointer == null);
        try testing.expectEqual(@as(u32, 42), overridden.pointer.?.*);

        for (bytes, 0..) |byte, offset| {
            if (offset < 4 or (offset >= 8 and offset < 16) or (offset >= 20 and offset < 24)) {
                try testing.expectEqual(@as(u8, 0), byte);
            }
        }
    }

    test "implicit fields use natural offsets after an unaligned explicit anchor" {
        const T = Impl.Build(.{ .size = 19 }, .{
            .tag = u8,
            .anchor = .{ .offset = 3, .type = u16 },
            .count = .{ .type = u32 },
            .tail = .{ .offset = 17, .type = u8 },
            .last = u8,
        });

        try testing.expectEqual(@as(usize, 19), @sizeOf(T));
        try testing.expectEqual(@as(usize, 1), @alignOf(T));
        try testing.expectEqual(@as(usize, 3), @offsetOf(T, "anchor"));
        try testing.expectEqual(@as(usize, 8), @offsetOf(T, "count"));
        try testing.expectEqual(@as(usize, 18), @offsetOf(T, "last"));

        var object: T = undefined;
        const bytes = std.mem.asBytes(&object);
        @memset(bytes, 0xa5);

        object.tag = 1;
        object.anchor = 0x1234;
        object.count = 0x12345678;
        object.tail = 2;
        object.last = 3;

        const anchor: u16 = 0x1234;
        const count: u32 = 0x12345678;
        try testing.expectEqualSlices(u8, std.mem.asBytes(&anchor), bytes[3..5]);
        try testing.expectEqualSlices(u8, std.mem.asBytes(&count), bytes[8..12]);

        for (bytes, 0..) |byte, offset| {
            if ((offset >= 1 and offset < 3) or (offset >= 5 and offset < 8) or
                (offset >= 12 and offset < 17))
            {
                try testing.expectEqual(@as(u8, 0xa5), byte);
            }
        }

        bytes[18] = 9;
        try testing.expectEqual(@as(u8, 9), object.last);

        try testing.expectEqual(*align(1) u32, @TypeOf(&object.count));
    }

    test "fully implicit fields preserve exact size and byte access" {
        const T = Impl.Build(.{ .size = 9 }, .{
            .tag = u8,
            .count = .{ .type = u32 },
            .tail = u8,
        });

        try testing.expectEqual(@as(usize, 9), @sizeOf(T));
        try testing.expectEqual(@as(usize, 1), @alignOf(T));
        try testing.expectEqual(@as(usize, 0), @offsetOf(T, "tag"));
        try testing.expectEqual(@as(usize, 4), @offsetOf(T, "count"));
        try testing.expectEqual(@as(usize, 8), @offsetOf(T, "tail"));

        var objects: [2]T = undefined;
        @memset(std.mem.asBytes(&objects), 0);

        objects[1].count = 42;

        const count: u32 = 42;
        try testing.expectEqualSlices(u8, std.mem.asBytes(&count), std.mem.asBytes(&objects)[13..17]);
        try testing.expectEqual(@as(usize, 9), @intFromPtr(&objects[1]) - @intFromPtr(&objects[0]));
    }

    test "explicit offsets preserve unknown bytes" {
        const T = Impl.Build(.{ .size = 32, .alignment = 8 }, .{
            .tag = .{ .offset = 0, .type = u8 },
            .count = .{ .offset = 3, .type = u32 },
            .owner = .{ .offset = 16, .type = u64 },
        });

        var object: T = undefined;
        const bytes = std.mem.asBytes(&object);
        @memset(bytes, 0xa5);

        object.tag = 0x7f;
        object.count = 0x12345678;
        object.owner = 0xfedcba9876543210;

        const count: u32 = 0x12345678;
        const owner: u64 = 0xfedcba9876543210;
        try testing.expectEqual(@as(u8, 0x7f), bytes[0]);
        try testing.expectEqualSlices(u8, std.mem.asBytes(&count), bytes[3..7]);
        try testing.expectEqualSlices(u8, std.mem.asBytes(&owner), bytes[16..24]);

        for (bytes, 0..) |byte, offset| {
            if ((offset >= 1 and offset < 3) or (offset >= 7 and offset < 16) or offset >= 24) {
                try testing.expectEqual(@as(u8, 0xa5), byte);
            }
        }

        try testing.expectEqual(*align(1) u32, @TypeOf(&object.count));
        try testing.expectEqual(*align(8) u64, @TypeOf(&object.owner));

        @memset(bytes[3..7], 0);
        try testing.expectEqual(@as(u32, 0), object.count);
    }

    test "unaligned nested fields preserve aligned array stride" {
        const Inner = Impl.Build(.{ .size = 8 }, .{
            .value = .{ .offset = 1, .type = u32 },
        });

        const Outer = Impl.Build(.{ .size = 32, .alignment = 16 }, .{
            .inner = .{ .offset = 3, .type = Inner },
        });

        var objects: [2]Outer = undefined;
        @memset(std.mem.asBytes(&objects), 0);

        objects[1].inner.value = 42;

        try testing.expectEqual(@as(usize, 32), @intFromPtr(&objects[1]) - @intFromPtr(&objects[0]));
        try testing.expectEqual(@as(usize, 0), @intFromPtr(&objects[1]) % 16);
        try testing.expectEqual(@as(u32, 0), objects[0].inner.value);
        try testing.expectEqual(@as(u32, 42), objects[1].inner.value);

        const value: u32 = 42;
        try testing.expectEqualSlices(u8, std.mem.asBytes(&value), std.mem.asBytes(&objects)[36..40]);
    }

    test "extern union payload follows an unaligned record" {
        const Record = Impl.Build(.{ .size = 12, .alignment = 4 }, .{
            .first = .{ .offset = 1, .type = u32 },
            .second = .{ .offset = 6, .type = u16 },
        });

        const Payload = extern union {
            integer: u64,
            bytes: [8]u8,
        };

        const T = Impl.Build(.{ .size = 24, .alignment = 8 }, .{
            .record = .{ .offset = 0, .type = Record },
            .payload = .{ .offset = 16, .type = Payload },
        });

        var object: T = undefined;
        const bytes = std.mem.asBytes(&object);
        @memset(bytes, 0xa5);

        object.record.first = 0x12345678;
        object.record.second = 0xabcd;
        object.payload.integer = 0xfedcba9876543210;

        const first: u32 = 0x12345678;
        const second: u16 = 0xabcd;
        const payload: u64 = 0xfedcba9876543210;
        try testing.expectEqualSlices(u8, std.mem.asBytes(&first), bytes[1..5]);
        try testing.expectEqualSlices(u8, std.mem.asBytes(&second), bytes[6..8]);
        try testing.expectEqualSlices(u8, std.mem.asBytes(&payload), &object.payload.bytes);
        try testing.expectEqualSlices(u8, std.mem.asBytes(&payload), bytes[16..24]);

        for (bytes, 0..) |byte, offset| {
            if (offset == 0 or offset == 5 or (offset >= 8 and offset < 16)) {
                try testing.expectEqual(@as(u8, 0xa5), byte);
            }
        }

        try testing.expectEqual(@as(usize, 24), @sizeOf(T));
        try testing.expectEqual(@as(usize, 8), @alignOf(T));
    }

    test "adjacent fields fill the declared record" {
        const T = Impl.Build(.{ .size = 8 }, .{
            .first = .{ .offset = 0, .type = u32 },
            .second = .{ .offset = 4, .type = u32 },
        });

        var object: T = undefined;
        object.first = 0x12345678;
        object.second = 0xabcdef01;

        const first: u32 = 0x12345678;
        const second: u32 = 0xabcdef01;
        const bytes = std.mem.asBytes(&object);
        try testing.expectEqual(@as(usize, 8), bytes.len);
        try testing.expectEqualSlices(u8, std.mem.asBytes(&first), bytes[0..4]);
        try testing.expectEqualSlices(u8, std.mem.asBytes(&second), bytes[4..8]);
    }

    test "empty records preserve reserved storage and zero size" {
        const Empty = Impl.Build(.{ .size = 8, .alignment = 4 }, .{});
        const Zero = Impl.Build(.{ .size = 0 }, .{});
        const AlignedZero = Impl.Build(.{ .size = 0, .alignment = 8 }, .{});

        const initialized: Empty = .{};
        const zero: Zero = .{};
        const aligned_zero: AlignedZero = .{};

        var records: [2]Empty = undefined;
        @memset(std.mem.asBytes(&records), 0xa5);
        @memset(std.mem.asBytes(&records[1]), 0x5a);

        try testing.expectEqualSlices(u8, &([_]u8{0} ** 8), std.mem.asBytes(&initialized));
        try testing.expectEqual(@as(usize, 0), std.mem.asBytes(&zero).len);
        try testing.expectEqual(@as(usize, 0), std.mem.asBytes(&aligned_zero).len);
        try testing.expectEqualSlices(u8, &([_]u8{0xa5} ** 8), std.mem.asBytes(&records[0]));
        try testing.expectEqualSlices(u8, &([_]u8{0x5a} ** 8), std.mem.asBytes(&records[1]));
        try testing.expectEqual(@as(usize, 8), @intFromPtr(&records[1]) - @intFromPtr(&records[0]));
        try testing.expectEqual(@as(usize, 4), @alignOf(Empty));
        try testing.expectEqual(@as(usize, 0), @sizeOf(Zero));
        try testing.expectEqual(@as(usize, 1), @alignOf(Zero));
        try testing.expectEqual(@as(usize, 0), @sizeOf(AlignedZero));
        try testing.expectEqual(@as(usize, 8), @alignOf(AlignedZero));
    }
};
