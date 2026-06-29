//! Page-sized address helpers. See docs/specs/addr/pages.md.

const std = @import("std");

const bits = @import("../bits.zig");

pub const _4kib = 4 * 1024;
pub const _16kib = 16 * 1024;
pub const _64kib = 64 * 1024;
pub const _2mib = 2 * 1024 * 1024;
pub const _1gib = 1024 * 1024 * 1024;

fn requireAddress(comptime Addr: type) void {
    if (!@hasDecl(Addr, "Raw")) @compileError("Page requires an Address-compatible type with Raw");
    if (!@hasDecl(Addr, "fromInt")) @compileError("Page requires an Address-compatible type with fromInt");
    if (!@hasDecl(Addr, "raw")) @compileError("Page requires an Address-compatible type with raw");
    const info = @typeInfo(Addr.Raw);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("Page requires Address.Raw to be an unsigned integer type");
    }
    const zero: Addr = Addr.fromInt(0);
    const raw_value: Addr.Raw = zero.raw();
    _ = raw_value;
}

pub fn Page(comptime Addr: type, comptime page_size: Addr.Raw) type {
    comptime {
        requireAddress(Addr);
        if (page_size == 0) @compileError("Page page_size must be non-zero");
        if (!bits.isPowerOfTwo(Addr.Raw, page_size)) @compileError("Page page_size must be a power of two");
    }

    return struct {
        pub const Address = Addr;
        pub const AddressInt = Addr.Raw;
        pub const Error = error{ Misaligned, Overflow, OutOfBounds };

        pub const Size = struct {
            pub const bytes: AddressInt = page_size;
            pub const mask: AddressInt = page_size - 1;
            pub const shift: comptime_int = @ctz(page_size);
        };

        pub const Count = enum(AddressInt) {
            _,

            const This = @This();

            pub fn fromPages(value: AddressInt) This {
                return @enumFromInt(value);
            }

            pub fn pages(self: This) AddressInt {
                return @intFromEnum(self);
            }

            pub fn zero() This {
                return fromPages(0);
            }

            pub fn max() This {
                return fromPages(std.math.maxInt(AddressInt));
            }

            pub fn fromBytesExact(bytes: AddressInt) Error!This {
                if ((bytes & Size.mask) != 0) return error.Misaligned;
                return fromPages(bytes >> Size.shift);
            }

            pub fn fromBytesRoundUp(bytes: AddressInt) Error!This {
                if (bytes == 0) return zero();
                const rounded = std.math.add(AddressInt, bytes, Size.mask) catch return error.Overflow;
                return fromPages(rounded >> Size.shift);
            }

            pub fn toBytes(self: This) Error!AddressInt {
                return std.math.mul(AddressInt, self.pages(), Size.bytes) catch return error.Overflow;
            }
        };

        pub const Frame = enum(AddressInt) {
            _,

            const This = @This();

            pub fn fromAddress(addr_value: Addr) Error!This {
                if (!isAlignedAddress(addr_value)) return error.Misaligned;
                return @enumFromInt(addr_value.raw());
            }

            pub fn fromAddressInt(value: AddressInt) Error!This {
                return fromAddress(Addr.fromInt(value));
            }

            pub fn address(self: This) Addr {
                return Addr.fromInt(self.addressInt());
            }

            pub fn addressInt(self: This) AddressInt {
                return @intFromEnum(self);
            }

            pub fn index(self: This) AddressInt {
                return self.addressInt() >> Size.shift;
            }

            pub fn isValid(self: This) bool {
                return (self.addressInt() & Size.mask) == 0;
            }

            pub fn assertValid(self: This) void {
                std.debug.assert(self.isValid());
            }

            pub fn isAlignedAddress(addr_value: Addr) bool {
                return (addr_value.raw() & Size.mask) == 0;
            }

            pub fn containingAddress(addr_value: Addr) Error!This {
                return fromAddressInt(addr_value.raw() & ~Size.mask);
            }

            pub fn nextAlignedAddress(addr_value: Addr) Error!This {
                if (isAlignedAddress(addr_value)) return fromAddress(addr_value);
                const added = std.math.add(AddressInt, addr_value.raw(), Size.mask) catch return error.Overflow;
                return fromAddressInt(added & ~Size.mask);
            }

            pub fn add(self: This, count: Count) Error!This {
                const bytes = try count.toBytes();
                const value = std.math.add(AddressInt, self.addressInt(), bytes) catch return error.Overflow;
                return fromAddressInt(value);
            }

            pub fn sub(self: This, count: Count) Error!This {
                const bytes = try count.toBytes();
                const value = std.math.sub(AddressInt, self.addressInt(), bytes) catch return error.Overflow;
                return fromAddressInt(value);
            }
        };

        pub const FrameRange = struct {
            base: Frame,
            count: Count,

            const This = @This();

            pub fn fromBaseCount(base: Frame, count: Count) Error!This {
                _ = try base.add(count);
                return .{ .base = base, .count = count };
            }

            pub fn fromAddressBytes(base: Addr, bytes: AddressInt) Error!This {
                const frame = try Frame.fromAddress(base);
                const count = try Count.fromBytesExact(bytes);
                return fromBaseCount(frame, count);
            }

            pub fn fromAddressByteSpan(start: Addr, byte_len: AddressInt) Error!This {
                const base = try Frame.containingAddress(start);
                const raw_end = std.math.add(AddressInt, start.raw(), byte_len) catch return error.Overflow;
                const end_frame = try Frame.nextAlignedAddress(Addr.fromInt(raw_end));
                const bytes = std.math.sub(AddressInt, end_frame.addressInt(), base.addressInt()) catch unreachable;
                return fromBaseCount(base, try Count.fromBytesExact(bytes));
            }

            pub fn empty(at: Frame) This {
                return .{ .base = at, .count = Count.zero() };
            }

            pub fn isValid(self: This) bool {
                if (!self.base.isValid()) return false;
                _ = self.base.add(self.count) catch return false;
                return true;
            }

            pub fn assertValid(self: This) void {
                std.debug.assert(self.isValid());
            }

            pub fn isEmpty(self: This) bool {
                return self.count.pages() == 0;
            }

            pub fn byteLen(self: This) AddressInt {
                self.assertValid();
                return self.count.toBytes() catch unreachable;
            }

            pub fn end(self: This) Frame {
                self.assertValid();
                return self.base.add(self.count) catch unreachable;
            }

            pub fn containsFrame(self: This, frame: Frame) bool {
                self.assertValid();
                return self.base.addressInt() <= frame.addressInt() and frame.addressInt() < self.end().addressInt();
            }

            pub fn containsAddress(self: This, address: Addr) bool {
                self.assertValid();
                return self.base.addressInt() <= address.raw() and address.raw() < self.end().addressInt();
            }

            pub fn containsFrameRange(self: This, other: This) bool {
                self.assertValid();
                other.assertValid();
                const self_start = self.base.addressInt();
                const self_end = self.end().addressInt();
                const other_start = other.base.addressInt();
                const other_end = other.end().addressInt();
                return self_start <= other_start and other_end <= self_end;
            }

            pub fn overlaps(self: This, other: This) bool {
                self.assertValid();
                other.assertValid();
                if (self.isEmpty() or other.isEmpty()) return false;
                return self.base.addressInt() < other.end().addressInt() and other.base.addressInt() < self.end().addressInt();
            }

            pub fn isAdjacent(self: This, other: This) bool {
                self.assertValid();
                other.assertValid();
                return self.end().addressInt() == other.base.addressInt() or other.end().addressInt() == self.base.addressInt();
            }

            pub fn intersection(self: This, other: This) ?This {
                if (!self.overlaps(other)) return null;
                const start = @max(self.base.addressInt(), other.base.addressInt());
                const finish = @min(self.end().addressInt(), other.end().addressInt());
                const count = Count.fromBytesExact(finish - start) catch unreachable;
                return fromBaseCount(Frame.fromAddressInt(start) catch unreachable, count) catch unreachable;
            }

            pub fn span(self: This, other: This) This {
                self.assertValid();
                other.assertValid();
                const start = @min(self.base.addressInt(), other.base.addressInt());
                const finish = @max(self.end().addressInt(), other.end().addressInt());
                const count = Count.fromBytesExact(finish - start) catch unreachable;
                return fromBaseCount(Frame.fromAddressInt(start) catch unreachable, count) catch unreachable;
            }

            pub fn splitAt(self: This, at: Frame) Error!struct { left: This, right: This } {
                self.assertValid();
                at.assertValid();
                const start = self.base.addressInt();
                const finish = self.end().addressInt();
                const point = at.addressInt();
                if (point < start or point > finish) return error.OutOfBounds;
                const left_count = try Count.fromBytesExact(point - start);
                const right_count = try Count.fromBytesExact(finish - point);
                return .{
                    .left = try fromBaseCount(self.base, left_count),
                    .right = try fromBaseCount(at, right_count),
                };
            }
        };
    };
}
