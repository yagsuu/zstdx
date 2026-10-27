const InclusiveRange = @import("stdx").ranges.InclusiveRange;

export fn instantiateZeroWidth() void {
    _ = InclusiveRange(u0);
}
