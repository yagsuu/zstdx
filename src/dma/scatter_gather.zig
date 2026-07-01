//! DMA segment lists and aligned append builders.
//! Spec: docs/specs/dma/scatter-gather.md.

const std = @import("std");

const address = @import("../addr/address.zig");
const bits = @import("../bits.zig");
const buffer = @import("buffer.zig");

const DmaAddr = address.DmaAddr;
const DmaRaw = DmaAddr.Raw;

/// Untyped device-visible range descriptor.
pub const Segment = struct {
    addr: DmaAddr,
    len_bytes: usize,

    pub const Address = DmaAddr;

    /// `Misaligned`: builder alignment rejection.
    /// `Overflow`: `addr.raw() + len_bytes` exceeds `Address.Raw`.
    pub const Error = error{ Misaligned, Overflow };

    /// Validated `[addr, addr + len_bytes)` segment.
    pub fn init(addr: DmaAddr, len_bytes: usize) Error!Segment {
        const len_raw: DmaRaw = std.math.cast(DmaRaw, len_bytes) orelse return error.Overflow;
        _ = std.math.add(DmaRaw, addr.raw(), len_raw) catch return error.Overflow;
        return .{ .addr = addr, .len_bytes = len_bytes };
    }

    /// Segment covering the whole `Buffer(T)`.
    pub fn fromBuffer(comptime T: type, buf: buffer.Buffer(T)) Segment {
        const byte_len_raw = buf.byteLen();
        const byte_len = std.math.cast(usize, byte_len_raw) orelse unreachable;
        return .{ .addr = buf.dmaAddr(), .len_bytes = byte_len };
    }

    pub fn byteLen(self: Segment) usize {
        return self.len_bytes;
    }

    pub fn isEmpty(self: Segment) bool {
        return self.len_bytes == 0;
    }

    /// One-past-the-end device address; revalidates hand-built segments.
    pub fn endAddr(self: Segment) Error!DmaAddr {
        const len_raw: DmaRaw = std.math.cast(DmaRaw, self.len_bytes) orelse return error.Overflow;
        const raw = std.math.add(DmaRaw, self.addr.raw(), len_raw) catch return error.Overflow;
        return DmaAddr.fromInt(raw);
    }

    /// True iff both `addr` and `len_bytes` are aligned.
    /// Invalid alignment returns `false`.
    pub fn isAligned(self: Segment, alignment: DmaRaw) bool {
        if (alignment == 0) return false;
        if (!bits.isPowerOfTwo(DmaRaw, alignment)) return false;
        const mask = alignment - 1;
        if ((self.addr.raw() & mask) != 0) return false;
        const len_raw: DmaRaw = std.math.cast(DmaRaw, self.len_bytes) orelse return false;
        return (len_raw & mask) == 0;
    }

    pub fn assertValid(self: Segment) void {
        const len_raw: DmaRaw = std.math.cast(DmaRaw, self.len_bytes) orelse unreachable;
        _ = std.math.add(DmaRaw, self.addr.raw(), len_raw) catch unreachable;
    }
};

/// Segment lists; `Static(N)` owns storage, `Bounded` borrows it.
pub const List = struct {
    /// Inline segment storage; zero capacity is valid.
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

            /// Sum `len_bytes`; returns `error.Overflow` on `usize` wrap.
            pub fn totalByteLen(self: *const Self) error{Overflow}!usize {
                return sumSegmentLens(self.asConstSlice());
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.count <= segment_capacity);
                for (self.buffer[0..self.count]) |segment| segment.assertValid();
            }
        };
    }

    /// Borrowed segment storage; capacity is `buffer.len`.
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

        pub fn totalByteLen(self: *const Bounded) error{Overflow}!usize {
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

/// Uniform per-segment alignment on append.
pub const Builder = struct {
    /// Builder over inline segment storage.
    pub fn Static(comptime capacity_segments: usize, comptime alignment: DmaRaw) type {
        comptime requireAlignment(alignment);
        return struct {
            list: List.Static(capacity_segments) = .{},

            const Self = @This();
            const InnerList = List.Static(capacity_segments);

            /// `Full`: underlying list at capacity.
            /// `Misaligned`: segment fails `isAligned(alignment)`.
            pub const Error = error{ Full, Misaligned };

            /// Uniform per-segment alignment for this builder.
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

            /// Misalignment is reported before capacity; errors leave the list unchanged.
            pub fn append(self: *Self, segment: Segment) Error!void {
                if (alignment != 1 and !segment.isAligned(alignment)) return error.Misaligned;
                self.list.append(segment) catch |err| switch (err) {
                    error.Full => return error.Full,
                };
            }

            pub fn appendBuffer(self: *Self, comptime T: type, buf: buffer.Buffer(T)) Error!void {
                return self.append(Segment.fromBuffer(T, buf));
            }

            /// Const list view; invalidated by mutation or moving the builder.
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

    /// Builder over borrowed segment storage.
    pub fn Bounded(comptime alignment: DmaRaw) type {
        comptime requireAlignment(alignment);
        return struct {
            list: List.Bounded,

            const Self = @This();

            /// `Full`: underlying list at capacity.
            /// `Misaligned`: segment fails `isAligned(alignment)`.
            pub const Error = error{ Full, Misaligned };

            /// Uniform per-segment alignment for this builder.
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

            /// Misalignment is reported before capacity; errors leave the list unchanged.
            pub fn append(self: *Self, segment: Segment) Error!void {
                if (alignment != 1 and !segment.isAligned(alignment)) return error.Misaligned;
                self.list.append(segment) catch |err| switch (err) {
                    error.Full => return error.Full,
                };
            }

            pub fn appendBuffer(self: *Self, comptime T: type, buf: buffer.Buffer(T)) Error!void {
                return self.append(Segment.fromBuffer(T, buf));
            }

            /// Const list view; invalidated by mutation or moving the builder.
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

fn sumSegmentLens(segments: []const Segment) error{Overflow}!usize {
    var total: usize = 0;
    for (segments) |segment| {
        total = std.math.add(usize, total, segment.len_bytes) catch return error.Overflow;
    }
    return total;
}
