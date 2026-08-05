//! Bump arenas. `Static(N)` owns inline storage; `Bounded` borrows caller bytes.

const std = @import("std");

const align_ops = @import("../align.zig");

/// `OutOfMemory`: remaining capacity does not fit the request.
/// `InvalidAlignment`: `byte_alignment` is zero or not a power of two.
/// `Overflow`: alignment rounding or typed byte count exceeded `usize`.
pub const ArenaAllocationError = error{ OutOfMemory, Overflow };
pub const ArenaError = error{ OutOfMemory, InvalidAlignment, Overflow };
pub const AllocationError = ArenaAllocationError;
pub const Error = ArenaError;

pub const Arena = struct {
    /// Borrows `buffer`; it must outlive every allocation.
    pub const Bounded = struct {
        buffer: []u8,
        index: usize = 0,

        pub const Mark = struct {
            index: usize,
        };

        pub const Error = ArenaError;
        pub const AllocationError = ArenaAllocationError;

        pub fn wrap(buffer: []u8) Bounded {
            return .{ .buffer = buffer };
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

        pub fn remainingBytes(self: Bounded) []u8 {
            return self.buffer[self.index..];
        }

        /// Uses byte alignment 1.
        pub fn allocBytes(self: *Bounded, len: usize) ArenaAllocationError![]u8 {
            return allocBytesInto(self.buffer, &self.index, len, 1) catch |err| switch (err) {
                error.InvalidAlignment => unreachable,
                error.OutOfMemory => return error.OutOfMemory,
                error.Overflow => return error.Overflow,
            };
        }

        /// Does not advance `index` on error or when `len == 0`.
        pub fn allocAlignedBytes(self: *Bounded, len: usize, byte_alignment: usize) ArenaError![]u8 {
            return allocBytesInto(self.buffer, &self.index, len, byte_alignment);
        }

        /// Returns uninitialized storage aligned to `@alignOf(T)`.
        pub fn alloc(self: *Bounded, comptime T: type) ArenaAllocationError!*T {
            return allocOneInto(T, self.buffer, &self.index);
        }

        /// Returns contiguous uninitialized storage.
        pub fn allocSlice(self: *Bounded, comptime T: type, len: usize) ArenaAllocationError![]T {
            return allocSliceInto(T, self.buffer, &self.index, len);
        }

        /// Views the same arena as `std.mem.Allocator`.
        pub fn allocator(self: *Bounded) std.mem.Allocator {
            return .{ .ptr = self, .vtable = &bounded_allocator_vtable };
        }

        pub fn mark(self: Bounded) Mark {
            return .{ .index = self.index };
        }

        /// Invalidates allocations after `checkpoint`.
        /// A forward or foreign mark is a programmer error.
        pub fn restore(self: *Bounded, checkpoint: Mark) void {
            std.debug.assert(checkpoint.index <= self.index);
            self.index = checkpoint.index;
        }

        /// Resets the arena and invalidates outstanding allocations.
        pub fn reset(self: *Bounded) void {
            self.index = 0;
        }

        pub fn isValid(self: Bounded) bool {
            return self.index <= self.buffer.len;
        }

        pub fn assertValid(self: Bounded) void {
            std.debug.assert(self.isValid());
        }
    };

    /// Owns inline storage. Do not move the arena while allocations are live.
    pub fn Static(comptime capacity_bytes: usize) type {
        comptime if (capacity_bytes == 0) @compileError("Arena.Static capacity_bytes must be non-zero");
        return struct {
            buffer: [capacity_bytes]u8 = undefined,
            index: usize = 0,

            /// Checkpoint type for this arena variant and capacity.
            pub const Mark = struct {
                index: usize,
            };

            const Self = @This();

            pub const Error = ArenaError;
            pub const AllocationError = ArenaAllocationError;
            pub const byte_capacity = capacity_bytes;

            pub fn init() Self {
                return .{};
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

            pub fn remainingBytes(self: *Self) []u8 {
                return self.buffer[self.index..];
            }

            /// Uses byte alignment 1.
            pub fn allocBytes(self: *Self, len: usize) ArenaAllocationError![]u8 {
                return allocBytesInto(self.buffer[0..], &self.index, len, 1) catch |err| switch (err) {
                    error.InvalidAlignment => unreachable,
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Overflow => return error.Overflow,
                };
            }

            /// Does not advance `index` on error or when `len == 0`.
            pub fn allocAlignedBytes(self: *Self, len: usize, byte_alignment: usize) ArenaError![]u8 {
                return allocBytesInto(self.buffer[0..], &self.index, len, byte_alignment);
            }

            /// Returns uninitialized storage aligned to `@alignOf(T)`.
            pub fn alloc(self: *Self, comptime T: type) ArenaAllocationError!*T {
                return allocOneInto(T, self.buffer[0..], &self.index);
            }

            /// Returns contiguous uninitialized storage.
            pub fn allocSlice(self: *Self, comptime T: type, len: usize) ArenaAllocationError![]T {
                return allocSliceInto(T, self.buffer[0..], &self.index, len);
            }

            /// Views the same arena as `std.mem.Allocator`.
            pub fn allocator(self: *Self) std.mem.Allocator {
                return .{ .ptr = self, .vtable = &allocator_vtable };
            }

            pub fn mark(self: *const Self) Mark {
                return .{ .index = self.index };
            }

            /// Invalidates allocations after `checkpoint`.
            /// A forward or foreign mark is a programmer error.
            pub fn restore(self: *Self, checkpoint: Mark) void {
                std.debug.assert(checkpoint.index <= self.index);
                self.index = checkpoint.index;
            }

            /// Resets the arena and invalidates outstanding allocations.
            pub fn reset(self: *Self) void {
                self.index = 0;
            }

            pub fn isValid(self: *const Self) bool {
                return self.index <= capacity_bytes;
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
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
        };
    }
};

fn allocBytesInto(buffer: []u8, index: *usize, len: usize, byte_alignment: usize) ArenaError![]u8 {
    const absolute = @intFromPtr(buffer.ptr) + index.*;
    const aligned_absolute = align_ops.alignUp(usize, absolute, byte_alignment) catch |err| switch (err) {
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

fn allocOneInto(comptime T: type, buffer: []u8, index: *usize) ArenaAllocationError!*T {
    comptime if (@sizeOf(T) == 0) @compileError("cannot allocate zero-sized type");
    const bytes = allocBytesInto(buffer, index, @sizeOf(T), @alignOf(T)) catch |err| switch (err) {
        error.InvalidAlignment => unreachable,
        error.OutOfMemory => return error.OutOfMemory,
        error.Overflow => return error.Overflow,
    };
    return @ptrCast(@alignCast(bytes.ptr));
}

fn allocSliceInto(comptime T: type, buffer: []u8, index: *usize, len: usize) ArenaAllocationError![]T {
    comptime if (@sizeOf(T) == 0) @compileError("cannot allocate zero-sized type");
    const byte_count = std.math.mul(usize, @sizeOf(T), len) catch return error.Overflow;

    if (len == 0) return &[_]T{};

    const bytes = allocBytesInto(buffer, index, byte_count, @alignOf(T)) catch |err| switch (err) {
        error.InvalidAlignment => unreachable,
        error.OutOfMemory => return error.OutOfMemory,
        error.Overflow => return error.Overflow,
    };
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
