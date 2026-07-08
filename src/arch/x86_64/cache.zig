//! x86_64 cache maintenance wrappers. Spec: docs/specs/arch/x86_64/base.md.

const std = @import("std");

const debug = @import("../../core/debug.zig");
const cpuid = @import("cpuid.zig");
const target = @import("target.zig");

const supported = target.supported;
const wrong_target = target.wrong_target;

/// L1 cache-line size in bytes, derived from `CPUID.1:EBX[15:8] * 8`.
/// Falls back to 64 when CPUID does not advertise a size.
pub fn lineSize() usize {
    if (!supported) @compileError(wrong_target);
    const ebx = cpuid.leaf(.feature_info).ebx;
    const clflush_qwords: u32 = (ebx >> 8) & 0xff;
    if (clflush_qwords == 0) return 64;
    return @as(usize, clflush_qwords) * 8;
}

/// Execute `clflush [addr]`.
/// Privilege: unprivileged.
/// Clobbers: `memory`.
pub fn flush(addr: usize) void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("clflush (%[addr])"
        :
        : [addr] "r" (addr),
        : .{ .memory = true });
}

/// Execute `clflushopt [addr]`.
/// Privilege: unprivileged.
/// Notes: may compile down to `clflush` when `clflushopt` is unavailable.
/// Clobbers: `memory`.
pub fn flushOptimized(addr: usize) void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("clflushopt (%[addr])"
        :
        : [addr] "r" (addr),
        : .{ .memory = true });
}

/// Execute `clwb [addr]`.
/// Privilege: unprivileged.
/// Notes: may compile down to `clflushopt` or `clflush` when unavailable.
/// Clobbers: `memory`.
pub fn writeBack(addr: usize) void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("clwb (%[addr])"
        :
        : [addr] "r" (addr),
        : .{ .memory = true });
}

/// Walk `[ptr, ptr + len)` in `lineSize()` steps, calling `flush` per line.
/// Privilege: unprivileged.
pub fn flushRange(ptr: [*]const u8, len: usize) void {
    if (!supported) @compileError(wrong_target);
    rangeWalk(ptr, len, flush);
}

/// Walk `[ptr, ptr + len)` in `lineSize()` steps, calling `writeBack` per
/// line.
/// Privilege: unprivileged.
pub fn writeBackRange(ptr: [*]const u8, len: usize) void {
    if (!supported) @compileError(wrong_target);
    rangeWalk(ptr, len, writeBack);
}

/// Execute `wbinvd`.
/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Clobbers: `memory`.
pub fn writeBackInvalidate() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("wbinvd" ::: .{ .memory = true });
}

/// Execute `invd`.
/// Privilege: CPL 0.
/// Faults: `#GP` at CPL > 0.
/// Notes: loses dirty cache state when no prior write-back was issued.
/// Clobbers: `memory`.
pub fn invalidate() void {
    if (!supported) @compileError(wrong_target);
    asm volatile ("invd" ::: .{ .memory = true });
}

fn rangeWalk(ptr: [*]const u8, len: usize, comptime op: fn (usize) void) void {
    if (!supported) @compileError(wrong_target);

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
