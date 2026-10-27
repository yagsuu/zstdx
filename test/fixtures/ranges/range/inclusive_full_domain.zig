const InclusiveRange = @import("stdx").ranges.InclusiveRange;

export fn constructFullDomain() void {
    _ = InclusiveRange(u8).of(0, 255);
}
