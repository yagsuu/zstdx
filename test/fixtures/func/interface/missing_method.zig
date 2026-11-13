const Interface = @import("stdx").func.Interface;

const Contract = struct {
    instance: *anyopaque,
    vtable: *const Vtable,

    pub const Vtable = struct {
        run: *const fn (*anyopaque, u32) u32,
    };
};

const Provider = struct {};

export fn entry() void {
    var provider: Provider = .{};
    _ = Interface(Contract).bind(&provider);
}
