const registers = @import("stdx").arch.x86_64.registers;

export fn descriptorWrites(
    gdtr: *const registers.GDTR,
    idtr: *const registers.IDTR,
    tr: registers.TR,
    ldtr: registers.LDTR,
) void {
    gdtr.write();
    idtr.write();
    tr.write();
    ldtr.write();
}

export fn descriptorReads() void {
    _ = registers.GDTR.read();
    _ = registers.IDTR.read();
    _ = registers.TR.read();
    _ = registers.LDTR.read();
}
