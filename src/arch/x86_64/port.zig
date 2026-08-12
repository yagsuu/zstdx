//! x86_64 port I/O primitives. See `docs/specs/arch/x86_64.md`.

const target = @import("target.zig");

pub const Port = enum(u16) {
    _,

    pub fn fromInt(value: u16) Port {
        return @enumFromInt(value);
    }

    pub fn raw(self: Port) u16 {
        return @intFromEnum(self);
    }

    /// Privilege: IOPL/TSS I/O bitmap permits access.
    /// Faults: `#GP` when access is denied.
    /// Clobbers: `memory`.
    pub fn in8(self: Port) u8 {
        target.ensureSupported();

        return asm volatile ("inb %[port], %[ret]"
            : [ret] "={al}" (-> u8),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    /// Privilege: IOPL/TSS I/O bitmap permits access.
    /// Faults: `#GP` when access is denied.
    /// Clobbers: `memory`.
    pub fn in16(self: Port) u16 {
        target.ensureSupported();

        return asm volatile ("inw %[port], %[ret]"
            : [ret] "={ax}" (-> u16),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    /// Privilege: IOPL/TSS I/O bitmap permits access.
    /// Faults: `#GP` when access is denied.
    /// Clobbers: `memory`.
    pub fn in32(self: Port) u32 {
        target.ensureSupported();

        return asm volatile ("inl %[port], %[ret]"
            : [ret] "={eax}" (-> u32),
            : [port] "{dx}" (@intFromEnum(self)),
            : .{ .memory = true });
    }

    /// Privilege: IOPL/TSS I/O bitmap permits access.
    /// Faults: `#GP` when access is denied.
    /// Clobbers: `memory`.
    pub fn out8(self: Port, value: u8) void {
        target.ensureSupported();

        asm volatile ("outb %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{al}" (value),
            : .{ .memory = true });
    }

    /// Privilege: IOPL/TSS I/O bitmap permits access.
    /// Faults: `#GP` when access is denied.
    /// Clobbers: `memory`.
    pub fn out16(self: Port, value: u16) void {
        target.ensureSupported();

        asm volatile ("outw %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{ax}" (value),
            : .{ .memory = true });
    }

    /// Privilege: IOPL/TSS I/O bitmap permits access.
    /// Faults: `#GP` when access is denied.
    /// Clobbers: `memory`.
    pub fn out32(self: Port, value: u32) void {
        target.ensureSupported();

        asm volatile ("outl %[value], %[port]"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [value] "{eax}" (value),
            : .{ .memory = true });
    }

    /// Requirements: `DF` clear and slice alignment.
    /// Clobbers: `rcx`, `rdi`, `memory`.
    pub fn inSlice8(self: Port, dst: []u8) void {
        target.ensureSupported();

        asm volatile ("rep insb"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [dst] "{rdi}" (dst.ptr),
              [count] "{rcx}" (dst.len),
            : .{ .rcx = true, .rdi = true, .memory = true });
    }

    /// Requirements: `DF` clear and slice alignment.
    /// Clobbers: `rcx`, `rdi`, `memory`.
    pub fn inSlice16(self: Port, dst: []u16) void {
        target.ensureSupported();

        asm volatile ("rep insw"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [dst] "{rdi}" (dst.ptr),
              [count] "{rcx}" (dst.len),
            : .{ .rcx = true, .rdi = true, .memory = true });
    }

    /// Requirements: `DF` clear and slice alignment.
    /// Clobbers: `rcx`, `rdi`, `memory`.
    pub fn inSlice32(self: Port, dst: []u32) void {
        target.ensureSupported();

        asm volatile ("rep insl"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [dst] "{rdi}" (dst.ptr),
              [count] "{rcx}" (dst.len),
            : .{ .rcx = true, .rdi = true, .memory = true });
    }

    /// Requirements: `DF` clear and slice alignment.
    /// Clobbers: `rcx`, `rsi`, `memory`.
    pub fn outSlice8(self: Port, src: []const u8) void {
        target.ensureSupported();

        asm volatile ("rep outsb"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [src] "{rsi}" (src.ptr),
              [count] "{rcx}" (src.len),
            : .{ .rcx = true, .rsi = true, .memory = true });
    }

    /// Requirements: `DF` clear and slice alignment.
    /// Clobbers: `rcx`, `rsi`, `memory`.
    pub fn outSlice16(self: Port, src: []const u16) void {
        target.ensureSupported();

        asm volatile ("rep outsw"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [src] "{rsi}" (src.ptr),
              [count] "{rcx}" (src.len),
            : .{ .rcx = true, .rsi = true, .memory = true });
    }

    /// Requirements: `DF` clear and slice alignment.
    /// Clobbers: `rcx`, `rsi`, `memory`.
    pub fn outSlice32(self: Port, src: []const u32) void {
        target.ensureSupported();

        asm volatile ("rep outsl"
            :
            : [port] "{dx}" (@intFromEnum(self)),
              [src] "{rsi}" (src.ptr),
              [count] "{rcx}" (src.len),
            : .{ .rcx = true, .rsi = true, .memory = true });
    }
};

/// Privilege: IOPL/TSS I/O bitmap permits access.
/// Faults: `#GP` when access is denied.
/// Clobbers: `memory`.
pub fn ioWait() void {
    target.ensureSupported();

    asm volatile ("outb %[v], $0x80"
        :
        : [v] "{al}" (@as(u8, 0)),
        : .{ .memory = true });
}
