const InclusiveRange = @import("stdx").ranges.InclusiveRange;

export fn instantiateSigned() void {
    _ = InclusiveRange(i8);
}
