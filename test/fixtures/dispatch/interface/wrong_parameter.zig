const Interface = @import("stdx").dispatch.Interface;

const Contract = struct {
    instance: *anyopaque,
    vtable: *const Vtable,

    pub const Vtable = struct {
        run: *const fn (*anyopaque, u32) u32,
    };
};

const Provider = struct {
    pub fn run(_: *Provider, _: u64) u32 {
        return 0;
    }
};

export fn entry() void {
    var provider: Provider = .{};
    _ = Interface(Contract).bind(&provider);
}
