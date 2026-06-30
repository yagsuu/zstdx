//! Spec: docs/specs/tags/tag-allocator.md.

const std = @import("std");

fn requireUnsignedInt(comptime Int: type) void {
    const info = @typeInfo(Int);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("Tag Int parameter must be an unsigned integer (u1..u64)");
    }
    if (info.int.bits == 0 or info.int.bits > 64) {
        @compileError("Tag Int parameter must have width u1 through u64");
    }
}

/// Strong-typed tag value for the `(Domain, Int)` pair. `Domain` is a
/// phantom-type identity; `Int` must be unsigned (u1..u64). Distinct
/// `Domain` types yield distinct `Tag` types even when `Int` matches.
pub fn Tag(comptime DomainT: type, comptime IntT: type) type {
    comptime requireUnsignedInt(IntT);
    return enum(IntT) {
        _,

        const Self = @This();

        pub const Domain = DomainT;
        pub const Int = IntT;

        /// Build a tag from its raw integer value. Every `IntT` value is a
        /// representable tag; allocator membership is a separate concern.
        pub fn fromInt(value: IntT) Self {
            return @enumFromInt(value);
        }

        /// Underlying integer value of the tag.
        pub fn raw(self: Self) IntT {
            return @intFromEnum(self);
        }
    };
}
