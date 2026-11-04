const registers = @import("stdx").arch.x86_64.registers;

export fn descriptorWrites(
    gdtr: *const registers.GDTR,
    idtr: *const registers.IDTR,
    tr: registers.TR.Word,
    ldtr: registers.LDTR.Word,
) void {
    gdtr.write();
    idtr.write();
    registers.TR.write(tr);
    registers.LDTR.write(ldtr);
}

export fn descriptorReads() void {
    _ = registers.GDTR.read();
    _ = registers.IDTR.read();
    _ = registers.TR.read();
    _ = registers.LDTR.read();
}
