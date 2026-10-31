//! Architecture-specific primitives. See `docs/specs/arch/x86_64.md`.

pub const x86_64 = @import("x86_64.zig");

test {
    _ = @import("x86_64/cpuid.zig").unit;
    _ = @import("x86_64/cache.zig").unit;
}
