//! Bump arena family. `Static(N)` owns inline storage; `Bounded` borrows
//! caller `[]u8`. See docs/specs/mem/arena-bounded.md and
//! docs/specs/mem/arena-static.md.

const std = @import("std");

const alignment = @import("alignment.zig");

/// `OutOfMemory`: remaining capacity does not fit the request.
/// `InvalidAlignment`: `byte_alignment` is zero or not a power of two.
/// `Overflow`: alignment rounding or typed byte count exceeded `usize`.
const ArenaError = error{ OutOfMemory, InvalidAlignment, Overflow };

/// Fixed-capacity bump arena family. Each variant exposes the same
/// `Error` set under its own type.
pub const Arena = struct {
    /// Borrowed `[]u8` bump arena. Owns nothing; the caller keeps `buffer`
    /// alive while any allocation is live.
    pub const Bounded = struct {
        buffer: []u8,
        index: usize = 0,

        pub const Error = ArenaError;

        /// Opaque checkpoint of the current allocation position.
        pub const Mark = struct {
            index: usize,
        };

        pub fn wrap(buffer: []u8) Bounded {
            return .{ .buffer = buffer };
        }

        pub fn assertValid(self: Bounded) void {
            std.debug.assert(self.isValid());
        }

        pub fn isValid(self: Bounded) bool {
            return self.index <= self.buffer.len;
        }

        pub fn capacity(self: Bounded) usize {
            return self.buffer.len;
        }

        pub fn used(self: Bounded) usize {
            return self.index;
        }

        pub fn remaining(self: Bounded) usize {
            return self.buffer.len - self.index;
        }

        /// View of the un-allocated tail. Borrows the backing buffer.
        pub fn remainingBytes(self: Bounded) []u8 {
            return self.buffer[self.index..];
        }

        pub fn mark(self: Bounded) Mark {
            return .{ .index = self.index };
        }

        /// Restore `index` to `checkpoint`. Allocations made after the mark
        /// become undefined. Passing a mark from another arena or a
        /// forward-shifted index is a programmer error.
        pub fn restore(self: *Bounded, checkpoint: Mark) void {
            std.debug.assert(checkpoint.index <= self.index);
            self.index = checkpoint.index;
        }

        /// Reset to a fresh arena over the same buffer. Invalidates every
        /// previously returned allocation.
        pub fn reset(self: *Bounded) void {
            self.index = 0;
        }

        /// Allocate `len` bytes with byte alignment 1.
        pub fn allocBytes(self: *Bounded, len: usize) Error![]u8 {
            return self.allocAlignedBytes(len, 1);
        }

        /// Allocate `len` bytes aligned to `byte_alignment`. Failure paths
        /// leave `index` unchanged. `len == 0` succeeds and does not advance.
        pub fn allocAlignedBytes(self: *Bounded, len: usize, byte_alignment: usize) Error![]u8 {
            return allocBytesInto(self.buffer, &self.index, len, byte_alignment);
        }

        /// Allocate one uninitialized `T` aligned to `@alignOf(T)`.
        pub fn alloc(self: *Bounded, comptime T: type) Error!*T {
            return allocOneInto(T, self.buffer, &self.index);
        }

        /// Allocate `len` uninitialized `T` values contiguously. Returns
        /// `error.Overflow` when `@sizeOf(T) * len` overflows.
        pub fn allocSlice(self: *Bounded, comptime T: type, len: usize) Error![]T {
            return allocSliceInto(T, self.buffer, &self.index, len);
        }

        /// `std.mem.Allocator` view backed by the same arena state.
        pub fn allocator(self: *Bounded) std.mem.Allocator {
            return .{ .ptr = self, .vtable = &bounded_allocator_vtable };
        }
    };

    /// Inline `[capacity_bytes]u8` bump arena. The arena value owns the
    /// backing storage. The value must not move while any allocation is
    /// live.
    pub fn Static(comptime capacity_bytes: usize) type {
        return struct {
            buffer: [capacity_bytes]u8 = undefined,
            index: usize = 0,

            const Self = @This();

            pub const Error = ArenaError;

            /// Opaque checkpoint of the current allocation position. Marks
            /// from one variant or one capacity cannot be restored into a
            /// different one.
            pub const Mark = struct {
                index: usize,
            };

            /// Comptime backing-buffer capacity in bytes.
            pub const byte_capacity = capacity_bytes;

            pub fn init() Self {
                return .{};
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }

            pub fn isValid(self: *const Self) bool {
                return self.index <= capacity_bytes;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return capacity_bytes;
            }

            pub fn used(self: *const Self) usize {
                return self.index;
            }

            pub fn remaining(self: *const Self) usize {
                return capacity_bytes - self.index;
            }

            /// View of the un-allocated tail. Borrows the inline buffer.
            pub fn remainingBytes(self: *Self) []u8 {
                return self.buffer[self.index..];
            }

            pub fn mark(self: *const Self) Mark {
                return .{ .index = self.index };
            }

            pub fn restore(self: *Self, checkpoint: Mark) void {
                std.debug.assert(checkpoint.index <= self.index);
                self.index = checkpoint.index;
            }

            pub fn reset(self: *Self) void {
                self.index = 0;
            }

            pub fn allocBytes(self: *Self, len: usize) Error![]u8 {
                return self.allocAlignedBytes(len, 1);
            }

            pub fn allocAlignedBytes(self: *Self, len: usize, byte_alignment: usize) Error![]u8 {
                return allocBytesInto(self.buffer[0..], &self.index, len, byte_alignment);
            }

            pub fn alloc(self: *Self, comptime T: type) Error!*T {
                return allocOneInto(T, self.buffer[0..], &self.index);
            }

            pub fn allocSlice(self: *Self, comptime T: type, len: usize) Error![]T {
                return allocSliceInto(T, self.buffer[0..], &self.index, len);
            }

            const allocator_vtable: std.mem.Allocator.VTable = .{
                .alloc = struct {
                    fn alloc(ctx: *anyopaque, len: usize, alignment_value: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
                        _ = ret_addr;
                        const self: *Self = @ptrCast(@alignCast(ctx));
                        const bytes = self.allocAlignedBytes(len, alignment_value.toByteUnits()) catch return null;
                        return bytes.ptr;
                    }
                }.alloc,
                .resize = noopResize,
                .remap = noopRemap,
                .free = noopFree,
            };

            pub fn allocator(self: *Self) std.mem.Allocator {
                return .{ .ptr = self, .vtable = &allocator_vtable };
            }
        };
    }
};

fn allocBytesInto(buffer: []u8, index: *usize, len: usize, byte_alignment: usize) ArenaError![]u8 {
    const absolute = @intFromPtr(buffer.ptr) + index.*;
    const aligned_absolute = alignment.alignUp(usize, absolute, byte_alignment) catch |err| switch (err) {
        error.InvalidAlignment => return error.InvalidAlignment,
        error.Overflow => return error.Overflow,
    };

    if (len == 0) return buffer[index.*..index.*];

    const padding = aligned_absolute - absolute;
    const start = std.math.add(usize, index.*, padding) catch return error.Overflow;
    const end = std.math.add(usize, start, len) catch return error.Overflow;
    if (end > buffer.len) return error.OutOfMemory;

    const out = buffer[start..end];
    index.* = end;
    return out;
}

fn allocOneInto(comptime T: type, buffer: []u8, index: *usize) ArenaError!*T {
    comptime if (@sizeOf(T) == 0) @compileError("cannot allocate zero-sized type");
    const bytes = try allocBytesInto(buffer, index, @sizeOf(T), @alignOf(T));
    return @ptrCast(@alignCast(bytes.ptr));
}

fn allocSliceInto(comptime T: type, buffer: []u8, index: *usize, len: usize) ArenaError![]T {
    comptime if (@sizeOf(T) == 0) @compileError("cannot allocate zero-sized type");
    const byte_count = std.math.mul(usize, @sizeOf(T), len) catch return error.Overflow;

    if (len == 0) return &[_]T{};

    const bytes = try allocBytesInto(buffer, index, byte_count, @alignOf(T));
    const ptr: [*]T = @ptrCast(@alignCast(bytes.ptr));
    return ptr[0..len];
}

const bounded_allocator_vtable = std.mem.Allocator.VTable{
    .alloc = boundedAlloc,
    .resize = noopResize,
    .remap = noopRemap,
    .free = noopFree,
};

fn boundedAlloc(ctx: *anyopaque, len: usize, alignment_value: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    _ = ret_addr;
    const self: *Arena.Bounded = @ptrCast(@alignCast(ctx));
    const bytes = self.allocAlignedBytes(len, alignment_value.toByteUnits()) catch return null;
    return bytes.ptr;
}

fn noopResize(ctx: *anyopaque, memory: []u8, alignment_value: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    _ = ctx;
    _ = memory;
    _ = alignment_value;
    _ = new_len;
    _ = ret_addr;
    return false;
}

fn noopRemap(
    ctx: *anyopaque,
    memory: []u8,
    alignment_value: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) ?[*]u8 {
    _ = ctx;
    _ = memory;
    _ = alignment_value;
    _ = new_len;
    _ = ret_addr;
    return null;
}

fn noopFree(ctx: *anyopaque, memory: []u8, alignment_value: std.mem.Alignment, ret_addr: usize) void {
    _ = ctx;
    _ = memory;
    _ = alignment_value;
    _ = ret_addr;
}
