//! does not guarantee posted-write or device completion.

const fence = @import("arch").x86_64.fence;

/// orders prior stores before subsequent stores.
pub inline fn release() void {
    fence.sfence();
}

/// orders prior loads before subsequent loads.
pub inline fn acquire() void {
    fence.lfence();
}

/// orders prior loads and stores before subsequent loads and stores.
pub inline fn full() void {
    fence.mfence();
}
