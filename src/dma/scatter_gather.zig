//! DMA segment lists and aligned append builders.
//! See `docs/specs/dma/scatter-gather.md`.

const std = @import("std");

const address = @import("../addr/address.zig");
const bits = @import("../bits.zig");
const buffer = @import("buffer.zig");

const DMAAddr = address.DMAAddr;
const DMARaw = DMAAddr.Raw;

/// A segment describes an untyped device-visible byte range.
pub const Segment = struct {
    addr: DMAAddr,
    len_bytes: DMARaw,

    pub const Address = DMAAddr;

    /// `Overflow`: `addr.raw() + len_bytes` exceeds `Address.Raw`.
    pub const Error = error{Overflow};

    /// Validates that `[addr, addr + len_bytes)` does not overflow.
    pub fn init(addr: DMAAddr, len_bytes: DMARaw) Error!Segment {
        _ = std.math.add(DMARaw, addr.raw(), len_bytes) catch return error.Overflow;
        return .{ .addr = addr, .len_bytes = len_bytes };
    }

    pub fn fromBuffer(comptime T: type, buf: buffer.Buffer(T)) Segment {
        return .{ .addr = buf.dmaAddr(), .len_bytes = buf.byteLen() };
    }

    pub fn byteLen(self: Segment) DMARaw {
        return self.len_bytes;
    }

    pub fn isEmpty(self: Segment) bool {
        return self.len_bytes == 0;
    }

    /// The returned address is one byte past the segment.
    pub fn endAddr(self: Segment) Error!DMAAddr {
        const raw = std.math.add(DMARaw, self.addr.raw(), self.len_bytes) catch return error.Overflow;
        return DMAAddr.fromInt(raw);
    }

    /// Returns `false` for zero or non-power-of-two alignment.
    pub fn isAligned(self: Segment, alignment: DMARaw) bool {
        if (alignment == 0) return false;
        if (!bits.isPowerOfTwo(DMARaw, alignment)) return false;
        const mask = alignment - 1;
        if ((self.addr.raw() & mask) != 0) return false;
        return (self.len_bytes & mask) == 0;
    }

    pub fn assertValid(self: Segment) void {
        _ = std.math.add(DMARaw, self.addr.raw(), self.len_bytes) catch unreachable;
    }
};

/// `Static` owns segment-list storage. `Bounded` borrows storage.
pub const List = struct {
    pub fn Static(comptime capacity_segments: usize) type {
        comptime if (capacity_segments == 0) @compileError("dma.List.Static capacity_segments must be non-zero");
        return struct {
            buffer: [capacity_segments]Segment = undefined,
            count: usize = 0,

            const Self = @This();

            /// `Full`: The list is at capacity.
            /// `OutOfBounds`: The index is at or past `count`.
            pub const Error = error{ Full, OutOfBounds };

            /// The compile-time capacity in segments.
            pub const segment_capacity = capacity_segments;

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                self.assertValid();
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return segment_capacity;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == segment_capacity;
            }

            pub fn asSlice(self: *Self) []Segment {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            pub fn asConstSlice(self: *const Self) []const Segment {
                self.assertValid();
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn append(self: *Self, segment: Segment) error{Full}!void {
                if (self.isFull()) return error.Full;
                self.appendAssumeCapacity(segment);
            }

            pub fn appendAssumeCapacity(self: *Self, segment: Segment) void {
                std.debug.assert(!self.isFull());
                if (segment_capacity == 0) unreachable;

                self.buffer[self.count] = segment;
                self.count += 1;
            }

            pub fn appendBuffer(self: *Self, comptime T: type, buf: buffer.Buffer(T)) error{Full}!void {
                return self.append(Segment.fromBuffer(T, buf));
            }

            pub fn at(self: *Self, index: usize) error{OutOfBounds}!*Segment {
                if (index >= self.count) return error.OutOfBounds;
                return &self.buffer[index];
            }

            pub fn constAt(self: *const Self, index: usize) error{OutOfBounds}!*const Segment {
                if (index >= self.count) return error.OutOfBounds;
                return &self.buffer[index];
            }

            /// `error.Overflow` is returned if the sum exceeds `Address.Raw`.
            pub fn totalByteLen(self: *const Self) error{Overflow}!DMARaw {
                return sumSegmentLens(self.asConstSlice());
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.count <= segment_capacity);
                for (self.buffer[0..self.count]) |segment| segment.assertValid();
            }
        };
    }

    /// Bounded lists borrow storage. Their capacity is `buffer.len`.
    pub const Bounded = struct {
        buffer: []Segment,
        count: usize = 0,

        /// `Full`: The list is at capacity.
        /// `OutOfBounds`: The index is at or past `count`.
        pub const Error = error{ Full, OutOfBounds };

        pub fn wrap(buf: []Segment) Bounded {
            return .{ .buffer = buf };
        }

        pub fn len(self: *const Bounded) usize {
            self.assertValid();
            return self.count;
        }

        pub fn capacity(self: *const Bounded) usize {
            self.assertValid();
            return self.buffer.len;
        }

        pub fn remaining(self: *const Bounded) usize {
            return self.capacity() - self.len();
        }

        pub fn isEmpty(self: *const Bounded) bool {
            return self.len() == 0;
        }

        pub fn isFull(self: *const Bounded) bool {
            return self.len() == self.capacity();
        }

        pub fn asSlice(self: *Bounded) []Segment {
            self.assertValid();
            return self.buffer[0..self.count];
        }

        pub fn asConstSlice(self: *const Bounded) []const Segment {
            self.assertValid();
            return self.buffer[0..self.count];
        }

        pub fn clearRetainingCapacity(self: *Bounded) void {
            self.count = 0;
        }

        pub fn append(self: *Bounded, segment: Segment) error{Full}!void {
            if (self.isFull()) return error.Full;
            self.appendAssumeCapacity(segment);
        }

        pub fn appendAssumeCapacity(self: *Bounded, segment: Segment) void {
            std.debug.assert(!self.isFull());
            if (self.buffer.len == 0) unreachable;

            self.buffer[self.count] = segment;
            self.count += 1;
        }

        pub fn appendBuffer(self: *Bounded, comptime T: type, buf: buffer.Buffer(T)) error{Full}!void {
            return self.append(Segment.fromBuffer(T, buf));
        }

        pub fn at(self: *Bounded, index: usize) error{OutOfBounds}!*Segment {
            if (index >= self.count) return error.OutOfBounds;
            return &self.buffer[index];
        }

        pub fn constAt(self: *const Bounded, index: usize) error{OutOfBounds}!*const Segment {
            if (index >= self.count) return error.OutOfBounds;
            return &self.buffer[index];
        }

        pub fn totalByteLen(self: *const Bounded) error{Overflow}!DMARaw {
            return sumSegmentLens(self.asConstSlice());
        }

        pub fn assertValid(self: *const Bounded) void {
            std.debug.assert(self.count <= self.buffer.len);
            for (self.buffer[0..self.count]) |segment| segment.assertValid();
        }
    };
};

fn requireAlignment(comptime alignment: DMARaw) void {
    if (alignment == 0) @compileError("Builder alignment must be non-zero");
    if (!bits.isPowerOfTwo(DMARaw, alignment)) @compileError("Builder alignment must be a power of two");
}

/// Builders require a uniform alignment for each appended segment.
pub const Builder = struct {
    /// Static builders own inline segment storage.
    pub fn Static(comptime capacity_segments: usize, comptime alignment: DMARaw) type {
        comptime if (capacity_segments == 0) @compileError("dma.Builder.Static capacity_segments must be non-zero");
        comptime requireAlignment(alignment);
        return struct {
            list: List.Static(capacity_segments) = .{},

            const Self = @This();
            const InnerList = List.Static(capacity_segments);

            /// `Full`: The underlying list is at capacity.
            /// `Misaligned`: The segment fails `isAligned(alignment)`.
            pub const Error = error{ Full, Misaligned };

            /// Appended segments must meet this alignment.
            pub const segment_alignment = alignment;

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                return self.list.len();
            }

            pub fn capacity(self: *const Self) usize {
                return self.list.capacity();
            }

            pub fn remaining(self: *const Self) usize {
                return self.list.remaining();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.list.isEmpty();
            }

            pub fn isFull(self: *const Self) bool {
                return self.list.isFull();
            }

            pub fn asSlice(self: *Self) []Segment {
                return self.list.asSlice();
            }

            pub fn asConstSlice(self: *const Self) []const Segment {
                return self.list.asConstSlice();
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.list.clearRetainingCapacity();
            }

            /// Misalignment is reported before capacity. Errors leave the list unchanged.
            pub fn append(self: *Self, segment: Segment) Error!void {
                if (alignment != 1 and !segment.isAligned(alignment)) return error.Misaligned;
                self.list.append(segment) catch |err| switch (err) {
                    error.Full => return error.Full,
                };
            }

            pub fn appendBuffer(self: *Self, comptime T: type, buf: buffer.Buffer(T)) Error!void {
                return self.append(Segment.fromBuffer(T, buf));
            }

            /// Returns a const list view. Mutating or moving the builder invalidates the view.
            pub fn finish(self: *Self) *const InnerList {
                return &self.list;
            }

            pub fn assertValid(self: *const Self) void {
                self.list.assertValid();
                for (self.list.asConstSlice()) |segment| {
                    std.debug.assert(segment.isAligned(alignment));
                }
            }
        };
    }

    /// Bounded builders borrow segment storage.
    pub fn Bounded(comptime alignment: DMARaw) type {
        comptime requireAlignment(alignment);
        return struct {
            list: List.Bounded,

            const Self = @This();

            /// `Full`: The underlying list is at capacity.
            /// `Misaligned`: The segment fails `isAligned(alignment)`.
            pub const Error = error{ Full, Misaligned };

            /// Appended segments must meet this alignment.
            pub const segment_alignment = alignment;

            pub fn wrap(buf: []Segment) Self {
                return .{ .list = List.Bounded.wrap(buf) };
            }

            pub fn len(self: *const Self) usize {
                return self.list.len();
            }

            pub fn capacity(self: *const Self) usize {
                return self.list.capacity();
            }

            pub fn remaining(self: *const Self) usize {
                return self.list.remaining();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.list.isEmpty();
            }

            pub fn isFull(self: *const Self) bool {
                return self.list.isFull();
            }

            pub fn asSlice(self: *Self) []Segment {
                return self.list.asSlice();
            }

            pub fn asConstSlice(self: *const Self) []const Segment {
                return self.list.asConstSlice();
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.list.clearRetainingCapacity();
            }

            /// Misalignment is reported before capacity. Errors leave the list unchanged.
            pub fn append(self: *Self, segment: Segment) Error!void {
                if (alignment != 1 and !segment.isAligned(alignment)) return error.Misaligned;
                self.list.append(segment) catch |err| switch (err) {
                    error.Full => return error.Full,
                };
            }

            pub fn appendBuffer(self: *Self, comptime T: type, buf: buffer.Buffer(T)) Error!void {
                return self.append(Segment.fromBuffer(T, buf));
            }

            /// Returns a const list view. Mutating or moving the builder invalidates the view.
            pub fn finish(self: *Self) *const List.Bounded {
                return &self.list;
            }

            pub fn assertValid(self: *const Self) void {
                self.list.assertValid();
                for (self.list.asConstSlice()) |segment| {
                    std.debug.assert(segment.isAligned(alignment));
                }
            }
        };
    }
};

fn sumSegmentLens(segments: []const Segment) error{Overflow}!DMARaw {
    var total: DMARaw = 0;
    for (segments) |segment| {
        total = std.math.add(DMARaw, total, segment.len_bytes) catch return error.Overflow;
    }
    return total;
}
