const registers = @import("stdx").arch.x86_64.registers;

export fn descriptorWrites(
    gdtr: registers.gdtr.GDTR,
    idtr: registers.idtr.IDTR,
    tr: registers.tr.TR,
    ldtr: registers.ldtr.LDTR,
) void {
    registers.gdtr.write(gdtr);
    registers.idtr.write(idtr);
    registers.tr.write(tr);
    registers.ldtr.write(ldtr);
}

export fn descriptorReads() void {
    _ = registers.gdtr.read();
    _ = registers.idtr.read();
    _ = registers.tr.read();
    _ = registers.ldtr.read();
}
