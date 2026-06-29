//! Caller-buffer-backed bump arena for bounded construction phases, parsers,
//! boot-time setup, and tests. Borrows `[]u8`, bumps forward, never frees
//! individual allocations. See docs/specs/mem/fixed-buffer-arena.md.

const std = @import("std");

const alignment = @import("alignment.zig");

/// Bump arena over caller-owned `[]u8`. Lifecycle is `mark`/`restore` and
/// `reset`; every error leaves `index` unchanged.
pub const FixedBufferArena = struct {
    buffer: []u8,
    index: usize = 0,

    /// `OutOfMemory`: remaining capacity does not fit the request.
    /// `InvalidAlignment`: `byte_alignment` is zero or not a power of two.
    /// `Overflow`: alignment rounding or typed byte count exceeded `usize`.
    pub const Error = error{ OutOfMemory, InvalidAlignment, Overflow };

    /// Opaque checkpoint of the current allocation position.
    pub const Mark = struct {
        index: usize,
    };

    pub fn init(buffer: []u8) FixedBufferArena {
        return .{ .buffer = buffer };
    }

    pub fn assertValid(self: FixedBufferArena) void {
        std.debug.assert(self.isValid());
    }

    pub fn isValid(self: FixedBufferArena) bool {
        return self.index <= self.buffer.len;
    }

    pub fn capacity(self: FixedBufferArena) usize {
        self.assertValid();
        return self.buffer.len;
    }

    pub fn used(self: FixedBufferArena) usize {
        self.assertValid();
        return self.index;
    }

    pub fn remaining(self: FixedBufferArena) usize {
        self.assertValid();
        return self.buffer.len - self.index;
    }

    /// View of the un-allocated tail. Borrows the backing buffer.
    pub fn remainingBytes(self: FixedBufferArena) []u8 {
        self.assertValid();
        return self.buffer[self.index..];
    }

    pub fn mark(self: FixedBufferArena) Mark {
        self.assertValid();
        return .{ .index = self.index };
    }

    /// Restore `index` to `checkpoint`. Allocations made after the mark become
    /// undefined. Passing a mark from another arena or a forward-shifted index
    /// is a programmer error.
    pub fn restore(self: *FixedBufferArena, checkpoint: Mark) void {
        self.assertValid();
        std.debug.assert(checkpoint.index <= self.index);
        self.index = checkpoint.index;
    }

    /// Reset to a fresh arena over the same buffer. Invalidates every
    /// previously returned allocation.
    pub fn reset(self: *FixedBufferArena) void {
        self.index = 0;
    }

    /// Allocate `len` bytes with byte alignment 1.
    pub fn allocBytes(self: *FixedBufferArena, len: usize) Error![]u8 {
        return self.allocAlignedBytes(len, 1);
    }

    /// Allocate `len` bytes aligned to `byte_alignment`. Failure paths leave
    /// `index` unchanged. `len == 0` succeeds and does not advance.
    pub fn allocAlignedBytes(self: *FixedBufferArena, len: usize, byte_alignment: usize) Error![]u8 {
        self.assertValid();
        const absolute = @intFromPtr(self.buffer.ptr) + self.index;
        const aligned_absolute = alignment.alignUp(usize, absolute, byte_alignment) catch |err| return switch (err) {
            error.InvalidAlignment => error.InvalidAlignment,
            error.Overflow => error.Overflow,
        };
        if (len == 0) return self.buffer[self.index..self.index];
        const padding = aligned_absolute - absolute;
        const start = std.math.add(usize, self.index, padding) catch return error.Overflow;
        const end = std.math.add(usize, start, len) catch return error.Overflow;
        if (end > self.buffer.len) return error.OutOfMemory;
        const out = self.buffer[start..end];
        self.index = end;
        return out;
    }

    /// Allocate one uninitialized `T` aligned to `@alignOf(T)`.
    pub fn alloc(self: *FixedBufferArena, comptime T: type) Error!*T {
        comptime if (@sizeOf(T) == 0) @compileError("cannot allocate zero-sized type");
        const bytes = try self.allocAlignedBytes(@sizeOf(T), @alignOf(T));
        return @ptrCast(@alignCast(bytes.ptr));
    }

    /// Allocate `len` uninitialized `T` values contiguously. Returns
    /// `error.Overflow` when `@sizeOf(T) * len` overflows.
    pub fn allocSlice(self: *FixedBufferArena, comptime T: type, len: usize) Error![]T {
        comptime if (@sizeOf(T) == 0) @compileError("cannot allocate zero-sized type");
        const byte_count = std.math.mul(usize, @sizeOf(T), len) catch return error.Overflow;
        if (len == 0) return &[_]T{};
        const bytes = try self.allocAlignedBytes(byte_count, @alignOf(T));
        const ptr: [*]T = @ptrCast(@alignCast(bytes.ptr));
        return ptr[0..len];
    }

    /// `std.mem.Allocator` view backed by the same arena state. Allocation
    /// and exhaustion rules match the typed API; `free`, `resize`, and
    /// `remap` are no-ops, so callers use `mark`/`restore`/`reset` for
    /// lifecycle.
    pub fn allocator(self: *FixedBufferArena) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &allocator_vtable };
    }
};

const allocator_vtable = std.mem.Allocator.VTable{
    .alloc = allocatorAlloc,
    .resize = allocatorResize,
    .remap = allocatorRemap,
    .free = allocatorFree,
};

fn allocatorAlloc(ctx: *anyopaque, len: usize, alignment_value: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    _ = ret_addr;
    const self: *FixedBufferArena = @ptrCast(@alignCast(ctx));
    const bytes = self.allocAlignedBytes(len, alignment_value.toByteUnits()) catch return null;
    return bytes.ptr;
}

fn allocatorResize(ctx: *anyopaque, memory: []u8, alignment_value: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    _ = ctx;
    _ = memory;
    _ = alignment_value;
    _ = new_len;
    _ = ret_addr;
    return false;
}

fn allocatorRemap(ctx: *anyopaque, memory: []u8, alignment_value: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    _ = ctx;
    _ = memory;
    _ = alignment_value;
    _ = new_len;
    _ = ret_addr;
    return null;
}

fn allocatorFree(ctx: *anyopaque, memory: []u8, alignment_value: std.mem.Alignment, ret_addr: usize) void {
    _ = ctx;
    _ = memory;
    _ = alignment_value;
    _ = ret_addr;
}
