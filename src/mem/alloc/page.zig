//! page-range allocation over a unit-index backend

const std = @import("std");

const buddy = @import("algo").alloc.buddy;

pub const PageAllocator = struct {
    pub fn Static(comptime Backend: type, comptime Page: type, comptime origin: Page.Base) type {
        comptime {
            Impl.requireBackend(Backend);

            const backend = Backend.init();
            const count = std.math.cast(Page.Int, backend.capacity()) orelse {
                @compileError("PageAllocator.Static extent overflows page address space");
            };

            if (count != 0) {
                _ = origin.add(Page.Count.from(count - 1)) catch {
                    @compileError("PageAllocator.Static extent overflows page address space");
                };
            }
        }

        return struct {
            backend: Backend = Backend.init(),

            const Self = @This();

            pub const Allocation = Impl.Allocation(Page);
            pub const Error = Impl.Error;

            pub fn init() Self {
                return .{};
            }

            pub fn base(_: *const Self) Page.Base {
                return origin;
            }

            pub fn capacity(self: *const Self) Page.Int {
                return @intCast(self.backend.capacity());
            }

            pub fn remaining(self: *const Self) Page.Int {
                return @intCast(self.backend.remaining());
            }

            pub fn allocated(self: *const Self) Page.Int {
                return @intCast(self.backend.allocated());
            }

            pub fn largestFreeOrder(self: *const Self) ?u8 {
                return Impl.largestFreeOrder(Backend, &self.backend);
            }

            pub fn remainingBytes(self: *const Self) Error!Page.Int {
                return std.math.mul(Page.Int, self.remaining(), Page.size) catch error.Overflow;
            }

            pub fn hasFreeBlock(self: *const Self, range: Page.Range) bool {
                return Impl.hasFreeBlock(Backend, Page, &self.backend, origin, range);
            }

            pub fn alloc(self: *Self, order: u8) Error!Allocation {
                return Impl.alloc(Backend, Page, &self.backend, origin, order);
            }

            pub fn free(self: *Self, allocation: Allocation) Error!void {
                return Impl.free(Backend, Page, &self.backend, origin, allocation);
            }

            pub fn reserve(self: *Self, range: Page.Range) Error!void {
                return Impl.reserve(Backend, Page, &self.backend, origin, range);
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(Backend, Page, &self.backend, origin);
            }
        };
    }

    pub fn Bounded(comptime Backend: type, comptime Page: type) type {
        comptime {
            Impl.requireBackend(Backend);
        }

        return struct {
            backend: Backend,
            origin: Page.Base,

            const Self = @This();

            pub const Error = Impl.Error;
            pub const Allocation = Impl.Allocation(Page);

            pub fn init(backend: Backend, origin: Page.Base) Error!Self {
                const count = std.math.cast(Page.Int, backend.capacity()) orelse return error.Overflow;
                if (count != 0) {
                    _ = origin.add(Page.Count.from(count - 1)) catch return error.Overflow;
                }
                return .{ .backend = backend, .origin = origin };
            }

            pub fn base(self: *const Self) Page.Base {
                return self.origin;
            }

            pub fn capacity(self: *const Self) Page.Int {
                return @intCast(self.backend.capacity());
            }

            pub fn remaining(self: *const Self) Page.Int {
                return @intCast(self.backend.remaining());
            }

            pub fn allocated(self: *const Self) Page.Int {
                return @intCast(self.backend.allocated());
            }

            pub fn largestFreeOrder(self: *const Self) ?u8 {
                return Impl.largestFreeOrder(Backend, &self.backend);
            }

            pub fn remainingBytes(self: *const Self) Error!Page.Int {
                return std.math.mul(Page.Int, self.remaining(), Page.size) catch error.Overflow;
            }

            pub fn hasFreeBlock(self: *const Self, range: Page.Range) bool {
                return Impl.hasFreeBlock(Backend, Page, &self.backend, self.origin, range);
            }

            pub fn alloc(self: *Self, order: u8) Error!Allocation {
                return Impl.alloc(Backend, Page, &self.backend, self.origin, order);
            }

            pub fn free(self: *Self, allocation: Allocation) Error!void {
                return Impl.free(Backend, Page, &self.backend, self.origin, allocation);
            }

            pub fn reserve(self: *Self, range: Page.Range) Error!void {
                return Impl.reserve(Backend, Page, &self.backend, self.origin, range);
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(Backend, Page, &self.backend, self.origin);
            }
        };
    }
};

const Impl = struct {
    const Error = error{
        OutOfMemory,
        OutOfBounds,
        InvalidRequest,
        InvalidOrder,
        AlreadyAllocated,
        NotAllocated,
        Overflow,
    };

    fn Allocation(comptime Page: type) type {
        return struct {
            inner: Page.Range,

            const Self = @This();

            pub fn range(self: Self) Page.Range {
                return self.inner;
            }
        };
    }

    fn alloc(comptime Backend: type, comptime Page: type, backend: *Backend, base: Page.Base, order: u8) Error!Allocation(Page) {
        if (order >= backend.orderCount()) {
            return error.InvalidOrder;
        }

        const block = try backend.alloc(order);
        return .{ .inner = try rangeFromBlock(Backend, Page, base, block) };
    }

    fn free(comptime Backend: type, comptime Page: type, backend: *Backend, base: Page.Base, allocation: Allocation(Page)) Error!void {
        const block = try blockFromRange(Backend, Page, backend, base, allocation.inner);
        try backend.free(block);
    }

    fn reserve(comptime Backend: type, comptime Page: type, backend: *Backend, base: Page.Base, range: Page.Range) Error!void {
        if (!range.isValid()) {
            return error.InvalidRequest;
        }

        const base_index = base.raw() >> Page.shift;
        const start_index = range.first().raw() >> Page.shift;

        if (start_index < base_index) {
            return error.OutOfBounds;
        }

        const start = start_index - base_index;
        const count = range.count().raw();

        const end = std.math.add(Page.Int, start, count) catch return error.Overflow;
        if (end > backend.capacity()) {
            return error.OutOfBounds;
        }

        try backend.reserve(.{ .start = @intCast(start), .end = @intCast(end) });
    }

    fn hasFreeBlock(comptime Backend: type, comptime Page: type, backend: *const Backend, base: Page.Base, range: Page.Range) bool {
        const block = blockFromRange(Backend, Page, backend, base, range) catch return false;
        return backend.hasFreeBlock(block);
    }

    fn largestFreeOrder(comptime Backend: type, backend: *const Backend) ?u8 {
        if (backend.remaining() == 0) {
            return null;
        }

        var order = backend.maxOrder();
        while (true) : (order -%= 1) {
            const size = buddy.blockSize(order) catch {
                if (order == 0) {
                    return null;
                }
                continue;
            };

            var start: usize = 0;
            while (start + size <= backend.capacity()) : (start += size) {
                if (backend.hasFreeBlock(.{ .start = start, .order = order })) {
                    return order;
                }
            }

            if (order == 0) {
                return null;
            }
        }
    }

    fn isValid(comptime Backend: type, comptime Page: type, backend: *const Backend, base: Page.Base) bool {
        if (!backend.isValid() or !base.isValid()) {
            return false;
        }

        const capacity = std.math.cast(Page.Int, backend.capacity()) orelse return false;
        if (capacity != 0) {
            _ = base.add(Page.Count.from(capacity - 1)) catch return false;
        }
        return true;
    }

    fn rangeFromBlock(comptime Backend: type, comptime Page: type, base: Page.Base, block: Backend.Block) Error!Page.Range {
        const start = std.math.cast(Page.Int, block.start) orelse return error.Overflow;
        const size = buddy.blockSize(block.order) catch return error.Overflow;
        const count = std.math.cast(Page.Int, size) orelse return error.Overflow;
        const address = base.add(Page.Count.from(start)) catch return error.Overflow;
        return (Page.Range.fromCount(address, Page.Count.from(count)) catch return error.Overflow).?;
    }

    fn blockFromRange(comptime Backend: type, comptime Page: type, backend: *const Backend, base: Page.Base, range: Page.Range) Error!Backend.Block {
        if (!range.isValid()) {
            return error.InvalidRequest;
        }

        const count = range.count().raw();
        const order = buddy.orderForLen(@intCast(count)) catch return error.InvalidRequest;
        const size = buddy.blockSize(order) catch return error.InvalidRequest;

        if (size != count) {
            return error.InvalidRequest;
        }

        const base_index = base.raw() >> Page.shift;
        const start_index = range.first().raw() >> Page.shift;

        if (start_index < base_index) {
            return error.OutOfBounds;
        }

        const start = std.math.cast(usize, start_index - base_index) orelse return error.OutOfBounds;
        if (start % size != 0) {
            return error.InvalidRequest;
        }

        const end = std.math.add(usize, start, size) catch return error.Overflow;
        if (end > backend.capacity()) {
            return error.OutOfBounds;
        }

        return .{ .start = start, .order = order };
    }

    fn requireBackend(comptime Backend: type) void {
        inline for (.{
            "Block",     "Range",     "Error", "capacity", "orderCount", "maxOrder",
            "allocated", "remaining", "alloc", "free",     "reserve",    "hasFreeBlock",
            "isValid",
        }) |name| {
            if (!@hasDecl(Backend, name)) {
                @compileError("PageAllocator backend missing decl: " ++ name);
            }
        }

        inline for (.{ "start", "order" }) |name| {
            if (!@hasField(Backend.Block, name)) {
                @compileError("PageAllocator backend Block missing field: " ++ name);
            }
        }

        inline for (.{ "start", "end" }) |name| {
            if (!@hasField(Backend.Range, name)) {
                @compileError("PageAllocator backend Range missing field: " ++ name);
            }
        }

        const errors = @typeInfo(Backend.Error).error_set orelse {
            @compileError("PageAllocator backend Error must be a named error set");
        };

        for (errors) |err| {
            var found = false;
            for (@typeInfo(Error).error_set.?) |expected| {
                if (std.mem.eql(u8, err.name, expected.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                @compileError("PageAllocator backend Error contains variant not in PageAllocator.Error: " ++ err.name);
            }
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    const Page = @import("addr").Page(@import("addr").PhysAddr, 4096);
    const Backend = @import("buddy.zig").BuddyAllocator.Static(16, 5);

    const origin = Page.Base.fromInt(0x100000) catch unreachable;

    test "core allocation converts relative blocks and coalesces on free" {
        var backend = Backend.init();
        const allocation = try Impl.alloc(Backend, Page, &backend, origin, 2);
        const range = allocation.range();

        try testing.expectEqual(origin, range.first());
        try testing.expectEqual(@as(u64, 4), range.count().raw());
        try testing.expect(!Impl.hasFreeBlock(Backend, Page, &backend, origin, range));
        try testing.expectEqual(@as(?u8, 3), Impl.largestFreeOrder(Backend, &backend));

        try Impl.free(Backend, Page, &backend, origin, allocation);

        try testing.expectEqual(@as(?u8, 4), Impl.largestFreeOrder(Backend, &backend));
        try testing.expect(Impl.hasFreeBlock(Backend, Page, &backend, origin, try Page.Range.init(origin, try origin.add(Page.Count.from(15)))));
        try testing.expect(Impl.isValid(Backend, Page, &backend, origin));
    }

    test "free block query distinguishes a represented block from a splittable subrange" {
        var backend = Backend.init();

        const whole = try Page.Range.init(origin, try origin.add(Page.Count.from(15)));
        const first = try Page.Range.init(origin, origin);

        try testing.expect(Impl.hasFreeBlock(Backend, Page, &backend, origin, whole));
        try testing.expect(!Impl.hasFreeBlock(Backend, Page, &backend, origin, first));

        const allocated = try Impl.alloc(Backend, Page, &backend, origin, 0);

        try testing.expectEqual(first, allocated.range());
    }

    test "validation rejects invalid backend metadata" {
        var backend = Backend.init();
        _ = try backend.bitmap.set(16);

        try testing.expect(!Impl.isValid(Backend, Page, &backend, origin));
    }

    test "core reservation excludes pages and preserves state on failure" {
        var backend = Backend.init();

        const start = try origin.add(Page.Count.from(3));
        const reserved = try Page.Range.init(start, try start.add(Page.Count.from(1)));
        const end = try origin.add(Page.Count.from(16));

        try Impl.reserve(Backend, Page, &backend, origin, reserved);

        try testing.expectError(error.AlreadyAllocated, Impl.reserve(Backend, Page, &backend, origin, reserved));
        try testing.expectError(error.OutOfBounds, Impl.reserve(Backend, Page, &backend, origin, try Page.Range.init(end, end)));
        try testing.expectEqual(@as(usize, 14), backend.remaining());

        for (0..14) |_| {
            const allocation = try Impl.alloc(Backend, Page, &backend, origin, 0);
            const range = allocation.range();
            const index = (range.first().raw() - origin.raw()) / Page.size;
            try testing.expect(index != 3 and index != 4);
        }

        try testing.expectError(error.OutOfMemory, Impl.alloc(Backend, Page, &backend, origin, 0));
    }

    test "core rejects invalid orders and malformed block ranges without allocation" {
        var backend = Backend.init();

        const misaligned = try origin.add(Page.Count.from(1));
        const before = try origin.sub(Page.Count.from(1));

        const bad_ranges = [_]Page.Range{
            try Page.Range.init(origin, try origin.add(Page.Count.from(2))),
            try Page.Range.init(misaligned, try misaligned.add(Page.Count.from(1))),
        };

        try testing.expectError(error.InvalidOrder, Impl.alloc(Backend, Page, &backend, origin, 5));

        for (bad_ranges) |range| {
            try testing.expectError(error.InvalidRequest, Impl.blockFromRange(Backend, Page, &backend, origin, range));
            try testing.expect(!Impl.hasFreeBlock(Backend, Page, &backend, origin, range));
        }

        try testing.expectError(error.OutOfBounds, Impl.blockFromRange(Backend, Page, &backend, origin, try Page.Range.init(before, before)));
        try testing.expectEqual(@as(usize, 0), backend.allocated());
    }

    test "variants retain origin and bounded construction checks the address limit" {
        const fixed = PageAllocator.Static(Backend, Page, origin).init();
        var bounded = try PageAllocator.Bounded(Backend, Page).init(fixed.backend, origin);

        const allocation = try bounded.alloc(1);

        try testing.expectEqual(origin, fixed.base());
        try testing.expectEqual(origin, bounded.base());
        try testing.expectEqual(@as(u64, 16), bounded.capacity());
        try testing.expectEqual(@as(u64, 2), bounded.allocated());
        try testing.expectEqual(@as(u64, 14 * Page.size), try bounded.remainingBytes());

        try bounded.free(allocation);

        try testing.expectEqual(bounded.capacity(), bounded.remaining());

        const limit = try Page.Base.fromInt(std.math.maxInt(Page.Int) & ~Page.mask);

        try testing.expectError(error.Overflow, PageAllocator.Bounded(Backend, Page).init(Backend.init(), limit));
    }

    test "static and bounded extents include the final page" {
        const SmallPage = @import("addr").Page(@import("addr").Address(opaque {}, u8), 2);
        const first = comptime SmallPage.Base.fromInt(224) catch unreachable;
        const last = try SmallPage.Base.fromInt(254);
        const final = try SmallPage.Range.init(last, last);
        const Fixed = PageAllocator.Static(Backend, SmallPage, first);
        const Bounded = PageAllocator.Bounded(Backend, SmallPage);

        inline for (.{ Fixed.init(), try Bounded.init(Backend.init(), first) }) |initial| {
            var pages = initial;
            try testing.expect(pages.isValid());
            try pages.reserve(final);
            try testing.expectEqual(@as(u8, 15), pages.remaining());
            try testing.expectError(error.AlreadyAllocated, pages.reserve(final));
            try pages.free(.{ .inner = final });
            const allocation = try pages.alloc(4);
            try testing.expectEqual(first, allocation.range().first());
            try testing.expectEqual(last, allocation.range().last());
            try pages.free(allocation);
            try testing.expectEqual(@as(u8, 16), pages.remaining());
            try testing.expect(pages.isValid());
        }
    }

    test "static and bounded support a full address space extent" {
        const SmallPage = @import("addr").Page(@import("addr").Address(opaque {}, u8), 2);
        const FullBackend = @import("buddy.zig").BuddyAllocator.Static(128, 8);
        const first = comptime SmallPage.Base.fromInt(0) catch unreachable;
        const last = try SmallPage.Base.fromInt(254);
        const final = try SmallPage.Range.init(last, last);
        const Fixed = PageAllocator.Static(FullBackend, SmallPage, first);
        const Bounded = PageAllocator.Bounded(FullBackend, SmallPage);

        inline for (.{ Fixed.init(), try Bounded.init(FullBackend.init(), first) }) |initial| {
            var pages = initial;
            try testing.expect(pages.isValid());
            try testing.expectError(error.Overflow, pages.remainingBytes());
            try pages.reserve(final);
            try pages.free(.{ .inner = final });
            const allocation = try pages.alloc(7);
            const range = allocation.range();
            try testing.expectEqual(first, range.first());
            try testing.expectEqual(last, range.last());
            try testing.expectEqual(@as(u8, 128), range.count().raw());
            try testing.expectError(error.Overflow, range.bytes());
            try testing.expectEqual(@as(u8, 0), pages.remaining());
            try pages.free(allocation);
            try testing.expectEqual(@as(u8, 128), pages.remaining());
            try testing.expect(pages.isValid());
        }
    }
};
