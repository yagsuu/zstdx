//! Page-sized address helpers. See `docs/specs/addr/pages.md`.

const std = @import("std");

const InclusiveRange = @import("ranges").InclusiveRange;

pub const _4kib = 4 * 1024;
pub const _16kib = 16 * 1024;
pub const _64kib = 64 * 1024;
pub const _2mib = 2 * 1024 * 1024;
pub const _1gib = 1024 * 1024 * 1024;

pub fn Page(comptime Addr: type, comptime page_size: Addr.Int) type {
    comptime {
        requireAddress(Addr);

        if (page_size < 2) {
            @compileError("Page size must be at least two bytes");
        }

        if (!std.math.isPowerOfTwo(page_size)) {
            @compileError("Page size must be a power of two");
        }
    }

    return struct {
        pub const Address = Addr;
        pub const Int = Addr.Int;

        pub const size: Int = page_size;
        pub const mask: Int = size - 1;
        pub const shift: comptime_int = @ctz(size);

        pub const Error = error{ Misaligned, Overflow, OutOfBounds };

        pub fn chunks(start: Addr, len: Int) error{Overflow}!Chunks {
            if (len != 0 and len - 1 > std.math.maxInt(Int) - start.raw()) {
                return error.Overflow;
            }
            return .{ .next_address = start, .remaining = len };
        }

        pub fn chunksSlice(slice: anytype) error{Overflow}!Chunks {
            const extent = sliceExtent(slice) orelse return error.Overflow;
            return chunks(extent.start, extent.len);
        }

        pub const Base = enum(Int) {
            _,

            const Self = @This();

            pub fn from(address: Addr) Error!Self {
                if (!isAligned(address)) {
                    return error.Misaligned;
                }
                return @fromBackingInt(address.raw());
            }

            pub fn fromInt(value: Int) Error!Self {
                return from(Addr.from(value));
            }

            pub fn alignDown(address: Addr) Self {
                return @fromBackingInt(address.raw() & ~mask);
            }

            pub fn alignUp(address: Addr) Error!Self {
                const added = std.math.add(Int, address.raw(), mask) catch return error.Overflow;
                return @fromBackingInt(added & ~mask);
            }

            pub fn addr(self: Self) Addr {
                return Addr.from(self.raw());
            }

            pub fn raw(self: Self) Int {
                return @backingInt(self);
            }

            pub fn index(self: Self) Int {
                return self.raw() >> shift;
            }

            pub fn isValid(self: Self) bool {
                return (self.raw() & mask) == 0;
            }

            pub fn isAligned(address: Addr) bool {
                return (address.raw() & mask) == 0;
            }

            pub fn contains(self: Self, address: Addr) bool {
                self.assertValid();
                return (address.raw() & ~mask) == self.raw();
            }

            pub fn containsExtent(self: Self, start: Addr, len: Int) bool {
                self.assertValid();
                if (len == 0) {
                    return true;
                }

                const offset = std.math.sub(Int, start.raw(), self.raw()) catch return false;
                return offset <= mask and len - 1 <= mask - offset;
            }

            pub fn containsSlice(self: Self, slice: anytype) bool {
                self.assertValid();
                const extent = sliceExtent(slice) orelse return false;
                return self.containsExtent(extent.start, extent.len);
            }

            pub fn add(self: Self, count: Count) Error!Self {
                const bytes = try count.bytes();
                const value = std.math.add(Int, self.raw(), bytes) catch return error.Overflow;
                return fromInt(value);
            }

            pub fn sub(self: Self, count: Count) Error!Self {
                const bytes = try count.bytes();
                const value = std.math.sub(Int, self.raw(), bytes) catch return error.Overflow;
                return fromInt(value);
            }

            pub fn assertValid(self: Self) void {
                std.debug.assert(self.isValid());
            }
        };

        pub const Count = enum(Int) {
            _,

            const Self = @This();

            pub fn from(value: Int) Self {
                return @fromBackingInt(value);
            }

            pub fn fromBytes(value: Int) Error!Self {
                if ((value & mask) != 0) {
                    return error.Misaligned;
                }
                return from(value >> shift);
            }

            pub fn fromBytesCeil(value: Int) Self {
                const whole = value >> shift;
                const partial = @intFromBool((value & mask) != 0);
                return from(whole + partial);
            }

            pub fn zero() Self {
                return from(0);
            }

            pub fn max() Self {
                return from(std.math.maxInt(Int));
            }

            pub fn raw(self: Self) Int {
                return @backingInt(self);
            }

            pub fn bytes(self: Self) Error!Int {
                return std.math.mul(Int, self.raw(), size) catch return error.Overflow;
            }
        };

        pub const Range = struct {
            bounds: RangeType,

            const Self = @This();
            const RangeType = InclusiveRange(Int);

            pub fn init(first_page: Base, last_page: Base) Error!Self {
                if (!first_page.isValid() or !last_page.isValid()) {
                    return error.Misaligned;
                }

                const bounds = RangeType.init(first_page.index(), last_page.index()) catch
                    return error.OutOfBounds;

                return .{ .bounds = bounds };
            }

            pub fn fromCount(base: Base, page_count: Count) Error!?Self {
                if (!base.isValid()) {
                    return error.Misaligned;
                }

                if (page_count.raw() == 0) {
                    return null;
                }

                const last_page = try base.add(Count.from(page_count.raw() - 1));
                return try init(base, last_page);
            }

            pub fn fromBytes(base: Addr, len: Int) Error!?Self {
                return fromCount(try Base.from(base), try Count.fromBytes(len));
            }

            pub fn containing(start: Addr, len: Int) Error!?Self {
                if (len == 0) {
                    return null;
                }

                const last_byte = std.math.add(Int, start.raw(), len - 1) catch
                    return error.Overflow;

                return try init(
                    Base.alignDown(start),
                    Base.alignDown(Addr.from(last_byte)),
                );
            }

            pub fn first(self: Self) Base {
                self.assertValid();
                return @fromBackingInt(self.bounds.start << shift);
            }

            pub fn last(self: Self) Base {
                self.assertValid();
                return @fromBackingInt(self.bounds.end << shift);
            }

            pub fn count(self: Self) Count {
                self.assertValid();
                return Count.from(self.bounds.end - self.bounds.start + 1);
            }

            pub fn bytes(self: Self) error{Overflow}!Int {
                return std.math.mul(Int, self.count().raw(), size) catch error.Overflow;
            }

            pub fn isValid(self: Self) bool {
                return self.bounds.isValid() and self.bounds.end <= (std.math.maxInt(Int) >> shift);
            }

            pub fn contains(self: Self, address: Addr) bool {
                self.assertValid();
                return self.bounds.contains(address.raw() >> shift);
            }

            pub fn containsExtent(self: Self, start: Addr, len: Int) bool {
                self.assertValid();

                if (len == 0) {
                    return true;
                }

                if (!self.contains(start)) {
                    return false;
                }

                const last_byte = (self.bounds.end << shift) | mask;
                return len - 1 <= last_byte - start.raw();
            }

            pub fn containsSlice(self: Self, slice: anytype) bool {
                self.assertValid();
                const extent = sliceExtent(slice) orelse return false;
                return self.containsExtent(extent.start, extent.len);
            }

            pub fn containsRange(self: Self, other: Self) bool {
                self.assertValid();
                other.assertValid();
                return self.bounds.containsRange(other.bounds);
            }

            pub fn overlaps(self: Self, other: Self) bool {
                self.assertValid();
                other.assertValid();
                return self.bounds.overlaps(other.bounds);
            }

            pub fn adjacent(self: Self, other: Self) bool {
                self.assertValid();
                other.assertValid();
                return self.bounds.adjacent(other.bounds);
            }

            pub fn intersection(self: Self, other: Self) ?Self {
                self.assertValid();
                other.assertValid();
                const bounds = self.bounds.intersection(other.bounds) orelse return null;
                return .{ .bounds = bounds };
            }

            pub fn span(self: Self, other: Self) Self {
                self.assertValid();
                other.assertValid();
                return .{ .bounds = self.bounds.span(other.bounds) };
            }

            pub fn splitAt(self: Self, at: Base) Error!struct { left: ?Self, right: ?Self } {
                self.assertValid();

                if (!at.isValid()) {
                    return error.Misaligned;
                }

                const point = at.index();
                if (point < self.bounds.start or point > self.bounds.end + 1) {
                    return error.OutOfBounds;
                }

                return .{
                    .left = if (point == self.bounds.start) null else .{
                        .bounds = .{ .start = self.bounds.start, .end = point - 1 },
                    },
                    .right = if (point > self.bounds.end) null else .{
                        .bounds = .{ .start = point, .end = self.bounds.end },
                    },
                };
            }

            pub fn assertValid(self: Self) void {
                std.debug.assert(self.isValid());
            }
        };

        pub const Chunk = struct {
            page: Base,
            offset: Int,
            len: Int,
        };

        pub const Chunks = struct {
            next_address: Addr,
            remaining: Int,

            const Self = @This();

            pub fn next(self: *Self) ?Chunk {
                if (self.remaining == 0) {
                    return null;
                }

                const start = self.next_address;
                const offset = start.raw() & mask;
                const len = @min(self.remaining, size - offset);

                self.remaining -= len;

                if (self.remaining != 0) {
                    self.next_address = Addr.from(start.raw() + len);
                }

                return .{
                    .page = Base.alignDown(start),
                    .offset = offset,
                    .len = len,
                };
            }
        };

        fn sliceExtent(slice: anytype) ?struct { start: Addr, len: Int } {
            const Element = switch (@typeInfo(@TypeOf(slice))) {
                .pointer => |pointer| if (pointer.size == .slice)
                    pointer.child
                else
                    @compileError("Expected a slice"),
                else => @compileError("Expected a slice"),
            };

            const start = std.math.cast(Int, @intFromPtr(slice.ptr)) orelse return null;
            const len = std.math.mul(usize, slice.len, @sizeOf(Element)) catch return null;

            return .{
                .start = Addr.from(start),
                .len = std.math.cast(Int, len) orelse return null,
            };
        }
    };
}

fn requireAddress(comptime Addr: type) void {
    if (!@hasDecl(Addr, "Int")) {
        @compileError("Page requires an Address-compatible type with Int");
    }

    if (!@hasDecl(Addr, "from")) {
        @compileError("Page requires an Address-compatible type with from");
    }

    if (!@hasDecl(Addr, "raw")) {
        @compileError("Page requires an Address-compatible type with raw");
    }

    const info = @typeInfo(Addr.Int);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("Page requires Address.Int to be an unsigned integer type");
    }

    const zero: Addr = Addr.from(0);
    const raw_value: Addr.Int = zero.raw();
    _ = raw_value;
}

pub const unit = struct {
    const testing = std.testing;
    const address = @import("address.zig");

    const A = address.Address(opaque {}, u8);
    const P = Page(A, 4);

    test "page families distinguish address domains and page sizes" {
        const Phys4K = Page(address.PhysAddr, _4kib);
        const Virt4K = Page(address.VirtAddr, _4kib);
        const Phys2M = Page(address.PhysAddr, _2mib);

        try testing.expect(Phys4K.Base != Virt4K.Base);
        try testing.expect(Phys4K.Base != Phys2M.Base);
    }

    test "page counts preserve checked byte rounding" {
        try testing.expectEqual(@as(u8, 2), (try P.Count.fromBytes(8)).raw());
        try testing.expectError(error.Misaligned, P.Count.fromBytes(5));
        try testing.expectEqual(@as(u8, 0), P.Count.fromBytesCeil(0).raw());
        try testing.expectEqual(@as(u8, 1), P.Count.fromBytesCeil(1).raw());
        try testing.expectEqual(@as(u8, 1), P.Count.fromBytesCeil(4).raw());
        try testing.expectEqual(@as(u8, 2), P.Count.fromBytesCeil(5).raw());
        try testing.expectEqual(@as(u8, 64), P.Count.fromBytesCeil(254).raw());
        try testing.expectEqual(@as(u8, 64), P.Count.fromBytesCeil(255).raw());
        try testing.expectEqual(@as(u8, 12), try P.Count.from(3).bytes());
        try testing.expectError(error.Overflow, P.Count.max().bytes());
    }

    test "page bases validate alignment and checked page arithmetic" {
        const frame = try P.Base.fromInt(8);
        const next = try frame.add(P.Count.from(2));
        const previous = try frame.sub(P.Count.from(1));

        frame.assertValid();
        try testing.expectEqual(@as(u8, 2), frame.index());
        try testing.expectEqual(@as(u8, 16), next.raw());
        try testing.expectEqual(@as(u8, 4), previous.raw());
        try testing.expectError(error.Misaligned, P.Base.fromInt(1));
        try testing.expectEqual(@as(u8, 8), P.Base.alignDown(A.from(11)).raw());
        try testing.expectEqual(@as(u8, 12), (try P.Base.alignUp(A.from(9))).raw());
        try testing.expectEqual(@as(u8, 252), (try P.Base.alignUp(A.from(252))).raw());
        try testing.expectError(error.Overflow, P.Base.alignUp(A.from(254)));
        try testing.expectError(error.Overflow, (try P.Base.fromInt(252)).add(P.Count.from(1)));
        try testing.expectError(error.Overflow, frame.sub(P.Count.from(3)));
        try testing.expectError(error.Misaligned, @as(P.Base, @fromBackingInt(1)).add(P.Count.zero()));
    }

    test "inclusive page ranges validate bounds and represent the final page" {
        const first = try P.Base.fromInt(8);
        const last = try P.Base.fromInt(16);
        const range = try P.Range.init(first, last);
        const from_bytes = (try P.Range.fromBytes(A.from(8), 8)).?;
        const covered = (try P.Range.containing(A.from(9), 4)).?;

        try testing.expectEqual(first, range.first());
        try testing.expectEqual(last, range.last());
        try testing.expectEqual(@as(u8, 3), range.count().raw());
        try testing.expectEqual(@as(u8, 12), try range.bytes());
        try testing.expectEqual(@as(u8, 2), from_bytes.count().raw());
        try testing.expectEqual(@as(u8, 8), covered.first().raw());
        try testing.expectEqual(@as(u8, 12), covered.last().raw());
        try testing.expectEqual(@as(?P.Range, null), try P.Range.fromBytes(A.from(8), 0));
        try testing.expectEqual(@as(?P.Range, null), try P.Range.containing(A.from(9), 0));
        try testing.expectEqual(@as(?P.Range, null), try P.Range.containing(A.from(255), 0));
        try testing.expectError(error.Misaligned, P.Range.fromBytes(A.from(9), 4));
        try testing.expectError(error.Misaligned, P.Range.fromBytes(A.from(8), 5));
        try testing.expectError(error.Misaligned, P.Range.init(@fromBackingInt(1), last));
        try testing.expectError(error.OutOfBounds, P.Range.init(last, first));

        const final_page = (try P.Range.fromBytes(A.from(252), 4)).?;
        try testing.expectEqual(@as(u8, 1), final_page.count().raw());
        try testing.expectEqual(@as(u8, 4), try final_page.bytes());
        try testing.expect(final_page.contains(A.from(255)));
        try testing.expectEqual(final_page, (try P.Range.containing(A.from(254), 2)).?);
        try testing.expectError(error.Overflow, P.Range.containing(A.from(254), 3));
        try testing.expectError(error.Overflow, P.Range.fromBytes(A.from(252), 8));
        try testing.expect(!(P.Range{ .bounds = .{ .start = 0, .end = 64 } }).isValid());
    }

    test "full address space has infallible page count and checked byte length" {
        const full = try P.Range.init(try P.Base.fromInt(0), try P.Base.fromInt(252));
        try testing.expectEqual(@as(u8, 64), full.count().raw());
        try testing.expectError(error.Overflow, full.bytes());
        try testing.expect(full.contains(A.from(0)));
        try testing.expect(full.contains(A.from(255)));
        try testing.expectEqual(full, (try P.Range.containing(A.from(1), 255)).?);

        const SmallPage = Page(address.Address(opaque {}, u64), 2);
        const wide = try SmallPage.Range.init(
            try SmallPage.Base.fromInt(0),
            try SmallPage.Base.fromInt(std.math.maxInt(u64) - 1),
        );
        try testing.expectEqual(@as(u64, 1) << 63, wide.count().raw());
        try testing.expectError(error.Overflow, wide.bytes());
    }

    test "inclusive operations preserve final-page membership and adjacency" {
        const left = (try P.Range.fromBytes(A.from(240), 8)).?;
        const right = (try P.Range.fromBytes(A.from(248), 8)).?;
        const middle = (try P.Range.fromBytes(A.from(244), 8)).?;
        const joined = left.span(right);

        try testing.expect(left.contains(left.first().addr()));
        try testing.expect(left.contains(left.last().addr()));
        try testing.expect(left.contains(A.from(247)));
        try testing.expect(!left.contains(A.from(248)));
        try testing.expect(right.contains(A.from(255)));
        try testing.expect(joined.containsRange(middle));
        try testing.expect(!left.overlaps(right));
        try testing.expect(left.adjacent(right));
        try testing.expectEqual(@as(?P.Range, null), left.intersection(right));
        try testing.expectEqual(@as(u8, 244), left.intersection(middle).?.first().raw());
        try testing.expectEqual(@as(u8, 244), left.intersection(middle).?.last().raw());
        try testing.expectEqual(@as(u8, 240), joined.first().raw());
        try testing.expectEqual(@as(u8, 252), joined.last().raw());
        try testing.expectEqual(@as(u8, 4), joined.count().raw());
    }

    test "splitting partitions pages without duplicating the split page" {
        const range = (try P.Range.fromBytes(A.from(8), 12)).?;
        const split = try range.splitAt(try P.Base.fromInt(12));
        const at_start = try range.splitAt(range.first());
        const after_last = try range.splitAt(try P.Base.fromInt(20));

        try testing.expectEqual(@as(u8, 1), split.left.?.count().raw());
        try testing.expectEqual(@as(u8, 2), split.right.?.count().raw());
        try testing.expect(split.left.?.adjacent(split.right.?));
        try testing.expect(!split.left.?.overlaps(split.right.?));
        try testing.expectEqual(@as(?P.Range, null), at_start.left);
        try testing.expectEqual(range, at_start.right.?);
        try testing.expectEqual(@as(?P.Range, null), after_last.right);
        try testing.expectEqual(range, after_last.left.?);
        try testing.expectError(error.OutOfBounds, range.splitAt(try P.Base.fromInt(4)));
        try testing.expectError(error.OutOfBounds, range.splitAt(try P.Base.fromInt(24)));

        const final = (try P.Range.fromBytes(A.from(248), 8)).?;
        const final_split = try final.splitAt(final.last());
        try testing.expectEqual(@as(u8, 1), final_split.left.?.count().raw());
        try testing.expectEqual(@as(u8, 1), final_split.right.?.count().raw());
        try testing.expect(final_split.right.?.contains(A.from(255)));
    }

    test "inclusive page ranges and full-space cardinality work at comptime" {
        comptime {
            const full = try P.Range.init(try P.Base.fromInt(0), try P.Base.fromInt(252));
            const split = try full.splitAt(try P.Base.fromInt(252));

            try testing.expectEqual(@as(u8, 64), full.count().raw());
            try testing.expectEqual(@as(u8, 63), split.left.?.count().raw());
            try testing.expectEqual(@as(u8, 1), split.right.?.count().raw());
            try testing.expectEqual(@as(u8, 252), split.right.?.last().raw());
        }
    }

    test "frame point and extent checks include every byte of the final page" {
        const frame = try P.Base.fromInt(252);
        const final_range = try P.Range.init(frame, frame);
        const full = try P.Range.init(try P.Base.fromInt(0), frame);

        try testing.expect(frame.contains(A.from(252)));
        try testing.expect(frame.contains(A.from(255)));
        try testing.expect(!frame.contains(A.from(251)));
        try testing.expect(frame.containsExtent(A.from(252), 4));
        try testing.expect(frame.containsExtent(A.from(255), 1));
        try testing.expect(!frame.containsExtent(A.from(255), 2));
        try testing.expect(!frame.containsExtent(A.from(251), 2));
        try testing.expect(frame.containsExtent(A.from(0), 0));
        try testing.expect(final_range.containsExtent(A.from(252), 4));
        try testing.expect(!final_range.containsExtent(A.from(253), 4));
        try testing.expect(final_range.containsExtent(A.from(0), 0));
        try testing.expect(full.containsExtent(A.from(1), 255));
        try testing.expect(!full.containsExtent(A.from(2), 255));
    }

    test "extents must fit wholly inside a frame or page range" {
        const frame = try P.Base.fromInt(8);
        const range = (try P.Range.fromCount(frame, P.Count.from(2))).?;

        try testing.expect(frame.containsExtent(A.from(9), 3));
        try testing.expect(!frame.containsExtent(A.from(9), 4));
        try testing.expect(!frame.containsExtent(A.from(7), 2));
        try testing.expect(range.containsExtent(A.from(9), 7));
        try testing.expect(!range.containsExtent(A.from(9), 8));
        try testing.expect(!range.containsExtent(A.from(7), 2));
        try testing.expect(!range.containsExtent(A.from(16), 1));
    }

    test "count construction accepts full-space extents without byte conversion" {
        const first_page = try P.Base.fromInt(0);
        const last_page = try P.Base.fromInt(252);
        const full = (try P.Range.fromCount(first_page, P.Count.from(64))).?;

        try testing.expectEqual(last_page, full.last());
        try testing.expectEqual(@as(u8, 64), full.count().raw());
        try testing.expectEqual(@as(?P.Range, null), try P.Range.fromCount(last_page, P.Count.zero()));
        try testing.expectEqual(last_page, (try P.Range.fromCount(last_page, P.Count.from(1))).?.last());
        try testing.expectError(error.Overflow, P.Range.fromCount(last_page, P.Count.from(2)));
        try testing.expectError(error.Misaligned, P.Range.fromCount(@fromBackingInt(1), P.Count.from(1)));
    }

    test "slice containment derives its address and measures elements in bytes" {
        const Frames = Page(address.PhysAddr, 128);
        var storage: [40]u32 align(128) = undefined;
        const all: []u32 = &storage;
        const prefix: []const u32 = all[0..32];
        const crossing: []u32 = all[31..33];
        const frame = Frames.Base.alignDown(address.PhysAddr.from(@intFromPtr(all.ptr)));
        const range = (try Frames.Range.fromCount(frame, Frames.Count.from(2))).?;

        try testing.expect(frame.containsSlice(prefix));
        try testing.expect(!frame.containsSlice(crossing));
        try testing.expect(!frame.containsSlice(all));
        try testing.expect(range.containsSlice(all));
        try testing.expect(range.containsSlice(crossing));
    }

    test "slice containment rejects unrepresentable addresses and byte lengths" {
        const frame = try P.Base.fromInt(252);
        const range = try P.Range.init(frame, frame);
        const pointer: [*]const u16 = @ptrFromInt(254);
        const final: []const u16 = pointer[0..1];
        const crossing: []const u16 = pointer[0..2];
        const outside_pointer: [*]const u8 = @ptrFromInt(256);
        const outside: []const u8 = outside_pointer[0..1];
        const long_pointer: [*]const u8 = @ptrFromInt(1);
        const long: []const u8 = long_pointer[0..256];
        const large_pointer: [*]const u64 = @ptrFromInt(8);
        const overflowing: []const u64 = large_pointer[0 .. std.math.maxInt(usize) / @sizeOf(u64) + 1];

        try testing.expect(frame.containsSlice(final));
        try testing.expect(range.containsSlice(final));
        try testing.expect(!frame.containsSlice(crossing));
        try testing.expect(!range.containsSlice(crossing));
        try testing.expect(!frame.containsSlice(outside));
        try testing.expect(!range.containsSlice(outside));
        try testing.expect(!frame.containsSlice(long));
        try testing.expect(!range.containsSlice(long));
        try testing.expect(!frame.containsSlice(overflowing));
        try testing.expect(!range.containsSlice(overflowing));
    }

    test "chunks split an unaligned extent into page-bounded byte segments" {
        var iterator = try P.chunks(A.from(9), 10);
        try testing.expectEqual(P.Chunk{ .page = try P.Base.fromInt(8), .offset = 1, .len = 3 }, iterator.next().?);
        try testing.expectEqual(P.Chunk{ .page = try P.Base.fromInt(12), .offset = 0, .len = 4 }, iterator.next().?);
        try testing.expectEqual(P.Chunk{ .page = try P.Base.fromInt(16), .offset = 0, .len = 3 }, iterator.next().?);
        try testing.expectEqual(@as(?P.Chunk, null), iterator.next());
        try testing.expectEqual(@as(?P.Chunk, null), iterator.next());
    }

    test "chunks stop at the final byte without advancing past it" {
        var iterator = try P.chunks(A.from(249), 7);
        try testing.expectEqual(P.Chunk{ .page = try P.Base.fromInt(248), .offset = 1, .len = 3 }, iterator.next().?);
        try testing.expectEqual(P.Chunk{ .page = try P.Base.fromInt(252), .offset = 0, .len = 4 }, iterator.next().?);
        try testing.expectEqual(@as(?P.Chunk, null), iterator.next());

        var final_byte = try P.chunks(A.from(255), 1);
        try testing.expectEqual(P.Chunk{ .page = try P.Base.fromInt(252), .offset = 3, .len = 1 }, final_byte.next().?);
        try testing.expectEqual(@as(?P.Chunk, null), final_byte.next());

        var empty = try P.chunks(A.from(255), 0);
        try testing.expectEqual(@as(?P.Chunk, null), empty.next());
        try testing.expectError(error.Overflow, P.chunks(A.from(255), 2));
        try testing.expectError(error.Overflow, P.chunks(A.from(249), 8));
    }

    test "slice chunks use pointer addresses and split in bytes rather than elements" {
        const Frames = Page(address.PhysAddr, 4096);
        var storage: [8192]u8 align(4096) = undefined;
        const slice: []u8 = storage[4090..4110];
        var iterator = try Frames.chunksSlice(slice);
        const first = iterator.next().?;
        const second = iterator.next().?;

        try testing.expectEqual(@intFromPtr(&storage), first.page.raw());
        try testing.expectEqual(@as(u64, 4090), first.offset);
        try testing.expectEqual(@as(u64, 6), first.len);
        try testing.expectEqual(@intFromPtr(&storage) + 4096, second.page.raw());
        try testing.expectEqual(@as(u64, 0), second.offset);
        try testing.expectEqual(@as(u64, 14), second.len);
        try testing.expectEqual(@as(?Frames.Chunk, null), iterator.next());

        const Small = Page(address.Address(opaque {}, u16), 4);
        const pointer: [*]align(1) const u32 = @ptrFromInt(258);
        const elements: []align(1) const u32 = pointer[0..2];
        var split_elements = try Small.chunksSlice(elements);
        try testing.expectEqual(Small.Chunk{ .page = try Small.Base.fromInt(256), .offset = 2, .len = 2 }, split_elements.next().?);
        try testing.expectEqual(Small.Chunk{ .page = try Small.Base.fromInt(260), .offset = 0, .len = 4 }, split_elements.next().?);
        try testing.expectEqual(Small.Chunk{ .page = try Small.Base.fromInt(264), .offset = 0, .len = 2 }, split_elements.next().?);
        try testing.expectEqual(@as(?Small.Chunk, null), split_elements.next());
        try testing.expectError(error.Overflow, P.chunksSlice(elements));
    }
};
