//! Architecture-specific primitives. See `docs/specs/arch/x86_64.md`.

pub const x86_64 = @import("x86_64.zig");

test {
    _ = @import("x86_64/paging.zig");
    _ = @import("x86_64/cpuid.zig").unit;
    _ = @import("x86_64/cache.zig").unit;
    _ = @import("x86_64/descriptors.zig").unit;
    _ = @import("x86_64/register/control.zig").unit;
    _ = @import("x86_64/register/debug.zig").unit;
    _ = @import("x86_64/register/descriptor.zig").unit;
    _ = @import("x86_64/register/efer.zig").unit;
    _ = @import("x86_64/register/rflags.zig").unit;
    _ = @import("x86_64/register/segment.zig").unit;
}
