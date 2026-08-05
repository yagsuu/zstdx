//! Page-typed wrapper around a unit-index allocator backend.
//! See `docs/specs/mem/alloc/frame.md`.

const std = @import("std");

const allocation = @import("../../algo/allocation.zig");

pub const FrameAllocator = struct {
    /// Owns an inline backend and a comptime base frame.
    pub fn Static(
        comptime Backend: type,
        comptime Page: type,
        comptime base_frame: Page.Frame,
    ) type {
        comptime requireBackend(Backend);

        return struct {
            backend: Backend = Backend.init(),

            const Self = @This();

            pub const Frame = Page.Frame;
            pub const FrameRange = Page.FrameRange;
            pub const AddressInt = Page.AddressInt;

            /// Superset of errors from all frame allocator operations.
            pub const Error = FrameError;

            pub fn init() Self {
                return .{};
            }

            pub fn baseFrame(self: *const Self) Frame {
                _ = self;
                return base_frame;
            }

            pub fn capacityFrames(self: *const Self) AddressInt {
                return @intCast(self.backend.capacity());
            }

            pub fn freeFrames(self: *const Self) AddressInt {
                return @intCast(self.backend.remainingUnits());
            }

            pub fn allocatedFrames(self: *const Self) AddressInt {
                return @intCast(self.backend.allocatedUnits());
            }

            pub fn largestFreeOrder(self: *const Self) ?u8 {
                return largestFreeOrderImpl(Backend, &self.backend);
            }

            pub fn remainingBytes(self: *const Self) Error!AddressInt {
                return remainingBytesImpl(AddressInt, Page.Size.bytes, self.freeFrames());
            }

            pub fn isFree(self: *const Self, range: FrameRange) bool {
                return isFreeImpl(Backend, Page, &self.backend, base_frame, range);
            }

            /// Allocates `1 << order` frames.
            /// Errors leave allocator state unchanged.
            pub fn alloc(self: *Self, order: u8) Error!FrameRange {
                return allocImpl(Backend, Page, &self.backend, base_frame, order);
            }

            /// Requires one allocated block.
            /// Errors leave allocator state unchanged.
            pub fn free(self: *Self, range: FrameRange) Error!void {
                return freeImpl(Backend, Page, &self.backend, base_frame, range);
            }

            /// Requires a valid `range`.
            /// An empty in-bounds range is a no-op; errors do not mutate.
            pub fn reserve(self: *Self, range: FrameRange) Error!void {
                return reserveImpl(Backend, Page, &self.backend, base_frame, range);
            }

            pub fn FrameSource(comptime order: u8) type {
                return FrameSourceImpl(Self, Page, order);
            }

            pub fn frameSource(self: *Self, comptime order: u8) FrameSource(order) {
                return .{ .parent = self };
            }

            pub fn isValid(self: *const Self) bool {
                return isValidImpl(Backend, Page, &self.backend, base_frame);
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }

    pub fn Bounded(
        comptime Backend: type,
        comptime Page: type,
    ) type {
        comptime requireBackend(Backend);

        return struct {
            backend: Backend,
            base: Page.Frame,

            const Self = @This();

            pub const Frame = Page.Frame;
            pub const FrameRange = Page.FrameRange;
            pub const AddressInt = Page.AddressInt;

            pub const Error = FrameError;

            pub fn wrap(backend: Backend, base: Frame) Error!Self {
                _ = base.add(Page.Count.fromPages(@intCast(backend.capacity()))) catch return error.Overflow;
                return .{ .backend = backend, .base = base };
            }

            pub fn baseFrame(self: *const Self) Frame {
                return self.base;
            }

            pub fn capacityFrames(self: *const Self) AddressInt {
                return @intCast(self.backend.capacity());
            }

            pub fn freeFrames(self: *const Self) AddressInt {
                return @intCast(self.backend.remainingUnits());
            }

            pub fn allocatedFrames(self: *const Self) AddressInt {
                return @intCast(self.backend.allocatedUnits());
            }

            pub fn largestFreeOrder(self: *const Self) ?u8 {
                return largestFreeOrderImpl(Backend, &self.backend);
            }

            pub fn remainingBytes(self: *const Self) Error!AddressInt {
                return remainingBytesImpl(AddressInt, Page.Size.bytes, self.freeFrames());
            }

            pub fn isFree(self: *const Self, range: FrameRange) bool {
                return isFreeImpl(Backend, Page, &self.backend, self.base, range);
            }

            /// Allocates `1 << order` frames.
            /// Errors leave allocator state unchanged.
            pub fn alloc(self: *Self, order: u8) Error!FrameRange {
                return allocImpl(Backend, Page, &self.backend, self.base, order);
            }

            /// Requires one allocated block.
            /// Errors leave allocator state unchanged.
            pub fn free(self: *Self, range: FrameRange) Error!void {
                return freeImpl(Backend, Page, &self.backend, self.base, range);
            }

            /// Requires a valid `range`.
            /// An empty in-bounds range is a no-op; errors do not mutate.
            pub fn reserve(self: *Self, range: FrameRange) Error!void {
                return reserveImpl(Backend, Page, &self.backend, self.base, range);
            }

            pub fn FrameSource(comptime order: u8) type {
                return FrameSourceImpl(Self, Page, order);
            }

            pub fn frameSource(self: *Self, comptime order: u8) FrameSource(order) {
                return .{ .parent = self };
            }

            pub fn isValid(self: *const Self) bool {
                return isValidImpl(Backend, Page, &self.backend, self.base);
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }
};

const Buddy = allocation.Buddy;

/// Error superset required from conforming backends.
const FrameError = error{
    OutOfMemory,
    OutOfBounds,
    InvalidRequest,
    InvalidOrder,
    AlreadyAllocated,
    NotAllocated,
    Overflow,
};

fn requireBackend(comptime Backend: type) void {
    inline for (.{ "Block", "Range", "Error" }) |name| {
        if (!@hasDecl(Backend, name)) {
            @compileError("FrameAllocator backend missing decl: " ++ name);
        }
    }
    inline for (.{
        "capacity",       "orderCount",     "maxOrder",
        "allocatedUnits", "remainingUnits", "alloc",
        "free",           "reserve",        "isFreeBlock",
        "assertValid",
    }) |name| {
        if (!@hasDecl(Backend, name)) {
            @compileError("FrameAllocator backend missing decl: " ++ name);
        }
    }
    if (!@hasField(Backend.Block, "start")) {
        @compileError("FrameAllocator backend Block missing field: start");
    }
    if (!@hasField(Backend.Block, "order")) {
        @compileError("FrameAllocator backend Block missing field: order");
    }
    if (!@hasField(Backend.Range, "start")) {
        @compileError("FrameAllocator backend Range missing field: start");
    }
    if (!@hasField(Backend.Range, "end")) {
        @compileError("FrameAllocator backend Range missing field: end");
    }
    requireBackendErrorFits(Backend, FrameError);
}

fn requireBackendErrorFits(comptime Backend: type, comptime Superset: type) void {
    const info = @typeInfo(Backend.Error).error_set orelse {
        @compileError("FrameAllocator backend Error must be a named error set");
    };
    const super_set = @typeInfo(Superset).error_set.?;
    for (info) |backend_err| {
        var found = false;
        for (super_set) |super_err| {
            if (std.mem.eql(u8, backend_err.name, super_err.name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            @compileError(
                "FrameAllocator backend Error contains variant not in FrameAllocator.Error: " ++ backend_err.name,
            );
        }
    }
}

fn allocImpl(
    comptime Backend: type,
    comptime Page: type,
    backend: *Backend,
    base: Page.Frame,
    order: u8,
) FrameError!Page.FrameRange {
    if (order >= backend.orderCount()) return error.InvalidOrder;
    const block = try backend.alloc(order);
    return frameRangeFromBlock(Backend, Page, base, block);
}

fn freeImpl(
    comptime Backend: type,
    comptime Page: type,
    backend: *Backend,
    base: Page.Frame,
    range: Page.FrameRange,
) FrameError!void {
    const block = try blockFromFrameRange(Page, backend, base, range);
    try backend.free(block);
}

fn reserveImpl(
    comptime Backend: type,
    comptime Page: type,
    backend: *Backend,
    base: Page.Frame,
    range: Page.FrameRange,
) FrameError!void {
    if (!range.isValid()) return error.InvalidRequest;

    const base_unit = base.addressInt() >> Page.Size.shift;
    const range_start_unit = range.base.addressInt() >> Page.Size.shift;

    if (range_start_unit < base_unit) return error.OutOfBounds;
    const relative_start = range_start_unit - base_unit;

    const page_count = range.count.pages();
    if (page_count == 0) {
        if (relative_start > backend.capacity()) return error.OutOfBounds;
        return;
    }

    const relative_end = std.math.add(Page.AddressInt, relative_start, page_count) catch return error.Overflow;
    if (relative_end > backend.capacity()) return error.OutOfBounds;

    const unit_range = Backend.Range{
        .start = @intCast(relative_start),
        .end = @intCast(relative_end),
    };
    try backend.reserve(unit_range);
}

fn isFreeImpl(
    comptime Backend: type,
    comptime Page: type,
    backend: *const Backend,
    base: Page.Frame,
    range: Page.FrameRange,
) bool {
    if (!range.isValid()) return false;
    if (range.isEmpty()) return false;

    const page_count = range.count.pages();
    const order = Buddy.orderForLen(@intCast(page_count)) catch return false;
    const block_size = Buddy.blockSize(order) catch return false;
    if (block_size != page_count) return false;

    const base_unit = base.addressInt() >> Page.Size.shift;
    const range_start_unit = range.base.addressInt() >> Page.Size.shift;
    if (range_start_unit < base_unit) return false;

    const relative_start_wide = range_start_unit - base_unit;
    const relative_start: usize = std.math.cast(usize, relative_start_wide) orelse return false;
    if ((relative_start % block_size) != 0) return false;

    const relative_end = std.math.add(usize, relative_start, block_size) catch return false;
    if (relative_end > backend.capacity()) return false;

    const block = Backend.Block{ .start = relative_start, .order = order };
    return backend.isFreeBlock(block);
}

fn largestFreeOrderImpl(comptime Backend: type, backend: *const Backend) ?u8 {
    if (backend.remainingUnits() == 0) return null;
    var order: u8 = backend.maxOrder();
    while (true) : (order -%= 1) {
        const block_size = Buddy.blockSize(order) catch {
            if (order == 0) return null;
            continue;
        };
        const capacity = backend.capacity();
        var start: usize = 0;
        while (start + block_size <= capacity) : (start += block_size) {
            const block = Backend.Block{ .start = start, .order = order };
            if (backend.isFreeBlock(block)) return order;
        }
        if (order == 0) return null;
    }
}

fn remainingBytesImpl(
    comptime AddressInt: type,
    page_bytes: AddressInt,
    free_frames: AddressInt,
) FrameError!AddressInt {
    return std.math.mul(AddressInt, free_frames, page_bytes) catch error.Overflow;
}

fn isValidImpl(
    comptime Backend: type,
    comptime Page: type,
    backend: *const Backend,
    base: Page.Frame,
) bool {
    if (!base.isValid()) return false;
    const capacity_frames_wide = backend.capacity();
    const capacity_frames = std.math.cast(Page.AddressInt, capacity_frames_wide) orelse return false;
    _ = base.add(Page.Count.fromPages(capacity_frames)) catch return false;

    const allocated = backend.allocatedUnits();
    const remaining = backend.remainingUnits();
    const sum = std.math.add(usize, allocated, remaining) catch return false;
    if (sum != capacity_frames_wide) return false;

    return true;
}

fn frameRangeFromBlock(
    comptime Backend: type,
    comptime Page: type,
    base: Page.Frame,
    block: Backend.Block,
) FrameError!Page.FrameRange {
    const start_offset: Page.AddressInt =
        std.math.cast(Page.AddressInt, block.start) orelse return error.Overflow;
    const count_pages_native: usize = Buddy.blockSize(block.order) catch return error.Overflow;
    const count_pages: Page.AddressInt =
        std.math.cast(Page.AddressInt, count_pages_native) orelse return error.Overflow;

    const base_frame = base.add(Page.Count.fromPages(start_offset)) catch return error.Overflow;
    return Page.FrameRange.fromBaseCount(base_frame, Page.Count.fromPages(count_pages)) catch return error.Overflow;
}

fn blockFromFrameRange(
    comptime Page: type,
    backend: anytype,
    base: Page.Frame,
    range: Page.FrameRange,
) FrameError!@TypeOf(backend.*).Block {
    if (!range.isValid()) return error.InvalidRequest;
    if (range.isEmpty()) return error.InvalidRequest;

    const page_count = range.count.pages();
    const order = Buddy.orderForLen(@intCast(page_count)) catch return error.InvalidRequest;
    const block_size = Buddy.blockSize(order) catch return error.InvalidRequest;
    if (block_size != page_count) return error.InvalidRequest;

    const base_unit = base.addressInt() >> Page.Size.shift;
    const range_start_unit = range.base.addressInt() >> Page.Size.shift;
    if (range_start_unit < base_unit) return error.OutOfBounds;

    const relative_start_wide = range_start_unit - base_unit;
    const relative_start: usize = std.math.cast(usize, relative_start_wide) orelse return error.OutOfBounds;
    if ((relative_start % block_size) != 0) return error.InvalidRequest;

    const relative_end = std.math.add(usize, relative_start, block_size) catch return error.Overflow;
    if (relative_end > backend.capacity()) return error.OutOfBounds;

    const BlockT = @TypeOf(backend.*).Block;
    return BlockT{ .start = relative_start, .order = order };
}

fn FrameSourceImpl(comptime Parent: type, comptime Page: type, comptime order: u8) type {
    const size_native = @as(u128, Page.Size.bytes) << order;
    if (size_native > std.math.maxInt(usize)) {
        @compileError("FrameSource region_bytes overflows usize");
    }

    return struct {
        parent: *Parent,

        pub const region_bytes: usize = @intCast(size_native);
        pub const region_align: usize = @intCast(Page.Size.bytes);
        pub const Error = Parent.Error;

        const RegionPtr = *align(region_align) [region_bytes]u8;

        pub fn acquire(self: *@This()) Error!RegionPtr {
            const range = try self.parent.alloc(order);
            const address_int = range.base.addressInt();
            const raw: usize = std.math.cast(usize, address_int) orelse return error.Overflow;
            return @ptrFromInt(raw);
        }

        pub fn release(self: *@This(), region: RegionPtr) void {
            const raw: usize = @intFromPtr(region);
            const address_int: Page.AddressInt = @intCast(raw);
            const frame = Page.Frame.fromAddressInt(address_int) catch unreachable;
            const count_pages = Buddy.blockSize(order) catch unreachable;
            const count = Page.Count.fromPages(@intCast(count_pages));
            const range = Page.FrameRange.fromBaseCount(frame, count) catch unreachable;
            self.parent.free(range) catch |err| std.debug.panic(
                "FrameSource.release: parent.free failed ({s}); " ++
                    "foreign region or double-release violates RegionSource contract",
                .{@errorName(err)},
            );
        }
    };
}
