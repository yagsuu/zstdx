const target = @import("target.zig");

pub const Port = enum(u16) {
    _,

    const Self = @This();

    pub fn from(value: u16) Self {
        return @enumFromInt(value);
    }

    pub fn raw(self: Self) u16 {
        return @intFromEnum(self);
    }

    /// requires I/O permission through IOPL or the TSS I/O bitmap.
    pub fn in8(self: Self) u8 {
        comptime target.require();

        return asm volatile ("inb %[port], %[ret]"
            : [ret] "={al}" (-> u8),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    /// requires I/O permission through IOPL or the TSS I/O bitmap.
    pub fn in16(self: Self) u16 {
        comptime target.require();

        return asm volatile ("inw %[port], %[ret]"
            : [ret] "={ax}" (-> u16),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    /// requires I/O permission through IOPL or the TSS I/O bitmap.
    pub fn in32(self: Self) u32 {
        comptime target.require();

        return asm volatile ("inl %[port], %[ret]"
            : [ret] "={eax}" (-> u32),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    /// requires I/O permission through IOPL or the TSS I/O bitmap.
    pub fn out8(self: Self, value: u8) void {
        comptime target.require();

        asm volatile ("outb %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{al}" (value),
            : .{ .memory = true });
    }

    /// requires I/O permission through IOPL or the TSS I/O bitmap.
    pub fn out16(self: Self, value: u16) void {
        comptime target.require();

        asm volatile ("outw %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{ax}" (value),
            : .{ .memory = true });
    }

    /// requires I/O permission through IOPL or the TSS I/O bitmap.
    pub fn out32(self: Self, value: u32) void {
        comptime target.require();

        asm volatile ("outl %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{eax}" (value),
            : .{ .memory = true });
    }

    /// requires I/O permission and DF clear.
    pub fn inSlice8(self: Self, dst: []u8) void {
        comptime target.require();

        var ptr = dst.ptr;
        var count = dst.len;
        asm volatile ("rep insb"
            : [dst] "={rdi}" (ptr),
              [count] "={rcx}" (count),
            : [port] "{dx}" (@intFromEnum(self)),
              [initial_dst] "0" (ptr),
              [initial_count] "1" (count),
            : .{ .memory = true });
    }

    /// requires I/O permission and DF clear.
    pub fn inSlice16(self: Self, dst: []u16) void {
        comptime target.require();

        var ptr = dst.ptr;
        var count = dst.len;
        asm volatile ("rep insw"
            : [dst] "={rdi}" (ptr),
              [count] "={rcx}" (count),
            : [port] "{dx}" (@intFromEnum(self)),
              [initial_dst] "0" (ptr),
              [initial_count] "1" (count),
            : .{ .memory = true });
    }

    /// requires I/O permission and DF clear.
    pub fn inSlice32(self: Self, dst: []u32) void {
        comptime target.require();

        var ptr = dst.ptr;
        var count = dst.len;
        asm volatile ("rep insl"
            : [dst] "={rdi}" (ptr),
              [count] "={rcx}" (count),
            : [port] "{dx}" (@intFromEnum(self)),
              [initial_dst] "0" (ptr),
              [initial_count] "1" (count),
            : .{ .memory = true });
    }

    /// requires I/O permission and DF clear.
    pub fn outSlice8(self: Self, src: []const u8) void {
        comptime target.require();

        var ptr = src.ptr;
        var count = src.len;
        asm volatile ("rep outsb"
            : [src] "={rsi}" (ptr),
              [count] "={rcx}" (count),
            : [port] "{dx}" (@intFromEnum(self)),
              [initial_src] "0" (ptr),
              [initial_count] "1" (count),
            : .{ .memory = true });
    }

    /// requires I/O permission and DF clear.
    pub fn outSlice16(self: Self, src: []const u16) void {
        comptime target.require();

        var ptr = src.ptr;
        var count = src.len;
        asm volatile ("rep outsw"
            : [src] "={rsi}" (ptr),
              [count] "={rcx}" (count),
            : [port] "{dx}" (@intFromEnum(self)),
              [initial_src] "0" (ptr),
              [initial_count] "1" (count),
            : .{ .memory = true });
    }

    /// requires I/O permission and DF clear.
    pub fn outSlice32(self: Self, src: []const u32) void {
        comptime target.require();

        var ptr = src.ptr;
        var count = src.len;
        asm volatile ("rep outsl"
            : [src] "={rsi}" (ptr),
              [count] "={rcx}" (count),
            : [port] "{dx}" (@intFromEnum(self)),
              [initial_src] "0" (ptr),
              [initial_count] "1" (count),
            : .{ .memory = true });
    }
};

/// writes zero to port 0x80; any delay depends on the platform.
/// requires I/O permission through IOPL or the TSS I/O bitmap.
pub fn ioWait() void {
    comptime target.require();

    asm volatile ("outb %[v], $0x80"
        :
        : [v] "{al}" (@as(u8, 0)),
        : .{ .memory = true });
}
