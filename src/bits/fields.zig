const std = @import("std");

const masks = @import("mask.zig");

/// Named fields in an unsigned integer word.
/// Offsets: LSB-relative; implicit fields are contiguous.
/// Width: Declared integer type, explicit width, or 1.
/// Write: `.normal` by default; `.w1c` enables acknowledgement methods.
pub fn Fields(comptime T: type, comptime declarations: anytype) type {
    const schema = Impl.normalize(T, declarations);

    const has_ack = for (schema) |field| {
        if (field.write == .w1c) break true;
    } else false;

    return if (has_ack) enum(T) {
        _,

        const Ops = Impl.Operations(@This(), T, &schema);

        pub const Int = T;
        pub const Name = Ops.Name;
        pub const AckField = Ops.AckField;

        pub const from = Ops.from;
        pub const raw = Ops.raw;

        pub const mask = Ops.mask;
        pub const extract = Ops.extract;
        pub const encode = Ops.encode;
        pub const replace = Ops.replace;

        pub const ack = Ops.ack;
        pub const ackAll = Ops.ackAll;
    } else enum(T) {
        _,

        const Ops = Impl.Operations(@This(), T, &schema);

        pub const Int = T;
        pub const Name = Ops.Name;

        pub const from = Ops.from;
        pub const raw = Ops.raw;

        pub const mask = Ops.mask;
        pub const extract = Ops.extract;
        pub const encode = Ops.encode;
        pub const replace = Ops.replace;
    };
}

const Write = enum { normal, w1c };

const Field = struct {
    name: [:0]const u8,
    offset: usize,
    type: type,
    write: Write,
};

const Impl = struct {
    fn normalize(comptime T: type, comptime declarations: anytype) [entries(declarations).len]Field {
        if (!unsigned(T)) {
            @compileError("Fields requires a positive-width unsigned integer");
        }

        var schema: [entries(declarations).len]Field = undefined;
        var cursor: usize = 0;
        var previous: usize = 0;

        for (entries(declarations), 0..) |entry, index| {
            const value = @field(declarations, entry.name);
            const bare = @TypeOf(value) == type;

            if (!bare) {
                for (std.meta.fields(@TypeOf(value))) |property| {
                    if (!std.mem.eql(u8, property.name, "offset") and
                        !std.mem.eql(u8, property.name, "type") and
                        !std.mem.eql(u8, property.name, "width") and
                        !std.mem.eql(u8, property.name, "write"))
                    {
                        @compileError(std.fmt.comptimePrint("Fields: unknown property '{s}'", .{property.name}));
                    }
                }
            }

            const explicit_type = bare or @hasField(@TypeOf(value), "type");
            const Value = if (bare) value else if (explicit_type) value.type else u1;

            if (!unsigned(Value)) {
                @compileError(std.fmt.comptimePrint(
                    "Fields: field '{s}' requires a positive-width unsigned integer type",
                    .{entry.name},
                ));
            }

            const width: usize = if (!bare and @hasField(@TypeOf(value), "width")) value.width else @bitSizeOf(Value);
            const offset: usize = if (!bare and @hasField(@TypeOf(value), "offset")) value.offset else cursor;
            const write: Write = if (!bare and @hasField(@TypeOf(value), "write")) value.write else .normal;

            if (width == 0) {
                @compileError(std.fmt.comptimePrint("Fields: field '{s}' has zero width", .{entry.name}));
            }

            if (explicit_type and width != @bitSizeOf(Value)) {
                @compileError(std.fmt.comptimePrint("Fields: field '{s}' type and width disagree", .{entry.name}));
            }

            if (offset < previous) {
                @compileError(std.fmt.comptimePrint("Fields: field '{s}' is out of offset order", .{entry.name}));
            }

            if (offset < cursor) {
                @compileError(std.fmt.comptimePrint("Fields: field '{s}' overlaps the previous field", .{entry.name}));
            }

            if (offset > @bitSizeOf(T) or width > @bitSizeOf(T) - offset) {
                @compileError(std.fmt.comptimePrint("Fields: field '{s}' exceeds backing width", .{entry.name}));
            }

            schema[index] = .{
                .name = entry.name,
                .offset = offset,
                .type = if (explicit_type) Value else @Int(.unsigned, @intCast(width)),
                .write = write,
            };
            previous = offset;
            cursor = offset + width;
        }

        return schema;
    }

    fn Operations(comptime Self: type, comptime T: type, comptime schema: []const Field) type {
        return struct {
            pub const Name = Names(schema, null);
            pub const AckField = Names(schema, .w1c);

            const AllValues = Values(schema, null);
            const NormalValues = Values(schema, .normal);

            pub fn from(value: T) Self {
                return @enumFromInt(value);
            }

            pub fn raw(self: Self) T {
                return @intFromEnum(self);
            }

            /// Union of selected field masks.
            pub fn mask(comptime selection: anytype) T {
                return comptime selectionMask(T, schema, Name, selection);
            }

            pub fn extract(self: Self, comptime name: Name) lookup(schema, @tagName(name)).type {
                const field = comptime lookup(schema, @tagName(name));
                const shift: std.math.Log2Int(T) = @intCast(field.offset);

                return @truncate(raw(self) >> shift);
            }

            /// Unspecified bits are zero; write policies are not applied.
            pub fn encode(values: AllValues) T {
                var result: T = 0;

                inline for (schema) |field| {
                    if (@field(values, field.name)) |value| {
                        const shift: std.math.Log2Int(T) = @intCast(field.offset);
                        result |= @as(T, value) << shift;
                    }
                }

                return result;
            }

            /// Normal fields only; preserves unselected bits.
            pub fn replace(self: Self, values: NormalValues) Self {
                var result = raw(self);

                inline for (schema) |field| {
                    if (comptime field.write == .normal) {
                        if (@field(values, field.name)) |value| {
                            const shift: std.math.Log2Int(T) = @intCast(field.offset);
                            const field_mask = comptime fieldMask(T, field);
                            const encoded = @as(T, value) << shift;

                            result = (result & ~field_mask) | encoded;
                        }
                    }
                }

                return from(result);
            }

            /// Observed selected W1C bits; zero elsewhere.
            pub fn ack(self: Self, comptime selection: anytype) T {
                return raw(self) & comptime selectionMask(T, schema, AckField, selection);
            }

            pub fn ackAll(self: Self) T {
                const w1c_mask = comptime blk: {
                    var result: T = 0;

                    for (schema) |field| {
                        if (field.write == .w1c) result |= fieldMask(T, field);
                    }

                    break :blk result;
                };

                return raw(self) & w1c_mask;
            }
        };
    }

    fn Names(comptime schema: []const Field, comptime policy: ?Write) type {
        const len = count(schema, policy);

        var names: [len][]const u8 = undefined;
        var index: usize = 0;

        for (schema) |field| {
            if (policy == null or field.write == policy.?) {
                names[index] = field.name;
                index += 1;
            }
        }

        const Tag = std.math.IntFittingRange(0, len -| 1);
        return @Enum(Tag, .exhaustive, &names, &std.simd.iota(Tag, len));
    }

    fn Values(comptime schema: []const Field, comptime policy: ?Write) type {
        const len = count(schema, policy);

        var names: [len][:0]const u8 = undefined;
        var types: [len]type = undefined;
        var attributes: [len]std.builtin.Type.StructField.Attributes = undefined;
        var index: usize = 0;

        for (schema) |field| {
            if (policy == null or field.write == policy.?) {
                const Optional = ?field.type;

                names[index] = field.name;
                types[index] = Optional;
                attributes[index] = .{ .default_value_ptr = &@as(Optional, null) };
                index += 1;
            }
        }

        return @Struct(.auto, null, &names, &types, &attributes);
    }

    fn selectionMask(
        comptime T: type,
        comptime schema: []const Field,
        comptime Allowed: type,
        comptime selection: anytype,
    ) T {
        const info = @typeInfo(@TypeOf(selection));
        if (info == .enum_literal or info == .@"enum") {
            const name: Allowed = selection;
            return fieldMask(T, lookup(schema, @tagName(name)));
        }

        if (info != .@"struct" or (!info.@"struct".is_tuple and info.@"struct".fields.len != 0)) {
            @compileError("Fields: selection must be a field name or tuple");
        }

        var result: T = 0;

        for (selection) |item| {
            const name: Allowed = item;
            result |= fieldMask(T, lookup(schema, @tagName(name)));
        }

        return result;
    }

    fn fieldMask(comptime T: type, comptime field: Field) T {
        const shift: std.math.Log2Int(T) = @intCast(field.offset);
        return masks.low(T, @bitSizeOf(field.type)) << shift;
    }

    fn lookup(comptime schema: []const Field, comptime name: []const u8) Field {
        for (schema) |field| {
            if (std.mem.eql(u8, field.name, name)) return field;
        }

        unreachable;
    }

    fn count(comptime schema: []const Field, comptime policy: ?Write) usize {
        var result: usize = 0;

        for (schema) |field| {
            if (policy == null or field.write == policy.?) result += 1;
        }

        return result;
    }

    fn entries(comptime declarations: anytype) []const std.builtin.Type.StructField {
        const info = @typeInfo(@TypeOf(declarations));
        if (info != .@"struct" or (info.@"struct".is_tuple and info.@"struct".fields.len != 0)) {
            @compileError("Fields requires a named-field record");
        }

        return info.@"struct".fields;
    }

    fn unsigned(comptime T: type) bool {
        const info = @typeInfo(T);

        return info == .int and info.int.signedness == .unsigned and info.int.bits != 0;
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "named masks and narrow values agree at runtime and comptime" {
        const S = Fields(u32, .{
            .thing = u2,
            .another = .{ .offset = 3 },
            .something = .{ .write = .w1c },
        });

        const selected = comptime S.mask(.{ .thing, .something });
        try testing.expectEqual(@as(u32, 0x13), selected);
        try testing.expectEqual(@as(u32, 0), S.mask(.{}));
        try testing.expectEqual(@as(u32, 0x08), S.mask(.{ .another, .another }));

        const encoded = S.encode(.{ .thing = 2, .another = 1, .something = 1 });
        try testing.expectEqual(@as(u32, 0x1a), encoded);

        const word = S.from(encoded);
        try testing.expectEqual(@as(u2, 2), word.extract(.thing));
        try testing.expectEqual(@as(u1, 1), word.extract(.another));
        try testing.expectEqual(@as(u1, 1), word.extract(.something));

        const constant = comptime S.from(S.encode(.{ .thing = 3 })).replace(.{ .another = 1 });
        try testing.expectEqual(@as(u32, 0x0b), constant.raw());
        try testing.expectEqual(@as(u32, 0), S.encode(.{}));
    }

    test "replacement preserves unselected fields and unknown bits without mutation" {
        const S = Fields(u8, .{
            .mode = .{ .offset = 2, .type = u2 },
            .pending = .{ .offset = 6, .write = .w1c },
        });

        for (0..256) |input| {
            const word = S.from(@intCast(input));
            const updated = word.replace(.{ .mode = 2 });

            try testing.expectEqual(@as(u2, 2), updated.extract(.mode));
            try testing.expectEqual(word.raw() & 0xf3, updated.raw() & 0xf3);
            try testing.expectEqual(@as(u8, @intCast(input)), word.raw());
            try testing.expectEqual(word.raw(), word.replace(.{}).raw());
        }
    }

    test "full-width and highest-bit fields support narrow and wide backings" {
        inline for (.{ u1, u8, u17, u32, u64, u128 }) |T| {
            const Full = Fields(T, .{ .value = T });
            const max = std.math.maxInt(T);

            try testing.expectEqual(max, Full.mask(.value));
            try testing.expectEqual(max, Full.encode(.{ .value = max }));
            try testing.expectEqual(max, Full.from(max).extract(.value));
            try testing.expectEqual(@as(T, 0), Full.from(max).replace(.{ .value = 0 }).raw());

            const Top = Fields(T, .{ .top = .{ .offset = @bitSizeOf(T) - 1, .write = .w1c } });
            const top: T = @as(T, 1) << (@bitSizeOf(T) - 1);
            try testing.expectEqual(top, Top.mask(.top));
            try testing.expectEqual(top, Top.from(max).ackAll());
            try testing.expectEqual(@as(u1, 1), Top.from(top).extract(.top));
        }
    }

    test "empty schemas preserve opaque word values" {
        const S = Fields(u16, .{});

        try testing.expectEqual(@as(u16, 0), S.mask(.{}));
        try testing.expectEqual(@as(u16, 0), S.encode(.{}));
        try testing.expectEqual(@as(u16, 0xabcd), S.from(0xabcd).replace(.{}).raw());
    }

    test "acknowledgements contain only observed selected W1C bits" {
        const S = Fields(u32, .{
            .mode = u2,
            .done = .{ .offset = 4, .write = .w1c },
            .errors = .{ .offset = 8, .type = u3, .width = 3, .write = .w1c },
        });

        try testing.expect(@hasDecl(S, "AckField"));
        try testing.expect(@hasDecl(S, "ack"));
        try testing.expect(@hasDecl(S, "ackAll"));

        const errors: S.AckField = .errors;
        const word = S.from(0x80000503);
        try testing.expectEqual(@as(u32, 0), word.ack(.done));
        try testing.expectEqual(@as(u32, 0x500), word.ack(errors));
        try testing.expectEqual(@as(u32, 0x500), word.ack(.{ .done, .errors, .done }));
        try testing.expectEqual(@as(u32, 0x500), word.ackAll());
        try testing.expectEqual(@as(u32, 0), word.ack(.{}));
        try testing.expectEqual(@as(u3, 5), word.extract(.errors));

        const updated = word.replace(.{ .mode = 1 });
        try testing.expectEqual(@as(u32, 0x80000501), updated.raw());
        try testing.expectEqual(word.ackAll(), updated.ackAll());
        try testing.expectEqual(@as(u32, 0x80000503), word.raw());

        const set = S.from(0x80000513);
        try testing.expectEqual(@as(u32, 0x10), set.ack(.done));
        try testing.expectEqual(@as(u32, 0x510), set.ackAll());

        const constant = comptime S.from(0x103).ackAll();
        try testing.expectEqual(@as(u32, 0x100), constant);
    }

    test "runtime optional values distinguish omission from clearing" {
        const S = Fields(u8, .{ .value = u2 });

        try testing.expect(!@hasDecl(S, "AckField"));
        try testing.expect(!@hasDecl(S, "ack"));
        try testing.expect(!@hasDecl(S, "ackAll"));

        const inputs = [_]?u2{ null, 0, 1, 2, 3 };
        const encoded = [_]u8{ 0, 0, 1, 2, 3 };
        const replaced = [_]u8{ 0xfb, 0xf8, 0xf9, 0xfa, 0xfb };

        for (inputs, encoded, replaced) |value, payload, result| {
            try testing.expectEqual(payload, S.encode(.{ .value = value }));
            try testing.expectEqual(result, S.from(0xfb).replace(.{ .value = value }).raw());
        }
    }
};
