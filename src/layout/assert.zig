const std = @import("std");

/// Checks optional size, alignment, and field offsets, all in bytes, at compile time.
/// Null values are not checked.
pub fn assertLayout(comptime T: type, comptime expected: Spec(T)) void {
    comptime Impl.check(T, expected);
}

fn Spec(comptime T: type) type {
    return struct {
        size: ?usize = null,
        alignment: ?usize = null,
        offsets: Fields(T) = .{},
    };
}

fn Fields(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .@"struct" => std.enums.EnumFieldStruct(std.meta.FieldEnum(T), ?usize, @as(?usize, null)),
        else => struct {},
    };
}

const Impl = struct {
    fn check(comptime T: type, comptime expected: Spec(T)) void {
        if (expected.size) |size| {
            equal(T, "size", size, @sizeOf(T));
        }

        if (expected.alignment) |alignment| {
            equal(T, "alignment", alignment, @alignOf(T));
        }

        inline for (@typeInfo(Fields(T)).@"struct".field_names) |field| {
            if (@field(expected.offsets, field)) |offset| {
                const actual = @offsetOf(T, field);
                if (offset != actual) {
                    @compileError(std.fmt.comptimePrint("{s}.{s}: expected byte offset {d}, found {d}", .{
                        @typeName(T), field, offset, actual,
                    }));
                }
            }
        }
    }

    fn equal(comptime T: type, comptime property: []const u8, comptime expected: usize, comptime actual: usize) void {
        if (expected != actual) {
            @compileError(std.fmt.comptimePrint("{s}: expected {s} {d}, found {d}", .{
                @typeName(T), property, expected, actual,
            }));
        }
    }
};
