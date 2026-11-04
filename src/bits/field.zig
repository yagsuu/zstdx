const std = @import("std");

pub fn BitField(comptime T: type, comptime declarations: anytype) type {
    const schema = Impl.normalize(T, declarations);

    return if (Impl.count(&schema, .clear) != 0)
        Impl.AckApi(T, &schema)
    else
        Impl.Api(T, &schema);
}

const Access = enum { rw, ro, reserved };
const Write = enum { assign, w1c, w0c, trigger };
const Filter = enum { all, readable, assignable, clear, trigger };

const PolicyMasks = struct {
    rw: comptime_int = 0,
    ro: comptime_int = 0,
    reserved: comptime_int = 0,
    assign: comptime_int = 0,
    w1c: comptime_int = 0,
    w0c: comptime_int = 0,
    trigger: comptime_int = 0,
};

const Field = struct {
    name: [:0]const u8,
    offset: usize,
    type: type,
    policy: PolicyMasks,
    default: comptime_int,
};

const Impl = struct {
    fn Api(comptime T: type, comptime schema: []const Field) type {
        return if (count(schema, .trigger) != 0) struct {
            const Ops = Impl.Operations(T, schema);
            const __StdxBitField = Ops.Metadata;

            pub const Int = T;
            pub const Word = Ops.Word;
            pub const Metadata = Ops.Metadata;
            pub const Name = Ops.Name;
            pub const TriggerField = Ops.TriggerField;

            pub const masks = Ops.masks;

            pub const init = Ops.init;
            pub const from = Ops.from;
            pub const raw = Ops.raw;

            pub const encode = Ops.encode;
            pub const replace = Ops.replace;

            pub const mask = Ops.mask;
            pub const trigger = Ops.trigger;
        } else struct {
            const Ops = Impl.Operations(T, schema);
            const __StdxBitField = Ops.Metadata;

            pub const Int = T;
            pub const Word = Ops.Word;
            pub const Metadata = Ops.Metadata;
            pub const Name = Ops.Name;

            pub const masks = Ops.masks;

            pub const init = Ops.init;
            pub const from = Ops.from;
            pub const raw = Ops.raw;

            pub const encode = Ops.encode;
            pub const replace = Ops.replace;

            pub const mask = Ops.mask;
        };
    }

    fn AckApi(comptime T: type, comptime schema: []const Field) type {
        return if (count(schema, .trigger) != 0) struct {
            const Ops = Impl.Operations(T, schema);
            const __StdxBitField = Ops.Metadata;

            pub const Int = T;
            pub const Word = Ops.Word;
            pub const Metadata = Ops.Metadata;
            pub const Name = Ops.Name;
            pub const AckField = Ops.AckField;
            pub const TriggerField = Ops.TriggerField;

            pub const masks = Ops.masks;

            pub const init = Ops.init;
            pub const from = Ops.from;
            pub const raw = Ops.raw;

            pub const encode = Ops.encode;
            pub const replace = Ops.replace;

            pub const mask = Ops.mask;
            pub const ack = Ops.ack;
            pub const ackAll = Ops.ackAll;

            pub const trigger = Ops.trigger;
        } else struct {
            const Ops = Impl.Operations(T, schema);
            const __StdxBitField = Ops.Metadata;

            pub const Int = T;
            pub const Word = Ops.Word;
            pub const Metadata = Ops.Metadata;
            pub const Name = Ops.Name;
            pub const AckField = Ops.AckField;

            pub const masks = Ops.masks;

            pub const init = Ops.init;
            pub const from = Ops.from;
            pub const raw = Ops.raw;

            pub const encode = Ops.encode;
            pub const replace = Ops.replace;

            pub const mask = Ops.mask;
            pub const ack = Ops.ack;
            pub const ackAll = Ops.ackAll;
        };
    }

    fn Operations(comptime T: type, comptime schema: []const Field) type {
        return struct {
            const Meta = Impl.Metadata(T, schema);
            const AllValues = Values(schema, .readable);
            const AssignValues = Values(schema, .assignable);

            pub const Word = PackedWord(T, schema);
            pub const Name = Names(schema, .all);
            pub const AckField = Names(schema, .clear);
            pub const TriggerField = Names(schema, .trigger);
            pub const Metadata = Meta;

            pub const masks = Meta.masks;

            pub fn init() Word {
                return from(encode(.{}));
            }

            pub fn from(value: T) Word {
                return @bitCast(value);
            }

            pub fn raw(word: Word) T {
                return @bitCast(word);
            }

            pub fn encode(values: AllValues) T {
                return encodeValues(T, schema, values);
            }

            pub fn replace(word: Word, values: AssignValues) Word {
                return from(replaceValues(T, schema, raw(word), values));
            }

            pub fn mask(comptime selection: anytype) T {
                return Meta.mask(selection);
            }

            pub fn ack(word: Word, comptime selection: anytype) T {
                const selected = comptime Meta.ackMask(selection);
                return acknowledge(T, masks, raw(word), selected);
            }

            pub fn ackAll(word: Word) T {
                return acknowledge(T, masks, raw(word), masks.clear);
            }

            pub fn trigger(comptime selection: anytype) T {
                return Meta.triggerMask(selection);
            }
        };
    }

    fn PackedWord(comptime T: type, comptime schema: []const Field) type {
        const len = memberCount(T, schema);
        var names: [len][:0]const u8 = undefined;
        var types: [len]type = undefined;
        var attributes: [len]std.builtin.Type.StructField.Attributes = undefined;

        var index: usize = 0;
        var offset: usize = 0;

        for (schema) |field| {
            if (field.offset > offset) {
                names[index] = std.fmt.comptimePrint("$pad[0x{x:0>4}..0x{x:0>4})", .{ offset, field.offset });
                types[index] = @Int(.unsigned, @intCast(field.offset - offset));
                const initial: types[index] = 0;
                attributes[index] = .{ .default_value_ptr = &initial };
                index += 1;
            }

            names[index] = field.name;
            types[index] = ValueType(field.type);

            const initial = fromBits(field.type, @as(FieldInt(field.type), field.default));
            attributes[index] = .{ .default_value_ptr = &initial };

            index += 1;
            offset = field.offset + @bitSizeOf(FieldInt(field.type));
        }

        if (offset < @bitSizeOf(T)) {
            names[index] = std.fmt.comptimePrint("$pad[0x{x:0>4}..0x{x:0>4})", .{ offset, @bitSizeOf(T) });
            types[index] = @Int(.unsigned, @intCast(@bitSizeOf(T) - offset));

            const initial: types[index] = 0;
            attributes[index] = .{ .default_value_ptr = &initial };

            index += 1;
        }

        std.debug.assert(index == len);

        const Word = @Struct(.@"packed", T, &names, &types, &attributes);

        std.debug.assert(@bitSizeOf(Word) == @bitSizeOf(T));
        for (schema) |field| {
            std.debug.assert(@bitOffsetOf(Word, field.name) == field.offset);
        }

        return Word;
    }

    fn memberCount(comptime T: type, comptime schema: []const Field) usize {
        var len: usize = schema.len;
        var offset: usize = 0;

        for (schema) |field| {
            if (field.offset > offset) len += 1;
            offset = field.offset + @bitSizeOf(FieldInt(field.type));
        }

        if (offset < @bitSizeOf(T)) len += 1;
        return len;
    }

    fn Names(comptime schema: []const Field, comptime filter: Filter) type {
        const len = count(schema, filter);

        var names: [len][]const u8 = undefined;
        var index: usize = 0;

        for (schema) |field| {
            if (includes(field, filter)) {
                names[index] = field.name;
                index += 1;
            }
        }

        const Tag = std.math.IntFittingRange(0, len -| 1);
        return @Enum(Tag, .exhaustive, &names, &std.simd.iota(Tag, len));
    }

    fn Values(comptime schema: []const Field, comptime filter: Filter) type {
        const len = count(schema, filter);

        var names: [len][:0]const u8 = undefined;
        var types: [len]type = undefined;
        var attributes: [len]std.builtin.Type.StructField.Attributes = undefined;
        var index: usize = 0;

        for (schema) |field| {
            if (includes(field, filter)) {
                const Optional = ?ValueType(field.type);

                names[index] = field.name;
                types[index] = Optional;
                attributes[index] = .{ .default_value_ptr = &@as(Optional, null) };
                index += 1;
            }
        }

        return @Struct(.auto, null, &names, &types, &attributes);
    }

    fn Metadata(comptime T: type, comptime schema: []const Field) type {
        return struct {
            pub const Int = T;
            pub const masks = Masks(T, schema);

            pub fn mask(comptime selection: anytype) T {
                const Allowed = Names(schema, .all);
                return comptime selectionMask(T, schema, Allowed, .all, selection);
            }

            pub fn ackMask(comptime selection: anytype) T {
                const Allowed = Names(schema, .clear);
                return comptime selectionMask(T, schema, Allowed, .clear, selection);
            }

            pub fn triggerMask(comptime selection: anytype) T {
                const Allowed = Names(schema, .trigger);
                return comptime selectionMask(T, schema, Allowed, .trigger, selection);
            }
        };
    }

    fn Masks(comptime T: type, comptime schema: []const Field) type {
        const bits = blk: {
            var result: PolicyMasks = .{};

            for (schema) |field| {
                for (std.meta.fields(PolicyMasks)) |category| {
                    @field(result, category.name) |= @field(field.policy, category.name) << field.offset;
                }
            }

            break :blk result;
        };

        std.debug.assert((bits.rw & (bits.ro | bits.reserved)) == 0);
        std.debug.assert((bits.assign | bits.w1c | bits.w0c | bits.trigger) == bits.rw);

        return struct {
            pub const rw: T = bits.rw;
            pub const ro: T = bits.ro;
            pub const reserved: T = bits.reserved;

            /// RW assignment fields only.
            pub const assign: T = bits.assign;
            pub const w1c: T = bits.w1c;
            pub const w0c: T = bits.w0c;
            pub const trigger: T = bits.trigger;

            pub const readable: T = rw | ro;
            pub const clear: T = w1c | w0c;
            pub const declared: T = readable | reserved;

            /// Undeclared bits; explicit reserved fields remain declared.
            pub const unknown: T = ~declared;
        };
    }

    fn normalize(comptime T: type, comptime declarations: anytype) [entries(declarations).len]Field {
        if (!unsigned(T)) {
            @compileError("BitField requires a positive-width unsigned integer");
        }

        var schema: [entries(declarations).len]Field = undefined;
        var cursor: usize = 0;
        var previous: usize = 0;

        for (entries(declarations), 0..) |entry, index| {
            const Resolved = ResolveField(T, entry.name, @field(declarations, entry.name), cursor);

            const width = @bitSizeOf(Resolved.Int);
            const field: Field = .{
                .name = entry.name,
                .offset = Resolved.offset,
                .type = Resolved.Type,
                .policy = Resolved.policy,
                .default = Resolved.default,
            };

            if (field.offset < previous) {
                @compileError(std.fmt.comptimePrint("BitField: field '{s}' is out of offset order", .{entry.name}));
            }

            if (field.offset < cursor) {
                @compileError(std.fmt.comptimePrint("BitField: field '{s}' overlaps the previous field", .{entry.name}));
            }

            if (field.offset > @bitSizeOf(T) or width > @bitSizeOf(T) - field.offset) {
                @compileError(std.fmt.comptimePrint("BitField: field '{s}' exceeds backing width", .{entry.name}));
            }

            schema[index] = field;
            previous = field.offset;
            cursor = field.offset + width;
        }

        return schema;
    }

    fn ResolveField(
        comptime T: type,
        comptime name: [:0]const u8,
        comptime value: anytype,
        comptime cursor: usize,
    ) type {
        if (std.mem.startsWith(u8, name, "$pad")) {
            @compileError("BitField: field names starting with '$pad' are reserved");
        }

        const bare = @TypeOf(value) == type;

        if (!bare) {
            for (std.meta.fields(@TypeOf(value))) |property| {
                const known = std.mem.eql(u8, property.name, "offset") or
                    std.mem.eql(u8, property.name, "type") or
                    std.mem.eql(u8, property.name, "width") or
                    std.mem.eql(u8, property.name, "access") or
                    std.mem.eql(u8, property.name, "write") or
                    std.mem.eql(u8, property.name, "default");

                if (!known) {
                    @compileError(std.fmt.comptimePrint("BitField: unknown property '{s}'", .{property.name}));
                }
            }
        }

        const explicit_type = bare or @hasField(@TypeOf(value), "type");

        const Value = if (bare) value else if (explicit_type) value.type else u1;
        const Tag = FieldInt(Value);

        const width: usize = if (!bare and @hasField(@TypeOf(value), "width")) value.width else @bitSizeOf(Tag);
        if (width == 0) {
            @compileError(std.fmt.comptimePrint("BitField: field '{s}' has zero width", .{name}));
        }

        if (explicit_type and width != @bitSizeOf(Tag)) {
            @compileError(std.fmt.comptimePrint("BitField: field '{s}' type and width disagree", .{name}));
        }

        if (width > @bitSizeOf(T)) {
            @compileError(std.fmt.comptimePrint("BitField: field '{s}' exceeds backing width", .{name}));
        }

        const FieldType = if (explicit_type) Value else @Int(.unsigned, @intCast(width));

        if (nested(FieldType) and !bare) {
            if (@hasField(@TypeOf(value), "access") or @hasField(@TypeOf(value), "write")) {
                @compileError("BitField: nested groups cannot override access or write policy");
            }
        }

        const access: Access = if (!bare and @hasField(@TypeOf(value), "access")) value.access else .rw;
        const write: Write = if (!bare and @hasField(@TypeOf(value), "write")) value.write else .assign;

        if (access != .rw and write != .assign) {
            @compileError(std.fmt.comptimePrint(
                "BitField: field '{s}' requires RW access for non-assignment writes",
                .{name},
            ));
        }

        return struct {
            pub const Type = FieldType;
            pub const Int = FieldInt(Type);
            pub const offset = if (!bare and @hasField(@TypeOf(value), "offset")) value.offset else cursor;

            pub const policy: PolicyMasks = blk: {
                const full = std.math.maxInt(Int);
                var result: PolicyMasks = .{};

                if (nested(Type)) {
                    const Meta = Type.__StdxBitField;

                    if (Meta.Int != Int) {
                        @compileError("BitField: nested metadata backing type does not match field backing type");
                    }

                    for (std.meta.fields(PolicyMasks)) |category| {
                        const bits: comptime_int = @field(Meta.masks, category.name);
                        if (bits < 0 or bits > full) {
                            @compileError("BitField: nested policy mask exceeds field width");
                        }

                        @field(result, category.name) = bits;
                    }

                    break :blk result;
                }

                switch (access) {
                    .rw => {
                        result.rw = full;

                        switch (write) {
                            .assign => result.assign = full,
                            .w1c => result.w1c = full,
                            .w0c => result.w0c = full,
                            .trigger => result.trigger = full,
                        }
                    },
                    .ro => result.ro = full,
                    .reserved => result.reserved = full,
                }

                break :blk result;
            };

            pub const default: comptime_int = blk: {
                var initial = fromBits(Type, @as(Int, policy.w0c));

                if (!bare and @hasField(@TypeOf(value), "default")) {
                    initial = value.default;
                }

                const bits: comptime_int = toBits(Int, initial);
                const zero = policy.w1c | policy.trigger;

                if ((bits & zero) != 0 or (bits & policy.w0c) != policy.w0c) {
                    @compileError(std.fmt.comptimePrint("BitField: field '{s}' requires a neutral write default", .{name}));
                }

                break :blk bits;
            };
        };
    }

    fn encodeValues(comptime T: type, comptime schema: []const Field, values: anytype) T {
        var result: T = 0;

        inline for (schema) |field| {
            var value: T = field.default;

            if (comptime includes(field, .readable)) {
                if (@field(values, field.name)) |supplied| {
                    value = toBits(T, supplied);
                }
            }

            const shift: std.math.Log2Int(T) = @intCast(field.offset);
            result |= value << shift;
        }

        return result;
    }

    fn replaceValues(comptime T: type, comptime schema: []const Field, word: T, values: anytype) T {
        var result = word;

        inline for (schema) |field| {
            if (comptime includes(field, .assignable)) {
                if (@field(values, field.name)) |value| {
                    const shift: std.math.Log2Int(T) = @intCast(field.offset);
                    const field_mask = comptime fieldMask(T, field, .assignable);
                    const encoded = (toBits(T, value) << shift) & field_mask;

                    result = (result & ~field_mask) | encoded;
                }
            }
        }

        return result;
    }

    fn acknowledge(comptime T: type, comptime categories: type, word: T, comptime selected: T) T {
        const observed = word & selected;
        return (observed & categories.w1c) | (categories.w0c & ~observed);
    }

    fn selectionMask(
        comptime T: type,
        comptime schema: []const Field,
        comptime Allowed: type,
        comptime filter: Filter,
        comptime selection: anytype,
    ) T {
        const info = @typeInfo(@TypeOf(selection));
        if (info == .enum_literal or info == .@"enum") {
            const name: Allowed = selection;
            return fieldMask(T, lookup(schema, @tagName(name)), filter);
        }

        if (info != .@"struct") {
            @compileError("BitField: selection must be a field name, tuple, or nested record");
        }

        var result: T = 0;

        if (info.@"struct".is_tuple) {
            for (selection) |item| {
                result |= selectionMask(T, schema, Allowed, filter, item);
            }
        } else {
            for (std.meta.fields(@TypeOf(selection))) |entry| {
                const name: Allowed = @field(Allowed, entry.name);
                const field = lookup(schema, @tagName(name));

                result |= nestedMask(T, field, filter, @field(selection, entry.name));
            }
        }

        return result;
    }

    fn nestedMask(comptime T: type, comptime field: Field, comptime filter: Filter, comptime selection: anytype) T {
        if (!nested(field.type)) {
            @compileError("BitField: nested selection requires a marked bit-field type");
        }

        const MetadataType = field.type.__StdxBitField;
        const selected = switch (filter) {
            .all => MetadataType.mask(selection),
            .clear => MetadataType.ackMask(selection),
            .trigger => MetadataType.triggerMask(selection),
            else => unreachable,
        };
        const shift: std.math.Log2Int(T) = @intCast(field.offset);

        return @as(T, selected) << shift;
    }

    fn fieldMask(comptime T: type, comptime field: Field, comptime filter: Filter) T {
        const shift: std.math.Log2Int(T) = @intCast(field.offset);

        return @as(T, policyBits(field, filter)) << shift;
    }

    fn policyBits(comptime field: Field, comptime filter: Filter) comptime_int {
        return switch (filter) {
            .all => std.math.maxInt(FieldInt(field.type)),
            .readable => field.policy.rw | field.policy.ro,
            .assignable => field.policy.assign,
            .clear => field.policy.w1c | field.policy.w0c,
            .trigger => field.policy.trigger,
        };
    }

    fn ValueType(comptime T: type) type {
        return if (nested(T)) T.Word else T;
    }

    fn FieldInt(comptime T: type) type {
        if (nested(T)) return T.Int;

        if (T == bool) return u1;
        if (unsigned(T)) return T;

        const info = @typeInfo(T);
        if (info != .@"enum") {
            @compileError("BitField: field type must be bool, an unsigned integer, an enum, or a BitField namespace");
        }

        const Int = info.@"enum".tag_type;
        if (!unsigned(Int)) {
            @compileError("BitField: enum fields require a positive-width unsigned tag");
        }

        if (info.@"enum".is_exhaustive) {
            const len: comptime_int = info.@"enum".fields.len;

            if (len == 0 or len - 1 != std.math.maxInt(Int)) {
                @compileError("BitField: exhaustive enum must cover every tag value");
            }
        }

        return Int;
    }

    fn toBits(comptime T: type, value: anytype) T {
        return switch (@typeInfo(@TypeOf(value))) {
            .bool => @intFromBool(value),
            .@"enum" => @intFromEnum(value),
            .@"struct" => @as(@typeInfo(@TypeOf(value)).@"struct".backing_integer.?, @bitCast(value)),
            else => value,
        };
    }

    fn fromBits(comptime T: type, value: FieldInt(T)) ValueType(T) {
        if (nested(T)) return @bitCast(value);

        return switch (@typeInfo(T)) {
            .bool => value != 0,
            .@"enum" => @enumFromInt(value),
            else => value,
        };
    }

    fn lookup(comptime schema: []const Field, comptime name: []const u8) Field {
        for (schema) |field| {
            if (std.mem.eql(u8, field.name, name)) return field;
        }

        unreachable;
    }

    fn count(comptime schema: []const Field, comptime filter: Filter) usize {
        var result: usize = 0;

        for (schema) |field| {
            if (includes(field, filter)) result += 1;
        }

        return result;
    }

    fn includes(comptime field: Field, comptime filter: Filter) bool {
        return policyBits(field, filter) != 0;
    }

    fn entries(comptime declarations: anytype) []const std.builtin.Type.StructField {
        const info = @typeInfo(@TypeOf(declarations));
        if (info != .@"struct" or (info.@"struct".is_tuple and info.@"struct".fields.len != 0)) {
            @compileError("BitField requires a named-field record");
        }

        return info.@"struct".fields;
    }

    fn nested(comptime T: type) bool {
        return @typeInfo(T) == .@"struct" and @hasDecl(T, "__StdxBitField");
    }

    fn unsigned(comptime T: type) bool {
        const info = @typeInfo(T);
        return info == .int and info.int.signedness == .unsigned and info.int.bits != 0;
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "full-width and highest-bit fields support narrow and wide backings" {
        @setEvalBranchQuota(10_000);

        inline for (.{ u1, u8, u17, u32, u64, u128 }) |T| {
            const Full = BitField(T, .{ .value = T });
            const max = std.math.maxInt(T);

            try testing.expectEqual(max, Full.mask(.value));
            try testing.expectEqual(max, Full.encode(.{ .value = max }));
            try testing.expectEqual(max, Full.from(max).value);
            try testing.expectEqual(@as(T, 0), Full.raw(Full.replace(Full.from(max), .{ .value = 0 })));
            try testing.expectEqual(max, Full.masks.assign);
            try testing.expectEqual(@as(T, 0), Full.masks.unknown);

            const Top = BitField(T, .{ .top = .{ .offset = @bitSizeOf(T) - 1, .write = .w1c } });
            const top: T = @as(T, 1) << (@bitSizeOf(T) - 1);

            try testing.expectEqual(top, Top.mask(.top));
            try testing.expectEqual(top, Top.ackAll(Top.from(max)));
            try testing.expectEqual(@as(u1, 1), Top.from(top).top);
            try testing.expectEqual(top, Top.masks.clear);
            try testing.expectEqual(max & ~top, Top.masks.unknown);

            const Tag = enum(T) { zero = 0, _ };
            const Typed = BitField(T, .{ .value = Tag });
            const unknown: Tag = @enumFromInt(max);

            try testing.expectEqual(max, @intFromEnum(Typed.from(max).value));
            try testing.expectEqual(max, Typed.encode(.{ .value = unknown }));
            try testing.expectEqual(@as(T, 0), Typed.raw(Typed.replace(Typed.from(max), .{ .value = .zero })));
        }
    }

    test "empty schemas preserve opaque word values" {
        const S = BitField(u16, .{});
        const empty: S.Word = .{};

        try testing.expectEqual(@as(u16, 0), S.mask(.{}));
        try testing.expectEqual(@as(u16, 0), S.encode(.{}));
        try testing.expectEqual(@as(u16, 0), S.raw(empty));
        try testing.expectEqual(@as(u16, 0xabcd), S.raw(S.replace(S.from(0xabcd), .{})));
        try testing.expectEqual(@as(u16, 0), S.masks.declared);
        try testing.expectEqual(@as(u16, 0xffff), S.masks.unknown);
        try testing.expectEqual(@as(u16, 0), S.masks.rw | S.masks.ro | S.masks.reserved);
    }

    test "partial word literals preserve typed defaults and zero unknown bits" {
        const Mode = enum(u2) { idle, receive, transmit, loopback };
        const S = BitField(u16, .{
            .enabled = .{ .type = bool, .default = true },
            .mode = .{ .offset = 3, .type = Mode, .default = .receive },
            .ready = .{ .type = bool, .access = .ro, .default = true },
            .fixed = .{ .type = bool, .access = .reserved, .default = true },
            .done = .{ .type = bool, .write = .w1c },
            .quiet = .{ .type = bool, .write = .w0c },
            .go = .{ .type = bool, .write = .trigger },
        });

        const initial: S.Word = .{};
        const partial: S.Word = .{ .enabled = false, .mode = .transmit };
        const unchecked: S.Word = .{
            .ready = false,
            .fixed = false,
            .done = true,
            .quiet = false,
            .go = true,
        };

        try testing.expectEqual(@as(u16, 0x169), S.raw(initial));
        try testing.expectEqual(S.raw(S.init()), S.raw(initial));
        try testing.expectEqual(@as(u16, 0x170), S.raw(partial));
        try testing.expectEqual(Mode.transmit, partial.mode);
        try testing.expectEqual(@as(u16, 0), S.raw(partial) & S.masks.unknown);
        try testing.expectEqual(@as(u16, 0x289), S.raw(unchecked));
    }

    test "typed defaults construct words without constraining raw snapshots" {
        const S = BitField(u8, .{
            .enabled = .{ .type = bool, .default = true },
            .mode = .{ .type = u2, .default = 2 },
            .ready = .{ .type = bool, .access = .ro, .default = true },
            .pending = .{ .type = bool, .write = .w1c },
            .quiet = .{ .type = bool, .write = .w0c },
            .reserved = .{ .type = u2, .access = .reserved, .default = 2 },
        });

        const initial = comptime S.init();

        try testing.expectEqual(@as(u8, 0xad), S.raw(initial));
        try testing.expect(initial.enabled);
        try testing.expect(initial.quiet);
        try testing.expect(!initial.pending);
        try testing.expectEqual(@as(u2, 2), initial.mode);

        try testing.expect(initial.ready);
        try testing.expectEqual(@as(u8, 0xc0), S.mask(.reserved));
        try testing.expectEqual(@as(u8, 0x92), S.encode(.{
            .enabled = false,
            .mode = 1,
            .ready = false,
            .pending = true,
            .quiet = false,
        }));

        const snapshot = S.from(0xff);
        const updated = S.replace(snapshot, .{ .enabled = false, .mode = 0 });

        try testing.expectEqual(@as(u8, 0xf8), S.raw(updated));
        try testing.expect(updated.ready);
        try testing.expect(updated.pending);
        try testing.expect(updated.quiet);
        try testing.expectEqual(@as(u8, 0xff), S.raw(snapshot));
        try testing.expectEqual(@as(u8, 0x40), S.raw(S.replace(S.from(0x40), .{})));
        try testing.expectEqual(@as(u8, 0), S.ackAll(initial));
    }

    test "reserved-only schemas construct defaults without rewriting snapshots" {
        const S = BitField(u8, .{
            .reserved = .{ .type = bool, .access = .reserved, .default = true },
        });

        try testing.expectEqual(@as(u8, 1), S.encode(.{}));
        try testing.expectEqual(@as(u8, 1), S.raw(S.init()));
        try testing.expectEqual(@as(u8, 0x80), S.raw(S.replace(S.from(0x80), .{})));
        try testing.expectEqual(@as(u8, 1), S.mask(.reserved));
        try testing.expectEqual(@as(u8, 0), S.masks.rw | S.masks.assign | S.masks.clear);
        try testing.expectEqual(@as(u8, 1), S.masks.reserved);
        try testing.expect(!@hasDecl(S, "ack"));
    }

    test "runtime optional values distinguish omission from clearing" {
        const S = BitField(u8, .{ .value = u2 });

        try testing.expect(!@hasDecl(S, "AckField"));
        try testing.expect(!@hasDecl(S, "ack"));
        try testing.expect(!@hasDecl(S, "ackAll"));

        const inputs = [_]?u2{ null, 0, 1, 2, 3 };
        const encoded = [_]u8{ 0, 0, 1, 2, 3 };
        const replaced = [_]u8{ 0xfb, 0xf8, 0xf9, 0xfa, 0xfb };

        for (inputs, encoded, replaced) |value, payload, result| {
            try testing.expectEqual(payload, S.encode(.{ .value = value }));
            try testing.expectEqual(result, S.raw(S.replace(S.from(0xfb), .{ .value = value })));
        }
    }

    test "optional bool inputs distinguish defaults from replacement omission" {
        const S = BitField(u8, .{
            .enabled = .{ .type = bool, .default = true },
            .ready = .{ .type = bool, .access = .ro, .default = true },
            .live = bool,
        });

        const inputs = [_]?bool{ null, false, true };
        const encoded = [_]u8{ 3, 2, 3 };
        const replaced = [_]u8{ 0x80, 0x80, 0x81 };

        for (inputs, encoded, replaced) |value, payload, result| {
            try testing.expectEqual(payload, S.encode(.{ .enabled = value }));
            try testing.expectEqual(result, S.raw(S.replace(S.from(0x80), .{ .enabled = value })));
        }

        try testing.expect(!S.init().live);
        try testing.expectEqual(@as(u8, 7), S.raw(S.replace(S.init(), .{ .live = true })));
    }

    test "enum fields preserve named and unknown values across conversion" {
        const Mode = enum(u2) { disabled, polling, interrupt, _ };
        const S = BitField(u16, .{
            .guard = .{ .type = u2, .default = 3 },
            .mode = .{ .offset = 4, .type = Mode, .default = .interrupt },
            .fallback = Mode,
        });

        const initial = comptime S.init();

        try testing.expectEqual(@as(u16, 0x23), S.raw(initial));
        try testing.expectEqual(Mode.interrupt, initial.mode);
        try testing.expectEqual(Mode.disabled, initial.fallback);
        try testing.expectEqual(@as(u16, 0x91), S.encode(.{
            .guard = 1,
            .mode = .polling,
            .fallback = .interrupt,
        }));

        const snapshot = S.from(0xabff);
        const unknown: Mode = snapshot.mode;

        try testing.expectEqual(@as(u2, 3), @intFromEnum(unknown));
        try testing.expectEqual(@as(u16, 0x33), S.encode(.{ .mode = unknown }));
        try testing.expectEqual(@as(u16, 0xabdf), S.raw(S.replace(snapshot, .{ .mode = .polling })));
        try testing.expectEqual(@as(u16, 0x30), S.mask(.mode));
    }

    test "complete exhaustive enums accept every raw field value" {
        const Tag = enum(u2) { three = 3, one = 1, zero = 0, two = 2 };
        const S = BitField(u8, .{ .value = .{ .type = Tag, .width = 2 } });

        const tags = [_]Tag{ .three, .one, .zero, .two };
        const values = [_]u8{ 3, 1, 0, 2 };

        try testing.expectEqual(Tag.zero, S.init().value);

        for (tags, values) |tag, value| {
            try testing.expectEqual(value, S.encode(.{ .value = tag }));
            try testing.expectEqual(tag, S.from(value | 0xfc).value);
            try testing.expectEqual(value | 0xfc, S.raw(S.replace(S.from(0xff), .{ .value = tag })));
        }
    }

    test "ordinary enums with mask declarations do not inherit field policies" {
        const Tag = enum(u2) {
            zero,
            one,
            _,

            pub const masks = struct {
                pub const reserved: u2 = 3;
            };
        };
        const S = BitField(u8, .{ .value = Tag });

        try testing.expectEqual(@as(u8, 3), S.masks.assign);
        try testing.expectEqual(@as(u8, 0), S.masks.reserved);
        try testing.expectEqual(@as(u8, 0xfc), S.raw(S.replace(S.from(0xff), .{ .value = .zero })));
    }

    test "named masks and narrow values agree at runtime and comptime" {
        const S = BitField(u32, .{
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
        try testing.expectEqual(@as(u2, 2), word.thing);
        try testing.expectEqual(@as(u1, 1), word.another);
        try testing.expectEqual(@as(u1, 1), word.something);

        const constant = comptime S.replace(S.from(S.encode(.{ .thing = 3 })), .{ .another = 1 });
        try testing.expectEqual(@as(u32, 0x0b), S.raw(constant));
        try testing.expectEqual(@as(u32, 0), S.encode(.{}));
    }

    test "category masks partition access and write policies at compile time" {
        const S = BitField(u16, .{
            .control = u2,
            .ready = .{ .offset = 3, .type = bool, .access = .ro },
            .reserved = .{ .width = 2, .access = .reserved },
            .done = .{ .offset = 8, .type = bool, .write = .w1c },
            .errors = .{ .width = 2, .write = .w0c },
        });

        try testing.expectEqual(@as(u16, 0x703), S.masks.rw);
        try testing.expectEqual(@as(u16, 0x008), S.masks.ro);
        try testing.expectEqual(@as(u16, 0x030), S.masks.reserved);
        try testing.expectEqual(@as(u16, 0x003), S.masks.assign);
        try testing.expectEqual(@as(u16, 0x100), S.masks.w1c);
        try testing.expectEqual(@as(u16, 0x600), S.masks.w0c);
        try testing.expectEqual(@as(u16, 0x70b), S.masks.readable);
        try testing.expectEqual(@as(u16, 0x700), S.masks.clear);
        try testing.expectEqual(@as(u16, 0x73b), S.masks.declared);
        try testing.expectEqual(@as(u16, 0xf8c4), S.masks.unknown);

        const non_mutable = comptime S.masks.ro | S.masks.reserved;
        const selected = comptime S.mask(.{ .control, .done }) & S.masks.clear;
        try testing.expectEqual(@as(u16, 0x38), non_mutable);
        try testing.expectEqual(@as(u16, 0x100), selected);

        try testing.expectEqual(@as(u16, 0), S.masks.assign & (S.masks.ro | S.masks.reserved));
    }

    test "replacement preserves unselected fields and unknown bits without mutation" {
        const S = BitField(u8, .{
            .mode = .{ .offset = 2, .type = u2 },
            .pending = .{ .offset = 6, .write = .w1c },
        });

        for (0..256) |input| {
            const word = S.from(@intCast(input));
            const updated = S.replace(word, .{ .mode = 2 });

            try testing.expectEqual(@as(u2, 2), updated.mode);
            try testing.expectEqual(S.raw(word) & 0xf3, S.raw(updated) & 0xf3);
            try testing.expectEqual(@as(u8, @intCast(input)), S.raw(word));
            try testing.expectEqual(S.raw(word), S.raw(S.replace(word, .{})));
        }
    }

    test "acknowledgements contain only observed selected W1C bits" {
        const S = BitField(u32, .{
            .mode = u2,
            .done = .{ .offset = 4, .write = .w1c },
            .errors = .{ .offset = 8, .type = u3, .width = 3, .write = .w1c },
        });

        try testing.expect(@hasDecl(S, "AckField"));
        try testing.expect(@hasDecl(S, "ack"));
        try testing.expect(@hasDecl(S, "ackAll"));

        const errors: S.AckField = .errors;
        const word = S.from(0x80000503);
        try testing.expectEqual(@as(u32, 0), S.ack(word, .done));
        try testing.expectEqual(@as(u32, 0x500), S.ack(word, errors));
        try testing.expectEqual(@as(u32, 0x500), S.ack(word, .{ .done, .errors, .done }));
        try testing.expectEqual(@as(u32, 0x500), S.ackAll(word));
        try testing.expectEqual(@as(u32, 0), S.ack(word, .{}));
        try testing.expectEqual(@as(u3, 5), word.errors);

        const updated = S.replace(word, .{ .mode = 1 });
        try testing.expectEqual(@as(u32, 0x80000501), S.raw(updated));
        try testing.expectEqual(S.ackAll(word), S.ackAll(updated));
        try testing.expectEqual(@as(u32, 0x80000503), S.raw(word));

        const set = S.from(0x80000513);
        try testing.expectEqual(@as(u32, 0x10), S.ack(set, .done));
        try testing.expectEqual(@as(u32, 0x510), S.ackAll(set));

        const constant = comptime S.ackAll(S.from(0x103));
        try testing.expectEqual(@as(u32, 0x100), constant);
    }

    test "W0C acknowledgements preserve unselected and unobserved flags" {
        const S = BitField(u8, .{
            .first = .{ .type = u2, .write = .w0c },
            .second = .{ .type = u2, .write = .w0c },
        });

        const word = S.from(0xf6);

        try testing.expectEqual(@as(u8, 0x0f), S.raw(S.init()));
        try testing.expectEqual(@as(u8, 0x0d), S.ack(word, .first));
        try testing.expectEqual(@as(u8, 0x0b), S.ack(word, .second));
        try testing.expectEqual(@as(u8, 0x09), S.ack(word, .{ .first, .second }));
        try testing.expectEqual(@as(u8, 0x09), S.ackAll(word));
        try testing.expectEqual(@as(u8, 0x0f), S.ack(word, .{}));
        try testing.expectEqual(@as(u8, 0x0f), S.ackAll(S.from(0)));

        const first: S.AckField = .first;
        const constant = comptime S.ack(S.from(0x06), first);
        try testing.expectEqual(@as(u8, 0x0d), constant);
    }

    test "mixed clear payloads clear only selected snapshot bits after new events" {
        const S = BitField(u8, .{
            .one = .{ .type = u2, .write = .w1c },
            .zero = .{ .offset = 4, .type = u2, .write = .w0c },
            .mode = .{ .type = u2, .write = .assign },
        });

        const selections = .{ .{}, .one, .zero, .{ .one, .zero } };

        inline for (selections) |selection| {
            const selected = comptime S.mask(selection);

            for (0..256) |input| {
                const snapshot: u8 = @intCast(input);
                const payload = S.ack(S.from(snapshot), selection);
                const current = snapshot | 0x33;
                const cleared_one = (current & 0x03) & ~payload;
                const cleared_zero = (current & 0x30) & payload;
                const expected = (current & 0x33) & ~(snapshot & selected);

                try testing.expectEqual(expected, cleared_one | cleared_zero);
                try testing.expectEqual(@as(u8, 0), payload & 0xcc);
            }
        }

        try testing.expectEqual(@as(u8, 0x11), S.ackAll(S.from(0xe5)));
        try testing.expectEqual(@as(u8, 0x31), S.ack(S.from(0xe5), .one));
        try testing.expectEqual(@as(u8, 0x10), S.ack(S.from(0xe5), .zero));
    }

    test "W0C defaults and payloads span the entire backing integer" {
        inline for (.{ u1, u8, u17, u32, u64, u128 }) |T| {
            const S = BitField(T, .{ .flags = .{ .type = T, .write = .w0c } });
            const max = std.math.maxInt(T);
            const top: T = @as(T, 1) << (@bitSizeOf(T) - 1);

            try testing.expectEqual(max, S.raw(S.init()));
            try testing.expectEqual(@as(T, 0), S.ackAll(S.from(max)));
            try testing.expectEqual(max, S.ackAll(S.from(0)));
            try testing.expectEqual(max & ~top, S.ackAll(S.from(top)));
        }

        const Bool = BitField(u1, .{ .flag = .{ .type = bool, .write = .w0c, .default = true } });

        try testing.expect(Bool.init().flag);
        try testing.expectEqual(@as(u1, 0), Bool.ackAll(Bool.from(1)));
        try testing.expectEqual(@as(u1, 1), Bool.ackAll(Bool.from(0)));
    }

    test "enum clear fields retain neutral defaults and bitwise acknowledgement" {
        const Flags = enum(u2) { single = 1, _ };
        const S = BitField(u8, .{
            .one = .{ .type = Flags, .write = .w1c },
            .zero = .{ .offset = 4, .type = Flags, .write = .w0c },
        });

        const initial = comptime S.init();

        try testing.expectEqual(@as(u8, 0x30), S.raw(initial));
        try testing.expectEqual(@as(u2, 0), @intFromEnum(initial.one));
        try testing.expectEqual(@as(u2, 3), @intFromEnum(initial.zero));
        try testing.expectEqual(@as(u8, 0x11), S.encode(.{ .one = .single, .zero = .single }));
        try testing.expectEqual(@as(u8, 0x11), S.ackAll(S.from(0x21)));
        try testing.expectEqual(@as(u8, 0x31), S.ack(S.from(0x21), .one));
        try testing.expectEqual(@as(u8, 0x10), S.ack(S.from(0x21), .zero));
    }

    test "trigger capabilities are independent of acknowledgement capabilities" {
        const Plain = BitField(u8, .{ .enabled = bool });
        const Trigger = BitField(u8, .{ .action = .{ .type = bool, .write = .trigger } });
        const Ack = BitField(u8, .{ .pending = .{ .type = bool, .write = .w1c } });
        const Both = BitField(u8, .{
            .action = .{ .type = bool, .write = .trigger },
            .pending = .{ .type = bool, .write = .w1c },
        });

        try testing.expect(!@hasDecl(Plain, "trigger"));
        try testing.expect(!@hasDecl(Plain, "TriggerField"));
        try testing.expect(!@hasDecl(Plain, "ack"));
        try testing.expectEqual(@as(u8, 1), Trigger.trigger(.action));
        try testing.expect(!@hasDecl(Trigger, "ack"));
        try testing.expect(!@hasDecl(Trigger, "AckField"));
        try testing.expectEqual(@as(u8, 1), Ack.ack(Ack.from(1), .pending));
        try testing.expect(!@hasDecl(Ack, "trigger"));
        try testing.expect(!@hasDecl(Ack, "TriggerField"));
        try testing.expectEqual(@as(u8, 1), Both.trigger(.action));
        try testing.expectEqual(@as(u8, 2), Both.ackAll(Both.from(3)));
    }

    test "trigger payloads contain selected action bits without defaults or readback" {
        const Control = BitField(u16, .{
            .enabled = .{ .type = bool, .default = true },
            .retrain = .{ .type = bool, .write = .trigger },
            .actions = .{ .offset = 8, .width = 3, .write = .trigger },
            .ready = .{ .offset = 12, .type = bool, .access = .ro },
        });
        const action: Control.TriggerField = .retrain;
        const selected = comptime Control.trigger(.{ .retrain, .actions });

        try testing.expectEqual(@as(u16, 1), Control.raw(Control.init()));
        try testing.expectEqual(@as(u16, 2), Control.trigger(action));
        try testing.expectEqual(@as(u16, 0x700), Control.trigger(.actions));
        try testing.expectEqual(@as(u16, 0x702), selected);
        try testing.expectEqual(@as(u16, 0), Control.trigger(.{}));
        try testing.expectEqual(@as(u16, 0x703), Control.masks.rw);
        try testing.expectEqual(@as(u16, 1), Control.masks.assign);
        try testing.expectEqual(@as(u16, 0x702), Control.masks.trigger);
        try testing.expectEqual(@as(u16, 0), Control.masks.clear);
        try testing.expectEqual(@as(u16, 0x203), Control.encode(.{ .retrain = true, .actions = 2 }));

        const observed = Control.from(0xffff);
        const updated = Control.replace(observed, .{ .enabled = false });
        try testing.expect(observed.retrain);
        try testing.expect(updated.retrain);
        try testing.expectEqual(@as(u16, 0xfffe), Control.raw(updated));
        try testing.expect(!Control.from(0).retrain);
    }

    test "acknowledgements exclude triggers and trigger payloads do not add W0C neutral bits" {
        const Control = BitField(u8, .{
            .enabled = bool,
            .retrain = .{ .type = bool, .write = .trigger },
            .done = .{ .type = bool, .write = .w1c },
            .quiet = .{ .type = bool, .write = .w0c },
        });

        try testing.expectEqual(@as(u8, 8), Control.raw(Control.init()));
        try testing.expectEqual(@as(u8, 2), Control.trigger(.retrain));
        try testing.expectEqual(@as(u8, 4), Control.ackAll(Control.from(0xff)));
        try testing.expectEqual(@as(u8, 12), Control.ack(Control.from(0xff), .done));
        try testing.expectEqual(@as(u8, 8), Control.ackAll(Control.from(0)));
        try testing.expectEqual(@as(u8, 0xfe), Control.raw(Control.replace(Control.from(0xff), .{ .enabled = false })));
    }

    test "typed trigger flags encode independent actions rather than command ordinals" {
        const Flags = enum(u2) { none = 0, first = 1, second = 2, both = 3 };
        const Control = BitField(u8, .{
            .actions = .{ .type = Flags, .write = .trigger, .default = .none },
            .enabled = bool,
        });

        try testing.expectEqual(@as(u8, 0), Control.raw(Control.init()));
        try testing.expectEqual(@as(u8, 3), Control.trigger(.actions));
        try testing.expectEqual(@as(u8, 2), Control.encode(.{ .actions = .second }));
        try testing.expectEqual(Flags.both, Control.from(3).actions);
        try testing.expectEqual(@as(u8, 0xfb), Control.raw(Control.replace(Control.from(0xff), .{ .enabled = false })));
    }

    test "packed words permit typed writes while replacement preserves protected bits" {
        const Mode = enum(u2) { disabled, polling, interrupt, _ };
        const Child = BitField(u8, .{
            .enabled = bool,
            .mode = Mode,
            .ready = .{ .type = bool, .access = .ro },
            .reserved = .{ .type = bool, .access = .reserved },
            .pending = .{ .type = bool, .write = .w1c },
            .action = .{ .type = bool, .write = .trigger },
            .quiet = .{ .type = bool, .write = .w0c },
        });
        const Parent = BitField(u16, .{
            .child = .{ .offset = 4, .type = Child },
            .ready = .{ .type = bool, .access = .ro },
            .reserved = .{ .type = bool, .access = .reserved },
            .enabled = bool,
        });

        var word: Parent.Word = Parent.from(0xffff);
        word.child = Child.from(0);
        word.child.enabled = true;
        word.child.mode = .polling;
        word.child.ready = true;
        word.child.reserved = true;
        word.ready = false;
        word.reserved = false;
        word.enabled = false;

        try testing.expectEqual(@as(usize, 16), @bitSizeOf(Parent.Word));
        try testing.expectEqual(@as(usize, 8), @bitSizeOf(Child.Word));
        try testing.expect(word.child.enabled);
        try testing.expectEqual(Mode.polling, word.child.mode);
        try testing.expect(word.child.ready);
        try testing.expect(word.child.reserved);
        try testing.expect(!word.ready);
        try testing.expect(!word.reserved);
        try testing.expectEqual(@as(u16, 0x81bf), Parent.raw(word));

        const snapshot = Parent.from(0xffff);
        const updated = Parent.replace(snapshot, .{ .child = word.child, .enabled = false });
        const protected = ~Parent.masks.assign;

        try testing.expectEqual(Parent.raw(snapshot) & protected, Parent.raw(updated) & protected);
        try testing.expect(updated.child.enabled);
        try testing.expectEqual(Mode.polling, updated.child.mode);
        try testing.expect(updated.child.pending);
        try testing.expect(updated.child.action);
        try testing.expect(updated.child.quiet);
        try testing.expect(updated.ready);
        try testing.expect(updated.reserved);
        try testing.expect(!updated.enabled);
        try testing.expectEqual(@as(u16, 0xffff), Parent.raw(snapshot));
    }

    test "nested words preserve inner types and explicit defaults" {
        const Mode = enum(u2) { disabled, polling, interrupt, _ };
        const Control = BitField(u8, .{
            .enabled = bool,
            .mode = .{ .type = Mode, .default = .polling },
            .reserved = .{ .offset = 5, .type = bool, .access = .reserved, .default = true },
        });
        const Device = BitField(u16, .{
            .prefix = u2,
            .control = .{ .offset = 4, .type = Control, .default = Control.init() },
            .channel = u3,
        });

        const initial = comptime Device.init();
        const control: Control.Word = initial.control;

        try testing.expectEqual(@as(u16, 0x220), Device.raw(initial));
        try testing.expectEqual(Mode.polling, control.mode);
        try testing.expectEqual(@as(u16, 0x0ff0), Device.mask(.control));

        const snapshot = Device.from(0xffff);
        const changed = Control.replace(snapshot.control, .{ .enabled = false, .mode = .interrupt });
        const updated = Device.replace(snapshot, .{ .control = changed });

        try testing.expectEqual(@as(u8, 0xfc), Control.raw(changed));
        try testing.expectEqual(@as(u16, 0xffcf), Device.raw(updated));
        try testing.expectEqual(@as(u3, 7), updated.channel);
        try testing.expectEqual(@as(u16, 0xffff), Device.raw(snapshot));

        const WithoutDefault = BitField(u16, .{ .control = Control });
        try testing.expectEqual(@as(u8, 0), Control.raw(WithoutDefault.init().control));
    }

    test "nested literals distinguish omitted groups from explicit child construction" {
        const Child = BitField(u8, .{
            .enabled = .{ .type = bool, .default = true },
            .done = .{ .type = u2, .write = .w1c },
            .quiet = .{ .offset = 4, .type = u2, .write = .w0c },
            .go = .{ .type = bool, .write = .trigger },
            .fixed = .{ .type = bool, .access = .reserved, .default = true },
        });
        const Parent = BitField(u16, .{ .child = .{ .offset = 3, .type = Child } });
        const Outer = BitField(u32, .{ .parent = .{ .offset = 5, .type = Parent } });
        const WithDefault = BitField(u16, .{
            .child = .{ .offset = 3, .type = Child, .default = Child.from(0xb0) },
        });

        const omitted: Parent.Word = .{};
        const explicit: Parent.Word = .{ .child = .{} };
        const partial: Parent.Word = .{ .child = .{ .enabled = false } };
        const outer: Outer.Word = .{};
        const supplied: WithDefault.Word = .{};
        const changed = Parent.replace(Parent.from(0xfe18), .{ .child = .{ .enabled = false } });

        try testing.expectEqual(@as(u16, 0x180), Parent.raw(omitted));
        try testing.expectEqual(Parent.raw(Parent.init()), Parent.raw(omitted));
        try testing.expectEqual(@as(u16, 0x588), Parent.raw(explicit));
        try testing.expectEqual(@as(u16, 0x580), Parent.raw(partial));
        try testing.expectEqual(@as(u32, 0x3000), Outer.raw(outer));
        try testing.expectEqual(@as(u16, 0x580), WithDefault.raw(supplied));
        try testing.expectEqual(@as(u16, 0xfe10), Parent.raw(changed));
        try testing.expectEqual(@as(u2, 1), changed.child.done);
        try testing.expectEqual(@as(u2, 0), changed.child.quiet);
        try testing.expect(changed.child.go);
    }

    test "nested defaults preserve neutral action bits without inheriting ordinary defaults" {
        const Child = BitField(u8, .{
            .enabled = .{ .type = bool, .default = true },
            .done = .{ .type = u2, .write = .w1c },
            .quiet = .{ .offset = 4, .type = u2, .write = .w0c },
            .action = .{ .type = bool, .write = .trigger },
            .reserved = .{ .type = bool, .access = .reserved, .default = true },
        });
        const Parent = BitField(u16, .{ .child = .{ .offset = 3, .type = Child } });
        const Outer = BitField(u32, .{ .parent = .{ .offset = 5, .type = Parent } });
        const Explicit = BitField(u16, .{
            .child = .{ .offset = 3, .type = Child, .default = Child.from(0xb1) },
        });

        const initial = comptime Parent.init();
        const outer = comptime Outer.init();

        try testing.expectEqual(@as(u8, 0xb1), Child.raw(Child.init()));
        try testing.expectEqual(@as(u16, 0x180), Parent.raw(initial));
        try testing.expectEqual(@as(u2, 3), initial.child.quiet);
        try testing.expectEqual(@as(u2, 0), initial.child.done);
        try testing.expect(!initial.child.action);
        try testing.expect(!initial.child.enabled);
        try testing.expect(!initial.child.reserved);
        try testing.expectEqual(@as(u32, 0x3000), Outer.raw(outer));
        try testing.expectEqual(@as(u16, 0x588), Explicit.raw(Explicit.init()));

        try testing.expectEqual(@as(u16, 0x230), Parent.encode(.{ .child = Child.from(0x46) }));
    }

    test "nested policy masks protect non-assignment bits from whole-child replacement" {
        const Child = BitField(u8, .{
            .enabled = bool,
            .ready = .{ .type = bool, .access = .ro },
            .done = .{ .type = bool, .write = .w1c },
            .quiet = .{ .type = bool, .write = .w0c },
            .reserved = .{ .offset = 5, .type = bool, .access = .reserved },
        });
        const Parent = BitField(u16, .{
            .child = .{ .offset = 4, .type = Child, .default = Child.init() },
            .other = .{ .offset = 12, .type = bool, .write = .w0c },
        });

        try testing.expectEqual(@as(u16, 0x10d0), Parent.masks.rw);
        try testing.expectEqual(@as(u16, 0x0020), Parent.masks.ro);
        try testing.expectEqual(@as(u16, 0x0200), Parent.masks.reserved);
        try testing.expectEqual(@as(u16, 0x0010), Parent.masks.assign);
        try testing.expectEqual(@as(u16, 0x0040), Parent.masks.w1c);
        try testing.expectEqual(@as(u16, 0x1080), Parent.masks.w0c);
        try testing.expectEqual(@as(u16, 0x12f0), Parent.masks.declared);
        try testing.expectEqual(@as(u16, 0xed0f), Parent.masks.unknown);
        try testing.expectEqual(@as(u16, 0x0ff0), Parent.mask(.child));
        try testing.expectEqual(@as(u16, 0x1080), Parent.raw(Parent.init()));
        try testing.expectEqual(@as(u16, 0xffef), Parent.raw(Parent.replace(Parent.from(0xffff), .{ .child = Child.from(0) })));

        for (0..256) |input| {
            const raw: u16 = (@as(u16, @intCast(input)) << 4) | 0xf00f;
            const word = Parent.from(raw);

            for ([_]u8{ 0, 0xff, 0x55, 0xaa }) |supplied| {
                const updated = Parent.replace(word, .{ .child = Child.from(supplied) });

                try testing.expectEqual((supplied & 1) != 0, updated.child.enabled);
                try testing.expectEqual(raw & 0xffef, Parent.raw(updated) & 0xffef);
                try testing.expectEqual(raw, Parent.raw(word));
            }
        }
    }

    test "nested named selectors compose offsets through multiple policy levels" {
        const Leaf = BitField(u4, .{
            .enabled = bool,
            .ready = .{ .type = bool, .access = .ro },
            .pending = .{ .type = bool, .write = .w1c },
            .quiet = .{ .type = bool, .write = .w0c },
        });
        const Middle = BitField(u8, .{
            .leaf = .{ .offset = 2, .type = Leaf, .default = Leaf.init() },
            .tail = bool,
        });
        const Parent = BitField(u32, .{
            .middle = .{ .offset = 8, .type = Middle, .default = Middle.init() },
            .outside = .{ .offset = 24, .type = bool, .write = .w0c },
        });

        const selected = comptime Parent.mask(.{ .middle = .{ .leaf = .{ .enabled, .pending } } });
        try testing.expectEqual(@as(u32, 0x1400), selected);
        try testing.expectEqual(@as(u32, 0x01004000), Parent.mask(.{ .{ .middle = .tail }, .outside }));
        try testing.expectEqual(@as(u32, 0x01002000), Parent.raw(Parent.init()));
        try testing.expectEqual(@as(u32, 0x0800), Parent.masks.ro);
        try testing.expectEqual(@as(u32, 0x4400), Parent.masks.assign);

        const word = Parent.from(0xffffffff);
        const payload = comptime Parent.ack(Parent.from(0xffffffff), .{ .middle = .{ .leaf = .pending } });
        try testing.expectEqual(@as(u32, 0x01003000), payload);
        try testing.expectEqual(@as(u32, 0x01001000), Parent.ack(word, .middle));
        try testing.expectEqual(@as(u32, 0x1000), Parent.ackAll(word));
        try testing.expectEqual(@as(u32, 0xffffbbff), Parent.raw(Parent.replace(word, .{ .middle = Middle.from(0) })));

        const WithoutDefault = BitField(u16, .{ .middle = Middle });
        try testing.expectEqual(@as(u16, 0x20), WithoutDefault.raw(WithoutDefault.init()));
    }

    test "nested acknowledgements retain W0C neutral bits across sibling groups" {
        const Child = BitField(u4, .{
            .one = .{ .type = u2, .write = .w1c },
            .zero = .{ .type = u2, .write = .w0c },
        });
        const Parent = BitField(u16, .{
            .group = .{ .offset = 4, .type = Child },
            .other = .{ .offset = 12, .type = bool, .write = .w0c },
        });
        const selections = .{
            .{ .group = .one },
            .{ .group = .zero },
            .{ .group = .{ .one, .zero } },
            .group,
            .{ .group, .other },
            .{},
        };

        inline for (selections) |selection| {
            const selected = comptime Parent.mask(selection) & Parent.masks.clear;

            for (0..32) |input| {
                const snapshot: u16 = (@as(u16, @intCast(input & 0xf)) << 4) |
                    (@as(u16, @intCast(input >> 4)) << 12);
                const payload = Parent.ack(Parent.from(snapshot), selection);
                const current = snapshot | Parent.masks.clear;
                const cleared_one = (current & Parent.masks.w1c) & ~payload;
                const cleared_zero = (current & Parent.masks.w0c) & payload;
                const expected = (current & Parent.masks.clear) & ~(snapshot & selected);

                try testing.expectEqual(expected, cleared_one | cleared_zero);
                try testing.expectEqual(@as(u16, 0), payload & ~Parent.masks.clear);
            }
        }

        try testing.expectEqual(@as(u16, 0x1030), Parent.ack(Parent.from(0xffff), .group));
        try testing.expectEqual(@as(u16, 0x0030), Parent.ackAll(Parent.from(0xffff)));
        const OnlyNested = BitField(u8, .{ .group = Child });
        try testing.expectEqual(@as(u8, 0x03), OnlyNested.ackAll(OnlyNested.from(0xff)));
    }

    test "nested read-only reserved and empty groups retain distinct visibility" {
        const ReadOnly = BitField(u4, .{
            .ready = .{ .type = bool, .access = .ro },
            .reserved = .{ .type = bool, .access = .reserved, .default = true },
        });
        const Reserved = BitField(u4, .{
            .reserved = .{ .offset = 2, .type = bool, .access = .reserved, .default = true },
        });
        const Empty = BitField(u2, .{});
        const Parent = BitField(u16, .{
            .status = .{ .type = ReadOnly, .default = ReadOnly.init() },
            .reserved = .{ .type = Reserved, .default = Reserved.init() },
            .empty = Empty,
        });

        try testing.expectEqual(@as(u16, 0x42), Parent.encode(.{}));
        try testing.expectEqual(@as(u16, 0), Parent.masks.assign);
        try testing.expectEqual(@as(u16, 1), Parent.masks.readable);
        try testing.expectEqual(@as(u16, 0x42), Parent.masks.reserved);
        try testing.expectEqual(@as(u16, 0x43), Parent.masks.declared);
        try testing.expectEqual(@as(u16, 0xffbc), Parent.masks.unknown);
        try testing.expectEqual(@as(u16, 0x40), Parent.mask(.{ .reserved = .reserved }));
        try testing.expectEqual(@as(u16, 0x300), Parent.mask(.empty));
        try testing.expectEqual(@as(u16, 0), Parent.mask(.{ .empty = .{} }));
        try testing.expect(Parent.from(0xffff).status.ready);
        try testing.expectEqual(@as(u16, 0xffff), Parent.raw(Parent.replace(Parent.from(0xffff), .{})));
        try testing.expect(!@hasDecl(Parent, "ack"));
    }

    test "nested policies retain the highest bit across backing widths" {
        inline for (.{ u1, u8, u17, u32, u64, u128 }) |T| {
            const Child = BitField(T, .{
                .pending = .{ .offset = @bitSizeOf(T) - 1, .type = bool, .write = .w0c },
            });
            const Parent = BitField(T, .{ .child = Child });
            const top: T = @as(T, 1) << (@bitSizeOf(T) - 1);
            const max = std.math.maxInt(T);

            try testing.expectEqual(top, Parent.masks.w0c);
            try testing.expectEqual(max & ~top, Parent.masks.unknown);
            try testing.expectEqual(max, Parent.mask(.child));
            try testing.expectEqual(top, Parent.mask(.{ .child = .pending }));
            try testing.expectEqual(@as(T, 0), Parent.ack(Parent.from(max), .child));
            try testing.expectEqual(top, Parent.ack(Parent.from(0), .{ .child = .pending }));
        }
    }

    test "nested triggers inherit masks selectors and replacement protection" {
        const Leaf = BitField(u8, .{
            .enabled = bool,
            .retrain = .{ .type = bool, .write = .trigger },
            .ready = .{ .type = bool, .access = .ro },
            .done = .{ .type = bool, .write = .w1c },
            .quiet = .{ .type = bool, .write = .w0c },
            .reserved = .{ .offset = 6, .type = bool, .access = .reserved },
        });

        const Middle = BitField(u16, .{
            .leaf = .{ .offset = 4, .type = Leaf, .default = Leaf.init() },
            .flush = .{ .offset = 12, .type = bool, .write = .trigger },
        });

        const Parent = BitField(u32, .{
            .middle = .{ .offset = 8, .type = Middle, .default = Middle.init() },
            .outside = .{ .offset = 28, .type = bool, .write = .w0c },
        });

        const selected = comptime Parent.trigger(.{ .middle = .{ .leaf = .retrain } });
        const combined = comptime Parent.trigger(.{ .middle = .{ .flush, .{ .leaf = .retrain } } });
        try testing.expectEqual(@as(u32, 0x2000), selected);
        try testing.expectEqual(@as(u32, 0x00102000), combined);
        try testing.expectEqual(@as(u32, 0x00102000), Parent.trigger(.middle));
        try testing.expectEqual(@as(u32, 0x00102000), Parent.masks.trigger);
        try testing.expectEqual(@as(u32, 0x10018000), Parent.masks.clear);
        try testing.expectEqual(@as(u32, 0x1000), Parent.masks.assign);
        try testing.expectEqual(@as(u32, 0x10010000), Parent.raw(Parent.init()));

        const observed = Parent.from(0xffffffff);
        const updated = Parent.replace(observed, .{ .middle = Middle.from(0) });
        try testing.expectEqual(@as(u32, 0xffffefff), Parent.raw(updated));
        try testing.expectEqual(@as(u32, 0x8000), Parent.ackAll(observed));
        try testing.expectEqual(@as(u32, 0x10018000), Parent.ack(observed, .{ .middle = .{ .leaf = .done } }));
    }

    test "trigger masks span high bits and remain available through trigger-only groups" {
        inline for (.{ u1, u8, u17, u32, u64, u128 }) |T| {
            const Child = BitField(T, .{
                .action = .{ .offset = @bitSizeOf(T) - 1, .type = bool, .write = .trigger, .default = false },
            });

            const Parent = BitField(T, .{ .child = Child });

            const top: T = @as(T, 1) << (@bitSizeOf(T) - 1);
            const max = std.math.maxInt(T);

            try testing.expectEqual(top, Child.trigger(.action));
            try testing.expectEqual(top, Parent.masks.trigger);
            try testing.expectEqual(top, Parent.trigger(.child));
            try testing.expectEqual(top, Parent.trigger(.{ .child = .action }));
            try testing.expectEqual(@as(T, 0), Parent.raw(Parent.init()));
            try testing.expectEqual(max, Parent.raw(Parent.replace(Parent.from(max), .{})));
            try testing.expect(!@hasDecl(Parent, "ack"));
        }
    }
};
