const InclusiveRange = @import("stdx").core.InclusiveRange;

export fn instantiateZeroWidth() void {
    _ = InclusiveRange(u0);
}
