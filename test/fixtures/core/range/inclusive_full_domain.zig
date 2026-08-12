const InclusiveRange = @import("stdx").core.InclusiveRange;

export fn constructFullDomain() void {
    _ = InclusiveRange(u8).of(0, 255);
}
