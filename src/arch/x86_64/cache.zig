//! x86_64 cache maintenance wrappers. Spec: docs/specs/arch/x86_64/base.md.

const std = @import("std");

const debug = @import("../../core/debug.zig");
const cpuid = @import("cpuid.zig");
const target = @import("target.zig");

/// Cache-flush line size in bytes, from `CPUID.1:EBX[15:8] * 8`.
/// Falls back to 64 when CPUID does not advertise a size.
pub fn lineSize() usize {
    target.ensureSupported();

    const ebx = cpuid.leaf(.feature_info).ebx;
    const clflush_qwords: u32 = (ebx >> 8) & 0xff;
    if (clflush_qwords == 0) return 64;

    return @as(usize, clflush_qwords) * 8;
}

/// Execute `clflush [addr]`.
/// Privilege: unprivileged.
/// Clobbers: `memory`.
pub fn flush(addr: usize) void {
    target.ensureSupported();
    asm volatile ("clflush (%[addr])"
        :
        : [addr] "r" (addr),
        : .{ .memory = true });
}

/// Execute `clflushopt [addr]`.
/// Privilege: unprivileged.
/// Requirements: CPUID leaf 7 subleaf 0 `EBX.CLFLUSHOPT`.
/// Clobbers: `memory`.
pub fn flushOptimized(addr: usize) void {
    target.ensureSupported();
    asm volatile ("clflushopt (%[addr])"
        :
        : [addr] "r" (addr),
        : .{ .memory = true });
}

/// Execute `clwb [addr]`.
/// Privilege: unprivileged.
/// Requirements: CPUID leaf 7 subleaf 0 `EBX.CLWB`.
/// Clobbers: `memory`.
pub fn writeBack(addr: usize) void {
    target.ensureSupported();
    asm volatile ("clwb (%[addr])"
        :
        : [addr] "r" (addr),
        : .{ .memory = true });
}

/// Flush every cache line intersecting `[ptr, ptr + len)`.
/// Contract: `ptr + len` must not wrap; `len == 0` does nothing.
/// Privilege: unprivileged.
pub fn flushRange(ptr: [*]const u8, len: usize) void {
    target.ensureSupported();
    rangeWalk(ptr, len, flush);
}

/// Write back every cache line intersecting `[ptr, ptr + len)`.
/// Contract: `ptr + len` must not wrap; `len == 0` does nothing.
/// Privilege: unprivileged.
pub fn writeBackRange(ptr: [*]const u8, len: usize) void {
    target.ensureSupported();
    rangeWalk(ptr, len, writeBack);
}

/// Execute `wbinvd`.
/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Clobbers: `memory`.
pub fn writeBackInvalidate() void {
    target.ensureSupported();
    asm volatile ("wbinvd" ::: .{ .memory = true });
}

/// Execute `invd`.
/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Notes: loses dirty cache state when no prior write-back was issued.
/// Clobbers: `memory`.
pub fn invalidate() void {
    target.ensureSupported();
    asm volatile ("invd" ::: .{ .memory = true });
}

fn rangeWalk(ptr: [*]const u8, len: usize, comptime op: fn (usize) void) void {
    target.ensureSupported();

    const line = lineSize();

    std.debug.assert(line > 0);
    std.debug.assert(std.math.isPowerOfTwo(line));

    const start = @intFromPtr(ptr);
    if (debug.checksEnabled(.build_mode)) {
        std.debug.assert(len <= std.math.maxInt(usize) - start);
    }

    const end = std.math.add(usize, start, len) catch return;
    if (len == 0) return;

    var cursor = start & ~(line - 1);
    while (cursor < end) : (cursor += line) {
        op(cursor);
    }
}
