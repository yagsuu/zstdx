//! DMA segment lists and aligned append builders.
//! Spec: docs/specs/dma/scatter-gather.md.

const std = @import("std");

const address = @import("../addr/address.zig");
const bits = @import("../bits.zig");
const buffer = @import("buffer.zig");

const DmaAddr = address.DmaAddr;
const DmaRaw = DmaAddr.Raw;

/// A segment describes an untyped device-visible byte range.
pub const Segment = struct {
    addr: DmaAddr,
    len_bytes: DmaRaw,

    pub const Address = DmaAddr;

    /// `Misaligned`: builder alignment rejection.
    /// `Overflow`: `addr.raw() + len_bytes` exceeds `Address.Raw`.
    pub const Error = error{ Misaligned, Overflow };

    /// Creates a validated `[addr, addr + len_bytes)` segment.
    pub fn init(addr: DmaAddr, len_bytes: DmaRaw) Error!Segment {
        _ = std.math.add(DmaRaw, addr.raw(), len_bytes) catch return error.Overflow;
        return .{ .addr = addr, .len_bytes = len_bytes };
    }

    /// Creates a segment covering the whole `Buffer(T)`.
    pub fn fromBuffer(comptime T: type, buf: buffer.Buffer(T)) Segment {
        return .{ .addr = buf.dmaAddr(), .len_bytes = buf.byteLen() };
    }

    pub fn byteLen(self: Segment) DmaRaw {
        return self.len_bytes;
    }

    pub fn isEmpty(self: Segment) bool {
        return self.len_bytes == 0;
    }

    /// Returns the one-past-the-end device address. Hand-built segments are revalidated.
    pub fn endAddr(self: Segment) Error!DmaAddr {
        const raw = std.math.add(DmaRaw, self.addr.raw(), self.len_bytes) catch return error.Overflow;
        return DmaAddr.fromInt(raw);
    }

    /// Returns true iff both `addr` and `len_bytes` are aligned. Invalid
    /// alignment returns `false`.
    pub fn isAligned(self: Segment, alignment: DmaRaw) bool {
        if (alignment == 0) return false;
        if (!bits.isPowerOfTwo(DmaRaw, alignment)) return false;
        const mask = alignment - 1;
        if ((self.addr.raw() & mask) != 0) return false;
        return (self.len_bytes & mask) == 0;
    }

    pub fn assertValid(self: Segment) void {
        _ = std.math.add(DmaRaw, self.addr.raw(), self.len_bytes) catch unreachable;
    }
};

/// `Static(N)` owns segment-list storage. `Bounded` borrows storage.
pub const List = struct {
    /// Provides inline segment storage. Zero capacity is valid.
    pub fn Static(comptime capacity_segments: usize) type {
        return struct {
            buffer: [capacity_segments]Segment = undefined,
            count: usize = 0,

            const Self = @This();

            /// `Full`: `append` at capacity.
            /// `OutOfBounds`: index access at or past `count`.
            pub const Error = error{ Full, OutOfBounds };

            /// Comptime capacity in segments.
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

            /// Sums `len_bytes`. Returns `error.Overflow` on `Address.Raw` wrap.
            pub fn totalByteLen(self: *const Self) error{Overflow}!DmaRaw {
                return sumSegmentLens(self.asConstSlice());
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.count <= segment_capacity);
                for (self.buffer[0..self.count]) |segment| segment.assertValid();
            }
        };
    }

    /// Borrows segment storage. Capacity is `buffer.len`.
    pub const Bounded = struct {
        buffer: []Segment,
        count: usize = 0,

        /// `Full`: `append` at capacity.
        /// `OutOfBounds`: index access at or past `count`.
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

        pub fn totalByteLen(self: *const Bounded) error{Overflow}!DmaRaw {
            return sumSegmentLens(self.asConstSlice());
        }

        pub fn assertValid(self: *const Bounded) void {
            std.debug.assert(self.count <= self.buffer.len);
            for (self.buffer[0..self.count]) |segment| segment.assertValid();
        }
    };
};

fn requireAlignment(comptime alignment: DmaRaw) void {
    if (alignment == 0) @compileError("Builder alignment must be non-zero");
    if (!bits.isPowerOfTwo(DmaRaw, alignment)) @compileError("Builder alignment must be a power of two");
}

/// Builders enforce uniform per-segment alignment on append.
pub const Builder = struct {
    /// Builds over inline segment storage.
    pub fn Static(comptime capacity_segments: usize, comptime alignment: DmaRaw) type {
        comptime requireAlignment(alignment);
        return struct {
            list: List.Static(capacity_segments) = .{},

            const Self = @This();
            const InnerList = List.Static(capacity_segments);

            /// `Full`: underlying list at capacity.
            /// `Misaligned`: segment fails `isAligned(alignment)`.
            pub const Error = error{ Full, Misaligned };

            /// Segments appended through this builder must meet this alignment.
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

            /// Returns a const list view. Mutation or moving the builder invalidates it.
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

    /// Builds over borrowed segment storage.
    pub fn Bounded(comptime alignment: DmaRaw) type {
        comptime requireAlignment(alignment);
        return struct {
            list: List.Bounded,

            const Self = @This();

            /// `Full`: underlying list at capacity.
            /// `Misaligned`: segment fails `isAligned(alignment)`.
            pub const Error = error{ Full, Misaligned };

            /// Segments appended through this builder must meet this alignment.
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

            /// Returns a const list view. Mutation or moving the builder invalidates it.
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

fn sumSegmentLens(segments: []const Segment) error{Overflow}!DmaRaw {
    var total: DmaRaw = 0;
    for (segments) |segment| {
        total = std.math.add(DmaRaw, total, segment.len_bytes) catch return error.Overflow;
    }
    return total;
}
